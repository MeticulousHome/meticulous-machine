import importlib.util
from pathlib import Path
import tempfile
import unittest


SCRIPT_PATH = Path(__file__).parents[1] / "scripts" / "validate_e2e_contract.py"
SPEC = importlib.util.spec_from_file_location("validate_e2e_contract", SCRIPT_PATH)
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)
NGINX_SITE = Path(__file__).parents[1] / "config/etc/nginx/sites-available/default"
DEVICE_AUTH_REAL_IP = "\t\tproxy_set_header X-Real-IP $remote_addr;\n"


class E2EContractManifestTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = VALIDATOR.load_manifest()

    def test_manifest_is_internally_consistent(self):
        self.assertEqual(VALIDATOR.validate_manifest(self.manifest), [])

    def test_every_screen_is_owned_by_exactly_one_group(self):
        screens = VALIDATOR.flatten_screen_groups(self.manifest)
        self.assertEqual(len(screens), len(set(screens)))

    def test_every_journey_has_a_status_at_each_of_its_tiers(self):
        for journey in self.manifest["journeys"]:
            with self.subTest(journey=journey["id"]):
                self.assertTrue(journey["tiers"])
                for status in journey["tiers"].values():
                    self.assertIn(status, {"planned", "implemented", "blocked"})

    def test_a_status_outside_the_tiers_is_refused(self):
        journey = dict(self.manifest["journeys"][0], status="implemented")
        manifest = dict(self.manifest, journeys=[journey])
        self.assertIn(
            f"Journey {journey['id']}: the status is per tier, in tiers",
            VALIDATOR.validate_manifest(manifest),
        )

    def test_an_unknown_status_at_a_tier_is_refused(self):
        journey = dict(self.manifest["journeys"][0], tiers={"simulated": "done"})
        manifest = dict(self.manifest, journeys=[journey])
        self.assertIn(
            f"Journey {journey['id']} has an invalid status at simulated: 'done'",
            VALIDATOR.validate_manifest(manifest),
        )

    def test_a_journey_without_an_owner_is_refused(self):
        journey = {k: v for k, v in self.manifest["journeys"][0].items() if k != "owner"}
        manifest = dict(self.manifest, journeys=[journey])
        self.assertIn(
            f"Journey {journey['id']} needs an owner, one of "
            "['meticulous-integration', 'meticulous-mobile'], not None",
            VALIDATOR.validate_manifest(manifest),
        )

    def test_the_app_journeys_are_owned_by_the_app(self):
        # meticulous-mobile's own gates run them; meticulous-integration must
        # not fail for want of a test of its own.
        owners = {journey["id"]: journey["owner"] for journey in self.manifest["journeys"]}
        self.assertEqual(owners["app-add-machine"], "meticulous-mobile")
        self.assertEqual(owners["app-reconnect"], "meticulous-mobile")

    def test_full_route_reachability_is_a_p0_target(self):
        journey = next(
            item
            for item in self.manifest["journeys"]
            if item["id"] == "dial-all-routes-reachable"
        )
        self.assertEqual(journey["priority"], "P0")
        self.assertEqual(journey["screen_groups"], ["*"])

    def test_known_contract_gaps_have_follow_up_actions(self):
        for gap in self.manifest["known_gaps"]:
            with self.subTest(gap=gap["id"]):
                self.assertTrue(gap["evidence"])
                self.assertTrue(gap["next_step"])

    def test_set_comparison_detects_contract_drift(self):
        errors = VALIDATOR._compare("example", {"kept", "new"}, {"kept", "removed"})
        self.assertEqual(
            errors,
            [
                "example: missing from source: ['removed']",
                "example: not inventoried: ['new']",
            ],
        )

    def test_a_qt_dial_is_inventoried_from_its_qml(self):
        with tempfile.TemporaryDirectory() as tmp:
            core = Path(tmp) / "qt/qml/Dial/Core"
            core.mkdir(parents=True)
            (core / "Routes.qml").write_text(
                'QtObject {\n    readonly property var order: [\n        "profileHome", "settings"\n    ]\n}\n'
            )
            (core / "Backend.qml").write_text(
                "QtObject {\n"
                "    function action(name) { Socket.emitEvent(\"action\", name) }\n"
                "    property Connections _socket: Connections {\n"
                "        function onEvent(name, data) {\n"
                "            switch (name) {\n"
                '            case "status": break\n'
                '            case "sensors": break\n'
                "            }\n"
                "        }\n"
                "    }\n"
                "}\n"
            )
            (core / "Api.qml").write_text(
                'QtObject {\n    function getSettings(name) { return get(v + "/settings/" + name) }\n}\n'
            )
            (Path(tmp) / "qt/qml/Dial/Home.qml").write_text(
                'Item { Component.onCompleted: { Api.getSettings(); Api.get("/x"); Backend.emitEvent("profileHover", {}) } }\n'
            )
            dial = VALIDATOR.discover_dial(Path(tmp))
        self.assertEqual(dial["screens"], {"profileHome", "settings"})
        self.assertEqual(dial["routes"], {"profileHome", "settings"})
        self.assertEqual(dial["api_methods"], {"getSettings"})
        self.assertEqual(dial["socket_receives"], {"status", "sensors"})
        self.assertEqual(dial["socket_emits"], {"action", "profileHover"})

    def test_the_shipped_nginx_site_meets_its_contracts(self):
        source = NGINX_SITE.read_text(encoding="utf-8")
        self.assertEqual(VALIDATOR.validate_nginx(self.manifest, source), [])

    def test_the_device_auth_subrequest_must_set_x_real_ip_itself(self):
        # Without it the backend sees no X-Real-IP, which it treats as the
        # machine, or one the client forged, so /health opens to the LAN. The
        # same line in the /api and /health blocks must not stand in for it.
        source = NGINX_SITE.read_text(encoding="utf-8")
        start = source.index("location = /_device_auth {")
        line = source.index(DEVICE_AUTH_REAL_IP, start)
        stripped = source[:line] + source[line + len(DEVICE_AUTH_REAL_IP):]
        self.assertNotIn(
            DEVICE_AUTH_REAL_IP.strip(),
            VALIDATOR.nginx_block(stripped, "location = /_device_auth {"),
        )
        self.assertIn(DEVICE_AUTH_REAL_IP.strip(), stripped)
        self.assertIn(
            "Machine Nginx location 'location = /_device_auth {' is missing: "
            "proxy_set_header X-Real-IP $remote_addr;",
            VALIDATOR.validate_nginx(self.manifest, stripped),
        )

    def test_a_commented_out_directive_does_not_meet_a_location_contract(self):
        source = NGINX_SITE.read_text(encoding="utf-8").replace(
            "\t\tauth_request /_device_auth;", "\t\t# auth_request /_device_auth;"
        )
        self.assertIn(
            "Machine Nginx location 'location ~* ^/health {' is missing: "
            "auth_request /_device_auth;",
            VALIDATOR.validate_nginx(self.manifest, source),
        )

    def test_a_location_block_ends_at_its_own_closing_brace(self):
        source = (
            "server {\n"
            "    location @denied {\n"
            "        return 401 '{\"error\":{\"code\":\"X\"}}'; # } not a brace\n"
            "        if ($a) { set $b 1; }\n"
            "    }\n"
            "    location /after { deny all; }\n"
            "}\n"
        )
        block = VALIDATOR.nginx_block(source, "location @denied {")
        self.assertIn("return 401", block)
        self.assertIn("set $b 1;", block)
        self.assertNotIn("deny all;", block)
        self.assertIsNone(VALIDATOR.nginx_block(source, "location /missing {"))


if __name__ == "__main__":
    unittest.main()
