#!/usr/bin/env python3
"""Dev server: static files from this folder with caching disabled.

Usage: python3 serve.py [port]
"""
import http.server, os, sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8794
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'web')


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store, must-revalidate')
        self.send_header('Expires', '0')
        super().end_headers()

    def do_POST(self):
        # capture uploads from the page: POST /upload?name=file.ext (body = raw bytes)
        from urllib.parse import urlparse, parse_qs
        q = parse_qs(urlparse(self.path).query)
        name = os.path.basename(q.get('name', ['upload.bin'])[0])
        out = os.environ.get('CAPTURE_DIR', os.path.join(ROOT, '..', 'captures'))
        os.makedirs(out, exist_ok=True)
        n = int(self.headers.get('Content-Length', 0))
        with open(os.path.join(out, name), 'wb') as f:
            f.write(self.rfile.read(n))
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'ok')

    def log_message(self, fmt, *args):
        if '404' in (args[1] if len(args) > 1 else ''):
            super().log_message(fmt, *args)


Handler.extensions_map.update({'.js': 'text/javascript', '.mjs': 'text/javascript'})
with http.server.ThreadingHTTPServer(('127.0.0.1', PORT), Handler) as httpd:
    print(f'SNES dev at http://127.0.0.1:{PORT}', flush=True)
    httpd.serve_forever()
