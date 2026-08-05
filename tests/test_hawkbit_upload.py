import importlib.util
from pathlib import Path
import unittest
from unittest import mock

SCRIPT_PATH = Path(__file__).parents[1] / "misc" / "hawkbit-upload.py"
SPEC = importlib.util.spec_from_file_location("hawkbit_upload", SCRIPT_PATH)
HAWKBIT_UPLOAD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HAWKBIT_UPLOAD)


def fake_response(status_code, json_body=None):
    response = mock.Mock()
    response.status_code = status_code
    response.json.return_value = json_body if json_body is not None else {}
    response.content = b"{}"
    return response


class DistributionSortingTests(unittest.TestCase):
    def setUp(self):
        self.client = HAWKBIT_UPLOAD.HawkbitMgmtClient("hawkbit", 443)

    def test_sorts_mixed_version_formats_by_creation_time(self):
        self.client.get_distributionsets_by_name = lambda _name: [
            {
                "version": "2026M1340-stable",
                "createdAt": 300,
            },
            {
                "version": "2026-07-27T19_46_37+0000",
                "createdAt": 100,
            },
            {
                "version": "2026M1339-stable",
                "createdAt": 200,
            },
        ]

        distributions = self.client.sort_distributions_by_creation_time("stable EMMC")

        self.assertEqual(
            [distribution["version"] for distribution in distributions],
            [
                "2026M1340-stable",
                "2026M1339-stable",
                "2026-07-27T19_46_37+0000",
            ],
        )

    def test_falls_back_to_last_modified_time(self):
        self.client.get_distributionsets_by_name = lambda _name: [
            {"version": "older", "lastModifiedAt": "100"},
            {"version": "newer", "lastModifiedAt": "200"},
        ]

        distributions = self.client.sort_distributions_by_creation_time("stable EMMC")

        self.assertEqual(
            [distribution["version"] for distribution in distributions],
            ["newer", "older"],
        )

    def test_returns_none_when_no_distributions_exist(self):
        self.client.get_distributionsets_by_name = lambda _name: None

        self.assertIsNone(
            self.client.sort_distributions_by_creation_time("stable EMMC")
        )


class ServerErrorRetryTests(unittest.TestCase):
    def setUp(self):
        self.client = HAWKBIT_UPLOAD.HawkbitMgmtClient("hawkbit", 443)

        sleep_patcher = mock.patch.object(HAWKBIT_UPLOAD.time, "sleep")
        self.sleep = sleep_patcher.start()
        self.addCleanup(sleep_patcher.stop)

    def test_get_retries_until_it_succeeds(self):
        responses = [
            fake_response(500),
            fake_response(503),
            fake_response(200, {"value": "ok"}),
        ]
        with mock.patch.object(
            HAWKBIT_UPLOAD.r, "get", side_effect=responses
        ) as get_mock:
            self.assertEqual(self.client.get("system/configs/x"), {"value": "ok"})

        self.assertEqual(get_mock.call_count, 3)
        self.assertEqual(self.sleep.call_count, 2)

    def test_get_gives_up_after_the_configured_retries(self):
        responses = [fake_response(500)] * (HAWKBIT_UPLOAD.RETRY_MAX_RETRIES + 1)
        with mock.patch.object(
            HAWKBIT_UPLOAD.r, "get", side_effect=responses
        ) as get_mock:
            with self.assertRaises(HAWKBIT_UPLOAD.HawkbitError):
                self.client.get("system/configs/x")

        self.assertEqual(get_mock.call_count, HAWKBIT_UPLOAD.RETRY_MAX_RETRIES + 1)

    def test_client_errors_are_not_retried(self):
        with mock.patch.object(
            HAWKBIT_UPLOAD.r, "get", return_value=fake_response(404)
        ) as get_mock:
            with self.assertRaises(HAWKBIT_UPLOAD.HawkbitError):
                self.client.get("targets/does-not-exist")

        self.assertEqual(get_mock.call_count, 1)

    def test_put_retries(self):
        responses = [fake_response(500), fake_response(200, {"id": 1})]
        with mock.patch.object(
            HAWKBIT_UPLOAD.r, "put", side_effect=responses
        ) as put_mock:
            self.client.put("distributionsets/1", {"version": "2"})

        self.assertEqual(put_mock.call_count, 2)

    def test_post_does_not_retry_by_default(self):
        with mock.patch.object(
            HAWKBIT_UPLOAD.r, "post", return_value=fake_response(500)
        ) as post_mock:
            with self.assertRaises(HAWKBIT_UPLOAD.HawkbitError):
                self.client.post("distributionsets", [{"name": "stable EMMC"}])

        self.assertEqual(post_mock.call_count, 1)

    def test_post_retries_when_the_endpoint_opts_in(self):
        responses = [fake_response(500), fake_response(200, {"id": 1})]
        with mock.patch.object(
            HAWKBIT_UPLOAD.r, "post", side_effect=responses
        ) as post_mock:
            self.client.post(
                "targetfilters/1/autoAssignDS",
                json_data={"id": 1},
                retry_on_server_error=True,
            )

        self.assertEqual(post_mock.call_count, 2)

    def test_assign_ds_to_targetfilter_opts_into_retrying(self):
        responses = [fake_response(500), fake_response(200, {"id": 1})]
        with mock.patch.object(
            HAWKBIT_UPLOAD.r, "post", side_effect=responses
        ) as post_mock:
            self.client.assignDS_to_targetfilter("1", "2")

        self.assertEqual(post_mock.call_count, 2)

    def test_delete_retries_until_it_succeeds(self):
        responses = [fake_response(500), fake_response(200)]
        with mock.patch.object(
            HAWKBIT_UPLOAD.r, "delete", side_effect=responses
        ) as delete_mock:
            self.client.delete("distributionsets/1")

        self.assertEqual(delete_mock.call_count, 2)

    def test_delete_gives_up_after_the_configured_retries(self):
        responses = [fake_response(500)] * (HAWKBIT_UPLOAD.RETRY_MAX_RETRIES + 1)
        with mock.patch.object(
            HAWKBIT_UPLOAD.r, "delete", side_effect=responses
        ) as delete_mock:
            with self.assertRaises(HAWKBIT_UPLOAD.HawkbitError):
                self.client.delete("distributionsets/1")

        self.assertEqual(delete_mock.call_count, HAWKBIT_UPLOAD.RETRY_MAX_RETRIES + 1)

    def test_delete_accepts_404_once_a_retry_is_under_way(self):
        # The lost attempt did reach hawkBit, so the resource really is gone.
        responses = [fake_response(502), fake_response(404)]
        with mock.patch.object(
            HAWKBIT_UPLOAD.r, "delete", side_effect=responses
        ) as delete_mock:
            self.client.delete("distributionsets/1")

        self.assertEqual(delete_mock.call_count, 2)

    def test_delete_still_raises_on_a_404_from_the_first_attempt(self):
        with mock.patch.object(
            HAWKBIT_UPLOAD.r, "delete", return_value=fake_response(404)
        ) as delete_mock:
            with self.assertRaises(HAWKBIT_UPLOAD.HawkbitError):
                self.client.delete("distributionsets/does-not-exist")

        self.assertEqual(delete_mock.call_count, 1)

    def test_a_404_is_not_recovered_for_other_methods(self):
        responses = [fake_response(500), fake_response(404)]
        with mock.patch.object(HAWKBIT_UPLOAD.r, "get", side_effect=responses):
            with self.assertRaises(HAWKBIT_UPLOAD.HawkbitError):
                self.client.get("distributionsets/1")

    def test_artifact_upload_cannot_opt_into_retrying(self):
        with self.assertRaises(AssertionError):
            self.client.post(
                "softwaremodules/1/artifacts",
                file_name=str(SCRIPT_PATH),
                retry_on_server_error=True,
            )

    def test_retry_delay_stays_within_the_configured_jitter(self):
        delays = [HAWKBIT_UPLOAD.retry_delay() for _ in range(1000)]

        self.assertGreaterEqual(
            min(delays),
            HAWKBIT_UPLOAD.RETRY_DELAY_SECONDS - HAWKBIT_UPLOAD.RETRY_JITTER_SECONDS,
        )
        self.assertLessEqual(
            max(delays),
            HAWKBIT_UPLOAD.RETRY_DELAY_SECONDS + HAWKBIT_UPLOAD.RETRY_JITTER_SECONDS,
        )


if __name__ == "__main__":
    unittest.main()
