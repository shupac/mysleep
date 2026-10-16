import io
import json
from email.message import Message
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from server import Bridge, Handler, build_bridge


class HandlerTests(unittest.TestCase):
    def handler(self, host='127.0.0.1:8787', origin='http://127.0.0.1:8787',
                body=b'{"command":"state"}', content_type='application/json'):
        h = Handler.__new__(Handler)
        h.headers = Message()
        h.headers['Host'] = host
        if origin is not None:
            h.headers['Origin'] = origin
        h.headers['Content-Type'] = content_type
        h.headers['Content-Length'] = str(len(body))
        h.rfile = io.BytesIO(body)
        h.path = '/api/command'
        self.calls = []

        def call(payload):
            self.calls.append(payload)
            return {'ok': True}

        h.server = SimpleNamespace(authority='127.0.0.1:8787', bridge=SimpleNamespace(call=call))
        self.response = None

        def reply(status, body, *_):
            self.response = (status, body)

        h.reply = reply
        return h

    def test_local_command_is_forwarded(self):
        self.handler().do_POST()
        self.assertEqual(self.response[0], 200)
        self.assertEqual(self.calls, [{'command': 'state'}])

    def test_cross_origin_and_missing_origin_cannot_access_session(self):
        for origin in ['https://example.com', None, 'null']:
            self.handler(origin=origin).do_POST()
            self.assertEqual(self.response[0], 403)
            self.assertFalse(self.calls)

    def test_rebinding_host_is_rejected(self):
        self.handler(host='attacker.example:8787').do_POST()
        self.assertEqual(self.response[0], 403)
        self.assertFalse(self.calls)

    def test_unexpected_paths_and_malformed_requests_are_rejected(self):
        for body, status in [(b'not json', 400), (b'[]', 400),
                             (b'{"command":"proxy","url":"https://example.com"}', 400),
                             (b'x' * 17000, 413)]:
            self.handler(body=body).do_POST()
            self.assertEqual(self.response[0], status)
            self.assertFalse(self.calls)
        h = self.handler(); h.path = '/api/anything'; h.do_POST()
        self.assertEqual(self.response[0], 404)
        self.handler(content_type='text/plain').do_POST()
        self.assertEqual(self.response[0], 415)

    def test_static_files_cannot_escape_allowlist(self):
        h = self.handler(); h.path = '/../Bridge.swift'; h.do_GET()
        self.assertEqual(self.response[0], 404)
        h = self.handler(); h.path = '/'; h.do_GET()
        self.assertEqual(self.response[0], 200)
        self.assertIn(b'MySleep', self.response[1])


class BridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary = build_bridge()

    def setUp(self):
        self.bridge = Bridge(self.binary)

    def tearDown(self):
        self.bridge.close()

    def test_unconfigured_report_returns_safe_error_without_requests(self):
        result = self.bridge.call({'command': 'report'})
        self.assertFalse(result['ok'])
        self.assertFalse(result['configured'])
        self.assertIn('Sign in', result['error'])
        self.assertEqual(result['diagnostics'], [])

    def test_demo_never_authenticates_and_cannot_control_real_bed(self):
        demo = self.bridge.call({'command': 'demo'})
        self.assertTrue(demo['ok'])
        self.assertEqual(demo['report']['report']['hrvMs'], 42)
        self.assertEqual(demo['diagnostics'], [])
        result = self.bridge.call({'command': 'control', 'action': 'on'})
        self.assertFalse(result['ok'])
        self.assertEqual(result['diagnostics'], [])
        disconnected = self.bridge.call({'command': 'disconnect'})
        self.assertFalse(disconnected['demo'])
        self.assertFalse(disconnected['configured'])

    def test_invalid_configuration_does_not_echo_password(self):
        result = self.bridge.call({'command': 'configure', 'email': 'invalid',
                                   'password': 'never-echo-this-secret', 'timezone': 'invalid'})
        self.assertFalse(result['ok'])
        self.assertNotIn('never-echo-this-secret', json.dumps(result))
        self.assertEqual(result['diagnostics'], [])


if __name__ == '__main__':
    unittest.main()
