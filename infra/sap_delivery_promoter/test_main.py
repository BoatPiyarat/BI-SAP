import csv
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
    @staticmethod
    def canonical_header():
        return ",".join(main._CANONICAL_HEADER)

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
        csv_bytes = (self.canonical_header() + "\n" +
                     (",".join("x" for _ in range(56))) + "\n").encode()
        source.open.side_effect = lambda mode: io.BytesIO(csv_bytes)

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
        self.assertEqual(body["header_column_count"], 56)
        self.assertEqual(body["data_row_count"], 1)

    @mock.patch("main.storage.Client")
    def test_wrong_header_count_is_rejected_before_copy(self, client_class):
        source = mock.Mock()
        source.size = 4
        source.crc32c = "AAAAAA=="
        source.generation = 123
        payload = ("a,b\n" + ",".join("x" for _ in range(56)) + "\n").encode()
        source.open.side_effect = lambda mode: io.BytesIO(payload)

        archive_bucket = mock.Mock()
        archive_bucket.blob.return_value = source
        production_bucket = mock.Mock()
        client_class.return_value.bucket.side_effect = (
            lambda name: archive_bucket if name == "rcb-bronze-zone" else production_bucket
        )

        with mock.patch.dict(os.environ, self.environment, clear=False):
            response = self.client.post("/promote", json=self.payload)

        self.assertEqual(response.status_code, 409)
        self.assertIn("canonical 56-column order", response.get_json()["error"])

    @mock.patch("main.storage.Client")
    def test_wrong_data_row_width_is_rejected_before_copy(self, client_class):
        source = mock.Mock()
        source.size = 4
        source.crc32c = "AAAAAA=="
        source.generation = 123
        header = self.canonical_header()
        source.open.side_effect = lambda mode: io.BytesIO((header + "\n1,2\n").encode())

        archive_bucket = mock.Mock()
        archive_bucket.blob.return_value = source
        production_bucket = mock.Mock()
        client_class.return_value.bucket.side_effect = (
            lambda name: archive_bucket if name == "rcb-bronze-zone" else production_bucket
        )

        with mock.patch.dict(os.environ, self.environment, clear=False):
            response = self.client.post("/promote", json=self.payload)

        self.assertEqual(response.status_code, 409)
        self.assertIn("row 2", response.get_json()["error"])

    def test_csv_shape_counts_quoted_newline_as_one_physical_record(self):
        blob = mock.Mock()
        header = self.canonical_header()
        row = ["line1\nline2"] + ["x"] * 55
        buffer = io.StringIO(newline="")
        writer = csv.writer(buffer)
        writer.writerow(main._CANONICAL_HEADER)
        writer.writerow(row)
        payload = buffer.getvalue().encode()
        blob.open.side_effect = lambda mode: io.BytesIO(payload)

        self.assertEqual(main.csv_shape_for_blob(blob), (56, 1))

    def test_reordered_header_is_rejected(self):
        blob = mock.Mock()
        header = list(main._CANONICAL_HEADER)
        header[0], header[1] = header[1], header[0]
        payload = (",".join(header) + "\n" + ",".join("x" for _ in range(56)) + "\n").encode()
        blob.open.side_effect = lambda mode: io.BytesIO(payload)

        with self.assertRaisesRegex(ValueError, "canonical 56-column order"):
            main.csv_shape_for_blob(blob)

    def test_duplicate_or_wrong_header_name_is_rejected(self):
        blob = mock.Mock()
        header = list(main._CANONICAL_HEADER)
        header[1] = header[0]
        payload = (",".join(header) + "\n" + ",".join("x" for _ in range(56)) + "\n").encode()
        blob.open.side_effect = lambda mode: io.BytesIO(payload)

        with self.assertRaisesRegex(ValueError, "canonical 56-column order"):
            main.csv_shape_for_blob(blob)

    def test_malformed_quoting_is_rejected(self):
        blob = mock.Mock()
        payload = (self.canonical_header() + "\n\"unterminated").encode()
        blob.open.side_effect = lambda mode: io.BytesIO(payload)

        with self.assertRaisesRegex(ValueError, "valid UTF-8 CSV"):
            main.csv_shape_for_blob(blob)

    def test_invalid_utf8_is_rejected(self):
        blob = mock.Mock()
        payload = (self.canonical_header() + "\n").encode() + b"\xff"
        blob.open.side_effect = lambda mode: io.BytesIO(payload)

        with self.assertRaisesRegex(ValueError, "valid UTF-8 CSV"):
            main.csv_shape_for_blob(blob)


if __name__ == "__main__":
    unittest.main()
