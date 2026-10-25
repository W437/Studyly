"""Serve docs/rethink/site for the phone, with no-cache headers so edits show up on reload.

Usage: python3 serve.py [port]
Binds 127.0.0.1 only; `tailscale serve --bg --https=<port> http://127.0.0.1:<port>` exposes it to the tailnet.
"""
import functools
import http.server
import os
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'site'))


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      '.webp': 'image/webp', '.js': 'text/javascript', '.css': 'text/css', '.html': 'text/html; charset=utf-8'}

    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache')
        super().end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write('%s %s\n' % (self.log_date_time_string(), fmt % args))


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8801
    server = http.server.ThreadingHTTPServer(('127.0.0.1', port), functools.partial(Handler, directory=ROOT))
    print(f'serving {ROOT} on http://127.0.0.1:{port}', flush=True)
    server.serve_forever()
