import importlib.util
from pathlib import Path
import unittest

SCRIPT_PATH = Path(__file__).parents[1] / "misc" / "hawkbit-upload.py"
SPEC = importlib.util.spec_from_file_location("hawkbit_upload", SCRIPT_PATH)
HAWKBIT_UPLOAD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HAWKBIT_UPLOAD)


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


if __name__ == "__main__":
    unittest.main()
