import os
import unittest
from unittest import mock

from google.cloud.workflows.executions_v1.types import Execution

import main


class WatchdogContractTest(unittest.TestCase):
    def test_configured_seconds_accepts_approved_range(self):
        with mock.patch.dict(os.environ, {"TEST_SECONDS": "300"}):
            self.assertEqual(main.configured_seconds("TEST_SECONDS", 60, 3600), 300)

    def test_configured_seconds_rejects_low_value(self):
        with mock.patch.dict(os.environ, {"TEST_SECONDS": "59"}):
            with self.assertRaisesRegex(RuntimeError, "between 60 and 3600"):
                main.configured_seconds("TEST_SECONDS", 60, 3600)

    def test_cancel_race_returns_already_succeeded(self):
        client = mock.Mock()
        client.cancel_execution.side_effect = RuntimeError("already terminal")
        client.get_execution.return_value = Execution(state=Execution.State.SUCCEEDED)
        self.assertEqual(
            main.cancel_until_terminal(client, "projects/p/locations/l/workflows/w/executions/e", 30),
            "SUCCEEDED",
        )

    @mock.patch("main.time.sleep")
    def test_cancel_polls_until_cancelled(self, sleep):
        client = mock.Mock()
        client.get_execution.side_effect = [
            Execution(state=Execution.State.ACTIVE),
            Execution(state=Execution.State.CANCELLED),
        ]
        self.assertEqual(
            main.cancel_until_terminal(client, "projects/p/locations/l/workflows/w/executions/e", 30),
            "CANCELLED",
        )
        self.assertEqual(sleep.call_count, 1)


if __name__ == "__main__":
    unittest.main()
