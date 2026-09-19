import json
import subprocess
import tempfile
import unittest
from pathlib import Path


from scripts.validate_component_contracts import ContractError, validate_pair


def run(command, cwd):
    return subprocess.run(command, cwd=cwd, check=True, capture_output=True, text=True)


def create_repo(root: Path, component: str, contract=None) -> Path:
    repo = root / component
    repo.mkdir()
    run(["git", "init"], repo)
    run(["git", "config", "user.name", "Contract Test"], repo)
    run(["git", "config", "user.email", "contract@example.com"], repo)
    (repo / "README.md").write_text(f"# {component}\n", encoding="utf-8")
    if contract is not None:
        (repo / "release-contract.json").write_text(
            json.dumps(contract), encoding="utf-8"
        )
    run(["git", "add", "."], repo)
    run(["git", "commit", "-m", "fixture"], repo)
    return repo


def contract(component, *, requires=None, provides=None):
    return {
        "schema_version": 1,
        "component": component,
        "requires": requires or [],
        "provides": provides or [],
    }


class ComponentContractTests(unittest.TestCase):
    def test_compatible_legacy_pair(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            dial = create_repo(root, "meticulous-dial", contract("meticulous-dial"))
            backend = create_repo(root, "meticulous-backend")

            result = validate_pair(dial, backend)

            self.assertEqual(result["dial_requires"], [])
            self.assertEqual(result["backend_provides"], [])

    def test_compatible_modern_pair(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            capability = "wifi-health-repair-v1"
            dial = create_repo(
                root,
                "meticulous-dial",
                contract("meticulous-dial", requires=[capability]),
            )
            backend = create_repo(
                root,
                "meticulous-backend",
                contract("meticulous-backend", provides=[capability]),
            )

            result = validate_pair(dial, backend)

            self.assertEqual(result["dial_requires"], [capability])
            self.assertEqual(result["backend_provides"], [capability])

    def test_incompatible_pair_fails(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            capability = "wifi-health-repair-v1"
            dial = create_repo(
                root,
                "meticulous-dial",
                contract("meticulous-dial", requires=[capability]),
            )
            backend = create_repo(root, "meticulous-backend")

            with self.assertRaisesRegex(ContractError, capability):
                validate_pair(dial, backend)

    def test_dial_without_contract_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            dial = create_repo(root, "meticulous-dial")
            backend = create_repo(root, "meticulous-backend")

            with self.assertRaisesRegex(ContractError, "missing release-contract.json"):
                validate_pair(dial, backend)


if __name__ == "__main__":
    unittest.main()
