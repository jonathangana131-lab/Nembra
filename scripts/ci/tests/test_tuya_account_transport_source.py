#!/usr/bin/env python3
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
SOURCE = (ROOT / "NembraApp/Features/Research/TuyaAccountBridge.swift").read_text(encoding="utf-8")

class TuyaAccountTransportSourceTests(unittest.TestCase):
    def test_plaintext_server_endpoint_is_not_admitted(self):
        self.assertNotIn('rawEndpoint.hasPrefix("http")', SOURCE)
        self.assertIn('components.scheme?.lowercased() == "https"', SOURCE)
        self.assertIn('let endpoint = try Self.normalizedHTTPSAPIEndpoint(rawEndpoint)', SOURCE)

    def test_authenticated_requests_reject_redirect_replay(self):
        self.assertIn('TuyaAccountBridgeNoRedirectDelegate', SOURCE)
        self.assertIn('completionHandler(nil)', SOURCE)
        self.assertIn('URLSession.shared.data(for: request, delegate: redirectDelegate)', SOURCE)

    def test_every_json_request_fails_closed_before_non_https_transport(self):
        self.assertIn('requestURL.scheme?.lowercased() == "https"', SOURCE)
        self.assertIn('throw BridgeError.invalidURL', SOURCE)

    def test_successful_approval_with_rejected_session_fails_instead_of_polling(self):
        self.assertNotIn('guard Self.bool(object["success"]), let result = object["result"]', SOURCE)
        self.assertIn('var approvalSucceeded = false', SOURCE)
        self.assertIn('approvalSucceeded = true', SOURCE)
        self.assertIn('if approvalSucceeded {', SOURCE)
        self.assertIn('phase = .failed', SOURCE)
        self.assertIn('account session was rejected:', SOURCE)
        self.assertIn('pollTask?.cancel()', SOURCE)

if __name__ == "__main__":
    unittest.main()
