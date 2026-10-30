"""Serves build/review (each phase's films, sounds and screenshots) for the owner's phone, with no-cache headers and
byte ranges (Safari won't play a video without them).

    python3 scripts/review_server.py [port]          default 8824; binds 127.0.0.1 only
    tailscale serve --bg --https=8824 http://127.0.0.1:8824

The log (stderr) has one line per request with its Range header, and one line when a client hangs up early (Safari does, once it has
read a film's header). `GET /__d?<text>` answers 204 and is logged: a page on a phone can report to the log with
`new Image().src = '/__d?' + encodeURIComponent(text)`, which is how a phone that will not play a film is asked what it sees.
"""
import functools
import http.server
import os
import re
import sys
import time

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'build', 'review'))


class _Slice:
    """A file object that stops after `remaining` bytes (the body of a 206)."""

    def __init__(self, f, remaining):
        self.f, self.remaining = f, remaining

    def read(self, n=-1):
        if self.remaining <= 0:
            return b''
        n = self.remaining if n is None or n < 0 else min(n, self.remaining)
        data = self.f.read(n)
        self.remaining -= len(data)
        return data

    def close(self):
        self.f.close()


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      '.mp4': 'video/mp4', '.wav': 'audio/wav', '.m4a': 'audio/mp4', '.json': 'application/json',
                      '.html': 'text/html; charset=utf-8', '.webp': 'image/webp'}

    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Accept-Ranges', 'bytes')
        super().end_headers()

    def send_head(self):
        wanted = self.headers.get('Range')
        path = self.translate_path(self.path)
        match = re.fullmatch(r'bytes=(\d*)-(\d*)', (wanted or '').strip())
        if not match or not os.path.isfile(path):
            return super().send_head()
        size = os.path.getsize(path)
        first, last = match.groups()
        if first == '':
            start, end = max(0, size - int(last or 0)), size - 1
        else:
            start, end = int(first), min(int(last) if last else size - 1, size - 1)
        if start >= size or start > end:
            self.send_response(416)
            self.send_header('Content-Range', f'bytes */{size}')
            self.end_headers()
            return None
        f = open(path, 'rb')
        f.seek(start)
        self.send_response(206)
        self.send_header('Content-Type', self.guess_type(path))
        self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
        self.send_header('Content-Length', str(end - start + 1))
        self.end_headers()
        return _Slice(f, end - start + 1)

    def do_GET(self):
        if self.path.startswith('/__d'):
            self.send_response(204)
            self.end_headers()
            return
        super().do_GET()

    def log_message(self, fmt, *args):
        headers = getattr(self, 'headers', None)
        extra = ''
        if headers is not None:
            if headers.get('Range'):
                extra += ' [%s]' % headers['Range']
            path = getattr(self, 'path', '')
            if path.startswith('/__d') or path.endswith('/') or path.endswith('.html'):
                agent = re.search(r'\(([^)]*)\)', headers.get('User-Agent', ''))
                extra += ' ua=%s' % (agent.group(1) if agent else '?')
        sys.stderr.write('%s %s%s\n' % (self.log_date_time_string(), fmt % args, extra))


class Server(http.server.ThreadingHTTPServer):
    def handle_error(self, request, client_address):
        if isinstance(sys.exc_info()[1], (BrokenPipeError, ConnectionResetError)):
            sys.stderr.write('%s client %s closed the connection early\n' % (time.strftime('%d/%b/%Y %H:%M:%S'), client_address[1]))
            return
        super().handle_error(request, client_address)


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8824
    os.makedirs(ROOT, exist_ok=True)
    server = Server(('127.0.0.1', port), functools.partial(Handler, directory=ROOT))
    print(f'serving {ROOT} on http://127.0.0.1:{port}', flush=True)
    server.serve_forever()
