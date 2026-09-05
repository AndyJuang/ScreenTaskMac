#!/usr/bin/env python3
"""Real loopback integration, using synthetic frames. No screen access."""
import base64, concurrent.futures, http.client, pathlib, re, socket, subprocess, time, tempfile, shutil
root = pathlib.Path(__file__).resolve().parents[1]
relocated = tempfile.TemporaryDirectory(prefix='screentask-smoke-')
bundle = pathlib.Path(relocated.name) / 'ScreenTask Mac.app'
shutil.copytree(root / 'dist/ScreenTask Mac.app', bundle)
app = bundle / 'Contents/MacOS/ScreenTaskMac'
def read_head(sock, buffered=b''):
    data = buffered
    while b'\r\n\r\n' not in data:
        chunk = sock.recv(4096)
        if not chunk: raise AssertionError('connection closed before headers')
        data += chunk
    head, rest = data.split(b'\r\n\r\n', 1)
    return head, rest
def read_body(sock, length, buffered=b''):
    data = buffered
    while len(data) < length:
        chunk = sock.recv(65536)
        if not chunk: raise AssertionError('connection closed mid-body')
        data += chunk
    return data[:length], data[length:]
def live_sockets(port):
    output = subprocess.run(['netstat', '-an', '-p', 'tcp'], capture_output=True, text=True).stdout
    return sum(1 for line in output.splitlines()
               if len(line.split()) >= 6 and line.split()[3].endswith(f'.{port}') and line.split()[5] == 'ESTABLISHED')
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
            assert exchange(port, '/stream.mjpg')[0] == 401
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
        # One connection, three requests: proves responses are framed for reuse, not per-frame sockets.
        line = ('Authorization: Basic ' + base64.b64encode(b'tester:test-only').decode() + '\r\n') if private else ''
        head_bytes = ('GET /ScreenTask.jpg HTTP/1.1\r\nHost: 127.0.0.1\r\n' + line + '\r\n').encode()
        with socket.create_connection(('127.0.0.1', port), timeout=5) as sock:
            rest = b''
            for _ in range(3):
                sock.sendall(head_bytes)
                head, rest = read_head(sock, rest)
                assert b' 200 OK' in head and b'Connection: keep-alive' in head, head
                body, rest = read_body(sock, int(re.search(rb'Content-Length: (\d+)', head).group(1)), rest)
                assert body[:2] == b'\xff\xd8' and body[-2:] == b'\xff\xd9'
            assert rest == b''
        # Multipart stream: one connection carries successive frames with no further requests.
        with socket.create_connection(('127.0.0.1', port), timeout=5) as sock:
            sock.sendall(('GET /stream.mjpg HTTP/1.1\r\nHost: 127.0.0.1\r\n' + line + '\r\n').encode())
            head, data = read_head(sock)
            assert b' 200 OK' in head and b'multipart/x-mixed-replace; boundary=screentaskframe' in head, head
            assert b'Content-Length' not in head and b'Connection: close' in head, head
            deadline = time.time() + 5
            while data.count(b'--screentaskframe') < 3 and time.time() < deadline:
                chunk = sock.recv(65536)
                if not chunk: break
                data += chunk
            assert data.count(b'--screentaskframe') >= 3, data.count(b'--screentaskframe')
            assert data.count(b'\xff\xd8\xff') >= 3
        # An explicit close request must still close.
        with socket.create_connection(('127.0.0.1', port), timeout=5) as sock:
            sock.sendall(('GET /ScreenTask.jpg HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n' + line + '\r\n').encode())
            head, rest = read_head(sock)
            assert b'Connection: close' in head, head
            body, rest = read_body(sock, int(re.search(rb'Content-Length: (\d+)', head).group(1)), rest)
            assert sock.recv(1) == b''
        # A body arriving with the headers is unframed input: rejected outright.
        with socket.create_connection(('127.0.0.1', port), timeout=5) as sock:
            sock.sendall(('POST / HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 5\r\n' + line + '\r\nhello').encode())
            head, _ = read_head(sock)
            assert b' 400 ' in head and b'Connection: close' in head, head
        # A body in a later segment is never read, so the response must close instead of desyncing.
        with socket.create_connection(('127.0.0.1', port), timeout=5) as sock:
            sock.sendall(('POST / HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 5\r\n' + line + '\r\n').encode())
            head, rest = read_head(sock)
            assert b' 405 ' in head and b'Connection: close' in head, head
            body, rest = read_body(sock, int(re.search(rb'Content-Length: (\d+)', head).group(1)), rest)
            assert sock.recv(1) == b''
        # One peer cannot take the whole connection table: streams have no natural deadline.
        held = [socket.create_connection(('127.0.0.1', port), timeout=5) for _ in range(24)]
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=5) as extra:
                extra.sendall(('GET /ScreenTask.jpg HTTP/1.1\r\nHost: 127.0.0.1\r\n' + line + '\r\n').encode())
                try:
                    assert extra.recv(64) == b'', 'connection past the per-peer cap was served'
                except ConnectionResetError:
                    pass
        finally:
            for sock in held: sock.close()
        # Slots come back once those peers go away.
        for attempt in range(40):
            try:
                assert exchange(port, '/ScreenTask.jpg', auth)[0] == 200
                break
            except (OSError, http.client.HTTPException, AssertionError):
                time.sleep(.1)
        else:
            raise AssertionError('server did not release connection slots')
        # A peer that stops reading must not be able to trade stalled sockets for fresh slots: the
        # write deadline has to take the socket down, not just its bookkeeping.
        if not private:
            stalled = []
            try:
                for wave in range(2):
                    for _ in range(8):
                        sock = socket.create_connection(('127.0.0.1', port), timeout=5)
                        sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 2048)
                        stalled.append(sock)
                        for _ in range(60):
                            try: sock.sendall(b'GET / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n')
                            except OSError: break
                            time.sleep(.005)
                    live = live_sockets(port)
                    assert live <= 24, f'stalled peer holds {live} sockets, past the per-peer cap'
                    if wave == 0: time.sleep(13)
            finally:
                for sock in stalled: sock.close()
            for attempt in range(60):
                if exchange(port, '/ScreenTask.jpg', auth)[0] == 200: break
                time.sleep(.5)
            else: raise AssertionError('server never recovered from a stalled peer')
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
