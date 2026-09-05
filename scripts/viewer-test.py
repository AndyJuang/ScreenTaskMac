#!/usr/bin/env python3
"""Viewer-page behaviour in real browser engines, against the app in --smoke-server mode.

Optional check: it needs Playwright (`pip install playwright && playwright install`), which is a
development-only tool and never ships in the app. Without it the script skips instead of failing.
No screen is captured: the smoke server serves two synthetic frames alternately.
"""
import hashlib, os, pathlib, socket, subprocess, sys, time, http.client

try:
    from playwright.sync_api import sync_playwright
except ImportError:
    print('VIEWER TEST SKIPPED (install Playwright to run it: pip install playwright && playwright install)')
    sys.exit(0)

root = pathlib.Path(__file__).resolve().parents[1]
app = root / 'dist/ScreenTask Mac.app/Contents/MacOS/ScreenTaskMac'
if not app.exists():
    print('VIEWER TEST SKIPPED (run scripts/build-app.sh first)')
    sys.exit(0)

STATE = """() => ({status: document.getElementById('status').textContent,
 hidden: document.getElementById('screen').hidden, width: document.getElementById('screen').naturalWidth,
 message: document.getElementById('message').textContent,
 intervalDisabled: document.getElementById('interval').disabled})"""

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)
        print('  FAIL:', message)


def start(port):
    process = subprocess.Popen([str(app), '--smoke-server', '--port', str(port)],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(80):
        if process.poll() is not None:
            raise AssertionError('smoke server exited')
        try:
            connection = http.client.HTTPConnection('127.0.0.1', port, timeout=2)
            connection.request('GET', '/')
            connection.getresponse().read()
            connection.close()
            return process
        except OSError:
            time.sleep(.1)
    process.terminate()
    raise AssertionError('smoke server not ready')


def free_port():
    """A fresh port per engine: TIME_WAIT outlives a run and would poison the next one."""
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


def sockets(port, state):
    """Server-side sockets only: a loopback connection shows up once per end."""
    output = subprocess.run(['netstat', '-an', '-p', 'tcp'], capture_output=True, text=True).stdout
    count = 0
    for line in output.splitlines():
        columns = line.split()
        if len(columns) >= 6 and columns[3].endswith(f'.{port}') and columns[5] == state:
            count += 1
    return count


def wait_for(page, predicate, seconds=20):
    """Viewer transitions are timer-driven (6 s stream watchdog, 3 s heartbeat), so poll, never sleep."""
    deadline = time.time() + seconds
    while time.time() < deadline:
        state = page.evaluate(STATE)
        if predicate(state):
            return state
        time.sleep(.5)
    return page.evaluate(STATE)


def frames_rendered(page, samples=10, gap=.25):
    """Screenshots, not canvas: Firefox draws a multipart <img> to canvas from its first frame."""
    seen = set()
    for _ in range(samples):
        seen.add(hashlib.sha256(page.locator('#screen').screenshot()).hexdigest())
        time.sleep(gap)
    return len(seen)


with sync_playwright() as playwright:
    # SCREENTASK_VIEWER_ENGINES narrows the run, for CI machines without every engine installed.
    engines = os.environ.get('SCREENTASK_VIEWER_ENGINES', 'chromium,webkit,firefox').split(',')
    for index, engine in enumerate(engine.strip() for engine in engines):
        port = free_port()
        process = start(port)
        browser = getattr(playwright, engine).launch()
        page = browser.new_page()
        errors = []
        page.on('pageerror', lambda error: errors.append(str(error)))
        try:
            page.goto(f'http://127.0.0.1:{port}/', wait_until='domcontentloaded')
            time.sleep(3)
            state = page.evaluate(STATE)
            print(f'[{engine}] stream: {state}')
            check('串流' in state['status'] and not state['hidden'] and state['width'] > 0,
                  f'{engine}: stream did not start ({state})')
            check(state['intervalDisabled'], f'{engine}: interval field must be disabled while streaming')

            distinct = frames_rendered(page)
            print(f'[{engine}] distinct rendered frames in 2.5 s: {distinct}')
            check(distinct > 1, f'{engine}: rendered image never changed, the stream is not live')

            # Persistent connections: the old build opened and closed one for every frame.
            churn = sockets(port, 'TIME_WAIT')
            print(f'[{engine}] closed connections in TIME_WAIT: {churn}')
            check(churn <= 5, f'{engine}: {churn} connections closed, expected persistent ones')

            # Pause must release the stream, and resume must not leak a socket each cycle.
            open_before = sockets(port, 'ESTABLISHED')
            page.click('#toggle')
            time.sleep(1.5)
            check(page.evaluate("() => document.getElementById('status').textContent") == '已暫停',
                  f'{engine}: pause did not update the status')
            paused_sockets = sockets(port, 'ESTABLISHED')
            check(paused_sockets < open_before,
                  f'{engine}: pause left {paused_sockets} connections open, was {open_before}')
            # A paused viewer shows a message, never a src-less image drawn as a broken-image glyph.
            paused = page.evaluate(STATE)
            check(paused['hidden'] and '暫停' in paused['message'],
                  f'{engine}: paused viewer shows a broken image ({paused})')
            # A heartbeat cut short by pausing is this page stopping, not the sharer disconnecting.
            time.sleep(2.5)
            settled = page.evaluate(STATE)
            check(settled['status'] == '已暫停', f'{engine}: pause drifted to {settled["status"]!r}')
            page.click('#toggle')
            resumed = wait_for(page, lambda state: '串流' in state['status'] and not state['hidden'])
            check('串流' in resumed['status'] and not resumed['hidden'] and resumed['width'] > 0,
                  f'{engine}: resume failed ({resumed})')
            for _ in range(3):
                page.click('#toggle')
                time.sleep(1)
                page.click('#toggle')
                wait_for(page, lambda state: '串流' in state['status'] and not state['hidden'], seconds=10)
            cycled = sockets(port, 'ESTABLISHED')
            print(f'[{engine}] connections open after 4 pause cycles: {cycled} (started at {open_before})')
            check(cycled <= open_before, f'{engine}: pause/resume leaks connections ({open_before} then {cycled})')

            # A stopped sharer must be reported, not left as a frozen last frame.
            process.terminate()
            process.wait()
            stopped = wait_for(page, lambda state: state['hidden'])
            print(f'[{engine}] sharer stopped: {stopped}')
            check(stopped['status'] == '等待重新連線' and stopped['hidden'],
                  f'{engine}: a stopped sharer was not detected ({stopped})')

            process = start(port)
            back = wait_for(page, lambda state: '串流' in state['status'] and not state['hidden'])
            print(f'[{engine}] sharer back: {back}')
            check('串流' in back['status'] and not back['hidden'] and back['width'] > 0,
                  f'{engine}: viewer did not reconnect by itself ({back})')

            # A browser that cannot stream must fall back to polling, with the interval usable again.
            polling = browser.new_page()
            polling.route('**/stream.mjpg*', lambda route: route.abort())
            polling.goto(f'http://127.0.0.1:{port}/', wait_until='domcontentloaded')
            state = wait_for(polling, lambda state: '逐張' in state['status'] and state['width'] > 0)
            print(f'[{engine}] polling fallback: {state}')
            check('逐張' in state['status'] and not state['hidden'] and state['width'] > 0
                  and not state['intervalDisabled'], f'{engine}: polling fallback failed ({state})')

            # Polling is a fallback, not a verdict: it must retry the stream even after the tab was
            # hidden, which clears the retry timer. Slow (a 30 s timer), so one engine covers it.
            if index == 0:
                polling.unroute('**/stream.mjpg*')
                polling.evaluate("() => document.dispatchEvent(new Event('visibilitychange'))")
                time.sleep(1)
                upgraded = wait_for(polling, lambda state: '串流' in state['status'], seconds=50)
                print(f'[{engine}] upgrade back to streaming: {upgraded["status"]}')
                check('串流' in upgraded['status'],
                      f'{engine}: stayed on polling after a visibility change ({upgraded})')
            check(not errors, f'{engine}: page errors {errors}')
        finally:
            browser.close()
            process.terminate()

if failures:
    print('VIEWER TEST FAILED: ' + '; '.join(failures))
    sys.exit(1)
print('VIEWER TEST PASSED')
