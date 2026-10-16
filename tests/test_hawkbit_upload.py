import importlib.util
import json
import re
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


def matcher_for(thresholds, threshold_name, attribute_name):
    threshold = next(
        item for item in thresholds if item["name"] == threshold_name
    )
    return next(
        matcher
        for matcher in threshold["attributes"]
        if matcher["name"] == attribute_name
    )


class ThresholdPinningTests(unittest.TestCase):
    def resolved_defaults(self):
        return json.loads(json.dumps(HAWKBIT_UPLOAD.FALLBACK_THRESHOLDS))

    def test_pins_both_image_version_matchers_to_exact(self):
        pinned, synthesized = HAWKBIT_UPLOAD.pin_thresholds(
            self.resolved_defaults(), "2026M1340-stable"
        )

        self.assertEqual(synthesized, [])
        self.assertEqual(
            matcher_for(
                pinned,
                HAWKBIT_UPLOAD.BOOT_SMOKE_THRESHOLD_NAME,
                HAWKBIT_UPLOAD.BOOT_SMOKE_VERSION_ATTRIBUTE,
            ),
            {
                "name": HAWKBIT_UPLOAD.BOOT_SMOKE_VERSION_ATTRIBUTE,
                "type": "exact",
                "pattern": "2026M1340-stable",
            },
        )
        self.assertEqual(
            matcher_for(
                pinned,
                HAWKBIT_UPLOAD.POST_UPDATE_SHOT_THRESHOLD_NAME,
                HAWKBIT_UPLOAD.POST_UPDATE_SHOT_VERSION_ATTRIBUTE,
            ),
            {
                "name": HAWKBIT_UPLOAD.POST_UPDATE_SHOT_VERSION_ATTRIBUTE,
                "type": "exact",
                "pattern": "2026M1340-stable",
            },
        )

    def test_leaves_every_other_matcher_untouched(self):
        resolved = self.resolved_defaults()

        pinned, _synthesized = HAWKBIT_UPLOAD.pin_thresholds(
            resolved, "2026M1340-stable"
        )

        pinned_names = {
            HAWKBIT_UPLOAD.BOOT_SMOKE_VERSION_ATTRIBUTE,
            HAWKBIT_UPLOAD.POST_UPDATE_SHOT_VERSION_ATTRIBUTE,
        }
        for threshold in resolved:
            for matcher in threshold["attributes"]:
                if matcher["name"] in pinned_names:
                    continue
                self.assertEqual(
                    matcher_for(pinned, threshold["name"], matcher["name"]), matcher
                )

    def test_does_not_mutate_the_resolved_thresholds(self):
        resolved = self.resolved_defaults()
        before = json.dumps(resolved)

        HAWKBIT_UPLOAD.pin_thresholds(resolved, "2026M1340-stable")

        self.assertEqual(json.dumps(resolved), before)

    def test_preserves_a_hand_set_override_of_an_unrelated_matcher(self):
        resolved = self.resolved_defaults()
        matcher_for(
            resolved,
            HAWKBIT_UPLOAD.BOOT_SMOKE_THRESHOLD_NAME,
            "boot_smoke_machine_status",
        )["pattern"] = "^idle$"
        matcher_for(
            resolved, HAWKBIT_UPLOAD.BOOT_SMOKE_THRESHOLD_NAME, "boot_smoke_dial"
        )["pattern"] = "false"

        pinned, _synthesized = HAWKBIT_UPLOAD.pin_thresholds(
            resolved, "2026M1340-stable"
        )

        self.assertEqual(
            matcher_for(
                pinned,
                HAWKBIT_UPLOAD.BOOT_SMOKE_THRESHOLD_NAME,
                "boot_smoke_machine_status",
            )["pattern"],
            "^idle$",
        )
        self.assertEqual(
            matcher_for(
                pinned, HAWKBIT_UPLOAD.BOOT_SMOKE_THRESHOLD_NAME, "boot_smoke_dial"
            )["pattern"],
            "false",
        )

    def test_synthesizes_thresholds_when_the_manager_resolved_none(self):
        pinned, synthesized = HAWKBIT_UPLOAD.pin_thresholds([], "2026M1340-stable")

        self.assertEqual(
            {threshold["name"] for threshold in pinned},
            {
                HAWKBIT_UPLOAD.BOOT_SMOKE_THRESHOLD_NAME,
                HAWKBIT_UPLOAD.POST_UPDATE_SHOT_THRESHOLD_NAME,
            },
        )
        self.assertIn(
            f"threshold '{HAWKBIT_UPLOAD.BOOT_SMOKE_THRESHOLD_NAME}'", synthesized
        )
        self.assertEqual(
            matcher_for(
                pinned,
                HAWKBIT_UPLOAD.BOOT_SMOKE_THRESHOLD_NAME,
                HAWKBIT_UPLOAD.BOOT_SMOKE_VERSION_ATTRIBUTE,
            )["pattern"],
            "2026M1340-stable",
        )

    def test_synthesizes_only_the_threshold_that_is_missing(self):
        resolved = [
            threshold
            for threshold in self.resolved_defaults()
            if threshold["name"] == HAWKBIT_UPLOAD.BOOT_SMOKE_THRESHOLD_NAME
        ]

        pinned, synthesized = HAWKBIT_UPLOAD.pin_thresholds(
            resolved, "2026M1340-stable"
        )

        self.assertEqual(
            synthesized,
            [f"threshold '{HAWKBIT_UPLOAD.POST_UPDATE_SHOT_THRESHOLD_NAME}'"],
        )
        self.assertEqual(len(pinned), 2)

    def test_appends_a_matcher_the_resolved_threshold_does_not_carry(self):
        resolved = self.resolved_defaults()
        boot_smoke = next(
            threshold
            for threshold in resolved
            if threshold["name"] == HAWKBIT_UPLOAD.BOOT_SMOKE_THRESHOLD_NAME
        )
        boot_smoke["attributes"] = [
            matcher
            for matcher in boot_smoke["attributes"]
            if matcher["name"] != HAWKBIT_UPLOAD.BOOT_SMOKE_VERSION_ATTRIBUTE
        ]

        pinned, synthesized = HAWKBIT_UPLOAD.pin_thresholds(
            resolved, "2026M1340-stable"
        )

        self.assertEqual(
            synthesized,
            [
                f"matcher '{HAWKBIT_UPLOAD.BOOT_SMOKE_VERSION_ATTRIBUTE}' "
                f"on '{HAWKBIT_UPLOAD.BOOT_SMOKE_THRESHOLD_NAME}'"
            ],
        )
        self.assertEqual(
            matcher_for(
                pinned,
                HAWKBIT_UPLOAD.BOOT_SMOKE_THRESHOLD_NAME,
                HAWKBIT_UPLOAD.BOOT_SMOKE_VERSION_ATTRIBUTE,
            )["pattern"],
            "2026M1340-stable",
        )

    def test_the_synthesized_thresholds_mirror_the_deployed_defaults(self):
        """
        Guards the copy in FALLBACK_THRESHOLDS against drifting in shape from
        default_thresholds.json in MeticulousHome/hawkbit-docker-deployment.
        """
        for threshold in HAWKBIT_UPLOAD.FALLBACK_THRESHOLDS:
            self.assertEqual(
                set(threshold), {"name", "percentage", "attributes"}
            )
            self.assertTrue(0 <= threshold["percentage"] <= 100)
            self.assertTrue(threshold["attributes"])
            for matcher in threshold["attributes"]:
                self.assertEqual(set(matcher), {"name", "type", "pattern"})
                self.assertIn(matcher["type"], {"exact", "regex"})
                self.assertTrue(matcher["pattern"])
                if matcher["type"] == "regex":
                    re.compile(matcher["pattern"])


class RolloutManagerRequestTests(unittest.TestCase):
    def setUp(self):
        self.client = HAWKBIT_UPLOAD.HawkbitMgmtClient(
            "hawkbit.example.com", 443, username="user", password="secret"
        )

    def test_targets_the_admin_api_outside_rest_v1(self):
        response = fake_response(200, {"source": "default", "thresholds": []})

        with mock.patch.object(HAWKBIT_UPLOAD.r, "get", return_value=response) as get:
            self.client.get_rollout_thresholds(42)

        self.assertEqual(
            get.call_args.args[0],
            "https://hawkbit.example.com:443/rollout-manager/rollouts/42/thresholds",
        )

    def test_uses_http_for_a_non_443_port(self):
        client = HAWKBIT_UPLOAD.HawkbitMgmtClient("localhost", 8092)

        self.assertEqual(
            client.rollout_manager_url.format(endpoint="rollouts/1/thresholds"),
            "http://localhost:8092/rollout-manager/rollouts/1/thresholds",
        )

    def test_an_explicit_base_url_overrides_the_derived_one(self):
        client = HAWKBIT_UPLOAD.HawkbitMgmtClient(
            "hawkbit.example.com",
            443,
            rollout_manager_base="http://127.0.0.1:8092/rollout-manager/",
        )

        self.assertEqual(
            client.rollout_manager_url.format(endpoint="rollouts/1/thresholds"),
            "http://127.0.0.1:8092/rollout-manager/rollouts/1/thresholds",
        )

    def test_sends_the_hawkbit_credentials(self):
        response = fake_response(200, {"source": "default", "thresholds": []})

        with mock.patch.object(HAWKBIT_UPLOAD.r, "get", return_value=response) as get:
            self.client.get_rollout_thresholds(42)

        self.assertEqual(get.call_args.kwargs["auth"], ("user", "secret"))

    def test_put_sends_the_pinned_list_as_the_body(self):
        pinned = [{"name": "boot_smoke", "percentage": 80, "attributes": []}]
        response = fake_response(200, {"source": "override", "thresholds": pinned})

        with mock.patch.object(HAWKBIT_UPLOAD.r, "put", return_value=response) as put:
            self.client.put_rollout_thresholds(42, pinned)

        self.assertEqual(put.call_args.kwargs["json"], pinned)
        self.assertEqual(
            put.call_args.args[0],
            "https://hawkbit.example.com:443/rollout-manager/rollouts/42/thresholds",
        )

    def test_the_threshold_put_inherits_the_retry_policy(self):
        pinned = [{"name": "boot_smoke", "percentage": 80, "attributes": []}]
        responses = [
            fake_response(502),
            fake_response(200, {"source": "override", "thresholds": pinned}),
        ]

        with mock.patch.object(HAWKBIT_UPLOAD.r, "put", side_effect=responses) as put:
            with mock.patch.object(HAWKBIT_UPLOAD.time, "sleep"):
                self.client.put_rollout_thresholds(42, pinned)

        self.assertEqual(put.call_count, 2)


class ApplyRolloutThresholdsTests(unittest.TestCase):
    def setUp(self):
        self.client = mock.Mock()
        self.client.get_rollout_thresholds.return_value = {
            "source": "default",
            "thresholds": json.loads(json.dumps(HAWKBIT_UPLOAD.FALLBACK_THRESHOLDS)),
        }
        self.client.put_rollout_thresholds.return_value = {"source": "override"}

    def test_puts_the_pinned_thresholds_and_reports_success(self):
        result = HAWKBIT_UPLOAD.apply_rollout_thresholds(
            self.client, 42, "2026M1340-stable"
        )

        self.assertTrue(result)
        rollout_id, pinned = self.client.put_rollout_thresholds.call_args.args
        self.assertEqual(rollout_id, 42)
        self.assertEqual(
            matcher_for(
                pinned,
                HAWKBIT_UPLOAD.BOOT_SMOKE_THRESHOLD_NAME,
                HAWKBIT_UPLOAD.BOOT_SMOKE_VERSION_ATTRIBUTE,
            )["pattern"],
            "2026M1340-stable",
        )

    def test_reports_failure_when_the_get_fails(self):
        self.client.get_rollout_thresholds.side_effect = HAWKBIT_UPLOAD.HawkbitError(
            "HTTP error 502"
        )

        result = HAWKBIT_UPLOAD.apply_rollout_thresholds(
            self.client, 42, "2026M1340-stable"
        )

        self.assertFalse(result)
        self.client.put_rollout_thresholds.assert_not_called()

    def test_reports_failure_when_the_put_fails(self):
        self.client.put_rollout_thresholds.side_effect = HAWKBIT_UPLOAD.HawkbitError(
            "HTTP error 400"
        )

        result = HAWKBIT_UPLOAD.apply_rollout_thresholds(
            self.client, 42, "2026M1340-stable"
        )

        self.assertFalse(result)


if __name__ == "__main__":
    unittest.main()
