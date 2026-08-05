import base64
import json
import unittest

import main


class DispatcherContractTest(unittest.TestCase):
    def setUp(self):
        self.event = {
            "log_id": "21183",
            "export_run_id": "V3DAILY-20260803-113257-55042e7c",
            "sap_file_name": "RCB_MOTOR_INSURANCE_RCB_06_V3_DAILY_NEWPAYMENT_20260803.csv",
            "import_status": "Success",
            "email_date": "2026-08-03T19:45:00+07:00",
        }

    def envelope(self, event):
        data = base64.b64encode(json.dumps(event).encode("utf-8")).decode("ascii")
        return {"message": {"data": data}}

    def test_valid_event_normalizes_status(self):
        decoded = main.decode_event(self.envelope(self.event))
        self.assertEqual(main.validate_event(decoded)["import_status"], "success")

    def test_claim_token_is_deterministic_lower_hex(self):
        first = main.claim_token(self.event)
        second = main.claim_token(dict(self.event))
        self.assertEqual(first, second)
        self.assertRegex(first, r"^[a-f0-9]{32}$")

    def test_unsafe_filename_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "safe .csv basename"):
            main.validate_event({**self.event, "sap_file_name": "../bad.csv"})

    def test_nonterminal_import_status_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "not an admitted terminal"):
            main.validate_event({**self.event, "import_status": "processing"})

    def test_naive_email_date_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "include a timezone"):
            main.validate_event({**self.event, "email_date": "2026-08-03T19:45:00"})


if __name__ == "__main__":
    unittest.main()
