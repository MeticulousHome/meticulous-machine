import importlib.util
from pathlib import Path
import unittest
from unittest import mock


SCRIPT_PATH = Path(__file__).parents[1] / "misc" / "configure-hawkbit-polling.py"
SPEC = importlib.util.spec_from_file_location("configure_hawkbit_polling", SCRIPT_PATH)
POLLING = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(POLLING)


class ConfigureHourlyPollingTests(unittest.TestCase):
    def setUp(self):
        self.client = mock.Mock()
        self.output = mock.Mock()

    def test_already_correct_does_not_write(self):
        self.client.get_config.return_value = POLLING.HOURLY_POLLING_TIME

        POLLING.configure_hourly_polling(self.client, apply=True, output=self.output)

        self.client.get_config.assert_called_once_with(POLLING.POLLING_TIME_KEY)
        self.client.set_config.assert_not_called()

    def test_dry_run_reports_proposed_change_without_writing(self):
        self.client.get_config.return_value = "00:01:00"

        POLLING.configure_hourly_polling(self.client, output=self.output)

        self.client.set_config.assert_not_called()
        self.output.assert_any_call(
            "[DRY RUN] Would change Hawkbit pollingTime from 00:01:00 to 01:00:00."
        )

    def test_apply_writes_and_verifies_readback(self):
        self.client.get_config.side_effect = ["00:01:00", "01:00:00"]

        POLLING.configure_hourly_polling(self.client, apply=True, output=self.output)

        self.client.set_config.assert_called_once_with("pollingTime", "01:00:00")
        self.assertEqual(
            self.client.method_calls,
            [
                mock.call.get_config("pollingTime"),
                mock.call.set_config("pollingTime", "01:00:00"),
                mock.call.get_config("pollingTime"),
            ],
        )
        self.output.assert_any_call(
            "Hawkbit pollingTime readback verified: 01:00:00."
        )

    def test_read_failure_is_sanitized(self):
        self.client.get_config.side_effect = RuntimeError("secret upstream detail")

        with self.assertRaisesRegex(
            POLLING.PollingConfigurationError,
            "Failed to read the current Hawkbit pollingTime",
        ) as raised:
            POLLING.configure_hourly_polling(self.client, apply=True)

        self.assertNotIn("secret upstream detail", str(raised.exception))
        self.client.set_config.assert_not_called()

    def test_write_failure_is_sanitized(self):
        self.client.get_config.return_value = "00:01:00"
        self.client.set_config.side_effect = RuntimeError("secret upstream detail")

        with self.assertRaisesRegex(
            POLLING.PollingConfigurationError,
            "Failed to write the Hawkbit pollingTime",
        ) as raised:
            POLLING.configure_hourly_polling(self.client, apply=True)

        self.assertNotIn("secret upstream detail", str(raised.exception))

    def test_readback_failure_is_sanitized(self):
        self.client.get_config.side_effect = [
            "00:01:00",
            RuntimeError("secret upstream detail"),
        ]

        with self.assertRaisesRegex(
            POLLING.PollingConfigurationError,
            "Failed to read back the Hawkbit pollingTime",
        ) as raised:
            POLLING.configure_hourly_polling(self.client, apply=True)

        self.assertNotIn("secret upstream detail", str(raised.exception))

    def test_mismatched_readback_fails(self):
        self.client.get_config.side_effect = ["00:01:00", "00:30:00"]

        with self.assertRaisesRegex(
            POLLING.PollingConfigurationError,
            "readback did not equal 01:00:00",
        ):
            POLLING.configure_hourly_polling(self.client, apply=True)


class MainTests(unittest.TestCase):
    @mock.patch.dict(
        "os.environ",
        {
            "HAWKBIT_SERVER": "hawkbit.example",
            "HAWKBIT_PORT": "443",
            "HAWKBIT_USER": "user",
            "HAWKBIT_PASSWORD": "secret-password",
        },
        clear=True,
    )
    def test_configuration_failure_returns_nonzero_without_exposing_credentials(self):
        client_factory = mock.Mock(return_value=mock.Mock())
        error = POLLING.PollingConfigurationError(
            "Failed to read the current Hawkbit pollingTime."
        )

        with mock.patch.object(
            POLLING, "load_management_client", return_value=client_factory
        ), mock.patch.object(
            POLLING, "configure_hourly_polling", side_effect=error
        ), mock.patch("builtins.print") as print_mock:
            result = POLLING.main(["--apply"])

        self.assertEqual(result, 1)
        output = " ".join(str(call) for call in print_mock.call_args_list)
        self.assertNotIn("secret-password", output)


if __name__ == "__main__":
    unittest.main()
