#!/usr/bin/env python3
"""Lokalni server za dijagnostički web build (iOS uređaji preko Tailscalea).

Poslužuje build/web sa SPA fallbackom i prima POST /__log (sendBeacon iz
web/index.html, aktivan samo na localhost / *.ts.net) te ga dopisuje u
log datoteku, da se konzola iPhonea čita s Maca bez Web Inspectora.

    python3 scripts/serve-debug-web.py [port] [log]
    tailscale serve --bg --https=8443 http://127.0.0.1:<port>
"""
import http.server
import os
import sys
import time

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'build', 'web')
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8790
LOG = sys.argv[2] if len(sys.argv) > 2 else '/tmp/domovina-web-debug.log'


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)

    def end_headers(self):
        # Isto kao produkcijski worker: bez izolacije skwasm ide jednodretveno.
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'credentialless')
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

    def do_POST(self):
        if self.path != '/__log':
            self.send_error(404)
            return
        n = int(self.headers.get('Content-Length') or 0)
        body = self.rfile.read(n).decode('utf-8', 'replace')
        ua = self.headers.get('User-Agent', '')
        dev = 'iPhone' if 'iPhone' in ua else 'iPad' if 'iPad' in ua else 'other'
        with open(LOG, 'a') as f:
            f.write(f"{time.strftime('%H:%M:%S')} [{dev}] {body}\n")
        self.send_response(204)
        self.end_headers()

    def send_head(self):
        path = self.translate_path(self.path.split('?', 1)[0])
        if not os.path.exists(path):
            self.path = '/index.html'
        return super().send_head()

    def log_message(self, *a):
        pass


if __name__ == '__main__':
    print(f'serving {ROOT} on :{PORT}, log -> {LOG}')
    http.server.ThreadingHTTPServer(('127.0.0.1', PORT), Handler).serve_forever()
