#!/usr/bin/env python3
"""Real loopback integration, using synthetic frames. No screen access."""
import base64, concurrent.futures, http.client, pathlib, socket, subprocess, time, tempfile, shutil
root = pathlib.Path(__file__).resolve().parents[1]
relocated = tempfile.TemporaryDirectory(prefix='screentask-smoke-')
bundle = pathlib.Path(relocated.name) / 'ScreenTask Mac.app'
shutil.copytree(root / 'dist/ScreenTask Mac.app', bundle)
app = bundle / 'Contents/MacOS/ScreenTaskMac'
def exchange(port, path='/', headers=None, method='GET'):
    conn = http.client.HTTPConnection('127.0.0.1', port, timeout=3)
    try:
        conn.request(method, path, headers=headers or {})
        r = conn.getresponse()
        return r.status, dict(r.getheaders()), r.read()
    finally: conn.close()
for private in (False, True):
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
    process = subprocess.Popen([str(app), '--smoke-server', '--port', str(port)] + (['--private'] if private else []), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        for attempt in range(80):
            if process.poll() is not None:
                raise AssertionError(process.communicate()[1].decode())
            try:
                status, _, _ = exchange(port)
                break
            except (OSError, http.client.HTTPException): time.sleep(.1)
        else: raise AssertionError('server not ready')
        auth = {'Authorization': 'Basic ' + base64.b64encode(b'tester:test-only').decode()} if private else {}
        if private:
            assert exchange(port)[0] == 401
            assert exchange(port, '/ScreenTask.jpg')[0] == 401
            assert exchange(port, '/frame.jpg', {'Authorization': 'Basic !!!'})[0] == 401
        status, headers, body = exchange(port, headers=auth)
        assert status == 200 and b'ScreenTask Mac' in body
        status, headers, jpeg = exchange(port, '/ScreenTask.jpg?cache=1', auth)
        assert status == 200 and jpeg[:2] == b'\xff\xd8' and jpeg[-2:] == b'\xff\xd9'
        assert headers['Content-Type'] == 'image/jpeg'
        assert exchange(port, '/ScreenTask.jpg', auth, 'HEAD')[2] == b''
        assert exchange(port, '/../../etc/passwd', auth)[0] == 404
        assert exchange(port, '/', auth, 'POST')[0] == 405
        with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
            assert all(s == 200 for s in pool.map(lambda _: exchange(port, '/frame.jpg', auth)[0], range(48)))
        with socket.create_connection(('127.0.0.1', port), timeout=3) as sock:
            sock.sendall(b'GET / HTTP/1.1\r\nX: ' + b'a' * 17000)
            assert b'431' in sock.recv(2048)
        with socket.create_connection(('127.0.0.1', port), timeout=3) as sock:
            sock.sendall(b'GET / HTTP/1.1\r\nBad\r\n\r\n')
            assert b'400' in sock.recv(2048)
    finally:
        process.terminate()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.kill(); process.wait()
    try: exchange(port)
    except OSError: pass
    else: raise AssertionError('server still reachable after stop')
relocated.cleanup()
print('HTTP SMOKE PASSED')
