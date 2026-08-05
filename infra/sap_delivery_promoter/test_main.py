import io
import os
import types
import unittest
from unittest import mock

import google.cloud

if not hasattr(google.cloud, "storage"):
    google.cloud.storage = types.SimpleNamespace(Client=mock.Mock)

import main


class DeliveryPromoterContractTest(unittest.TestCase):
    def setUp(self):
        self.client = main.app.test_client()
        self.payload = {
            "archive_bucket": "rcb-bronze-zone",
            "archive_object": "sap-interface-archive/run/file.csv",
            "archive_generation": "123",
            "production_bucket": "interface-file",
            "production_object": "RCB_MOTOR/INSURANCE_RCB_TEST_000000000000.csv",
            "production_file_name": "INSURANCE_RCB_TEST_000000000000.csv",
        }
        self.environment = {
            "ARCHIVE_BUCKET": "rcb-bronze-zone",
            "PRODUCTION_BUCKET": "interface-file",
            "PRODUCTION_PREFIX": "RCB_MOTOR",
        }

    def test_legacy_one_name_payload_is_rejected(self):
        payload = dict(self.payload)
        del payload["production_file_name"]
        payload["sap_file_name"] = "INSURANCE_RCB_TEST_000000000000.csv"
        with mock.patch.dict(os.environ, self.environment, clear=False):
            response = self.client.post("/promote", json=payload)
        self.assertEqual(response.status_code, 400)
        self.assertIn("production_file_name", response.get_json()["error"])

    def test_production_object_must_match_exact_production_name(self):
        payload = dict(self.payload)
        payload["production_object"] = "RCB_MOTOR/other.csv"
        with mock.patch.dict(os.environ, self.environment, clear=False):
            response = self.client.post("/promote", json=payload)
        self.assertEqual(response.status_code, 400)
        self.assertIn("production_file_name", response.get_json()["error"])

    @mock.patch("main.storage.Client")
    def test_success_returns_production_name_not_sap_result_name(self, client_class):
        source = mock.Mock()
        source.size = 4
        source.crc32c = "AAAAAA=="
        source.generation = 123
        source.open.return_value = io.BytesIO(b"test")

        destination = mock.Mock()
        destination.size = 4
        destination.crc32c = "AAAAAA=="
        destination.generation = 456
        destination.rewrite.return_value = (None, 4, 4)

        archive_bucket = mock.Mock()
        archive_bucket.blob.return_value = source
        production_bucket = mock.Mock()
        production_bucket.blob.return_value = destination
        client_class.return_value.bucket.side_effect = (
            lambda name: archive_bucket if name == "rcb-bronze-zone" else production_bucket
        )

        with mock.patch.dict(os.environ, self.environment, clear=False):
            response = self.client.post("/promote", json=self.payload)

        self.assertEqual(response.status_code, 200)
        body = response.get_json()
        self.assertEqual(
            body["production_file_name"], "INSURANCE_RCB_TEST_000000000000.csv"
        )
        self.assertNotIn("sap_file_name", body)
        self.assertEqual(
            body["production_uri"],
            "gs://interface-file/RCB_MOTOR/INSURANCE_RCB_TEST_000000000000.csv",
        )


if __name__ == "__main__":
    unittest.main()
