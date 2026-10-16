#!/usr/bin/env python3
"""Loopback-only HTTP UI for the shared Swift sleep service. No dependencies."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
BUILD = ROOT / '.build'


def build_bridge():
    BUILD.mkdir(exist_ok=True)
    binary = BUILD / 'sleep-web-bridge'
    sources = sorted((REPO / 'native/Core').glob('*.swift')) + [ROOT / 'Bridge.swift']
    if not binary.exists() or any(p.stat().st_mtime > binary.stat().st_mtime for p in sources):
        print('Building the shared Swift client…', flush=True)
        env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(BUILD / 'module-cache'))
        subprocess.run(['swiftc', '-parse-as-library', *map(str, sources), '-o', str(binary)],
                       env=env, check=True)
    return binary


class Bridge:
    def __init__(self, binary):
        self.process = subprocess.Popen([str(binary), str(REPO / 'native/Fixtures/demo.json')],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        text=True, bufsize=1)
        self.lock = threading.Lock()

    def call(self, payload):
        with self.lock:
            self.process.stdin.write(json.dumps(payload) + '\n')
            self.process.stdin.flush()
            line = self.process.stdout.readline()
            if not line:
                raise RuntimeError('Swift bridge stopped')
            return json.loads(line)

    def close(self):
        self.process.terminate()
        self.process.wait(timeout=10)
        self.process.stdin.close()
        self.process.stdout.close()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Never log POST bodies, credentials, or report data.

    def allowed(self):
        return self.headers.get('Host') == self.server.authority

    def reply(self, status, data, content_type='application/json'):
        body = json.dumps(data).encode() if content_type == 'application/json' else data
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if not self.allowed():
            return self.reply(403, {'error': 'Use the local URL printed by the server.'})
        files = {'/': ('index.html', 'text/html; charset=utf-8'),
                 '/app.js': ('app.js', 'text/javascript; charset=utf-8'),
                 '/style.css': ('style.css', 'text/css; charset=utf-8')}
        if self.path not in files:
            return self.reply(404, {'error': 'Not found'})
        name, mime = files[self.path]
        self.reply(200, (ROOT / 'static' / name).read_bytes(), mime)

    def do_POST(self):
        if not self.allowed() or self.headers.get('Origin') != 'http://' + self.server.authority:
            return self.reply(403, {'error': 'Requests must originate from this local client.'})
        if self.path != '/api/command':
            return self.reply(404, {'error': 'Not found'})
        if self.headers.get('Content-Type', '').split(';')[0] != 'application/json':
            return self.reply(415, {'error': 'Expected JSON'})
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= 16384:
                return self.reply(413, {'error': 'Request too large or empty'})
            payload = json.loads(self.rfile.read(size))
            if not isinstance(payload, dict) or payload.get('command') not in {
                'configure', 'report', 'status', 'control', 'demo', 'disconnect', 'state'
            }:
                return self.reply(400, {'error': 'Unknown command'})
        except (ValueError, UnicodeError):
            return self.reply(400, {'error': 'Invalid JSON request'})
        try:
            self.reply(200, self.server.bridge.call(payload))
        except (RuntimeError, BrokenPipeError, ValueError):
            self.reply(503, {'ok': False, 'error': 'Local Swift client stopped. Restart the web server.'})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8787)
    args = parser.parse_args()
    binary = build_bridge()
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    server.authority = f'127.0.0.1:{server.server_port}'
    server.bridge = Bridge(binary)
    print(f'MySleep web client: http://{server.authority}', flush=True)
    print('Credentials and reports stay in server memory until disconnect or shutdown.', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        server.bridge.close()


if __name__ == '__main__':
    main()
