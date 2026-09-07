import importlib.util
from pathlib import Path
import unittest


SCRIPT_PATH = Path(__file__).parents[1] / "scripts" / "validate_e2e_contract.py"
SPEC = importlib.util.spec_from_file_location("validate_e2e_contract", SCRIPT_PATH)
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


class E2EContractManifestTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = VALIDATOR.load_manifest()

    def test_manifest_is_internally_consistent(self):
        self.assertEqual(VALIDATOR.validate_manifest(self.manifest), [])

    def test_every_screen_is_owned_by_exactly_one_group(self):
        screens = VALIDATOR.flatten_screen_groups(self.manifest)
        self.assertEqual(len(screens), len(set(screens)))

    def test_every_journey_has_a_test_tier_and_explicit_status(self):
        for journey in self.manifest["journeys"]:
            with self.subTest(journey=journey["id"]):
                self.assertTrue(journey["tiers"])
                self.assertIn(journey["status"], {"planned", "implemented", "blocked"})

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


if __name__ == "__main__":
    unittest.main()
