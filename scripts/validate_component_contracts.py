#!/usr/bin/env python3
"""Validate release contracts for the exact Dial/backend source pair."""

import argparse
import json
import subprocess
import sys
from pathlib import Path


CONTRACT_FILE = "release-contract.json"


class ContractError(ValueError):
    pass


def git_head(repo: Path) -> str:
    try:
        return subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=repo,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as error:
        raise ContractError(f"{repo} is not a readable Git checkout") from error


def load_contract(repo: Path, component: str, *, required: bool) -> dict:
    contract_path = repo / CONTRACT_FILE
    if not contract_path.is_file():
        if required:
            raise ContractError(
                f"{component} {git_head(repo)} is missing {CONTRACT_FILE}"
            )
        return {
            "schema_version": 1,
            "component": component,
            "requires": [],
            "provides": [],
        }

    try:
        contract = json.loads(contract_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ContractError(f"invalid {component} {CONTRACT_FILE}: {error}") from error

    if contract.get("schema_version") != 1:
        raise ContractError(f"{component} contract must use schema_version 1")
    if contract.get("component") != component:
        raise ContractError(
            f"{component} contract declares component {contract.get('component')!r}"
        )

    for field in ("requires", "provides"):
        values = contract.get(field, [])
        if not isinstance(values, list) or any(
            not isinstance(value, str) or not value for value in values
        ):
            raise ContractError(f"{component} contract field {field} must be a string list")
        if len(values) != len(set(values)):
            raise ContractError(f"{component} contract field {field} contains duplicates")
        contract[field] = values

    return contract


def validate_pair(dial_repo: Path, backend_repo: Path) -> dict:
    dial_sha = git_head(dial_repo)
    backend_sha = git_head(backend_repo)
    dial = load_contract(dial_repo, "meticulous-dial", required=True)
    backend = load_contract(backend_repo, "meticulous-backend", required=False)

    missing = sorted(set(dial["requires"]) - set(backend["provides"]))
    if missing:
        raise ContractError(
            "incompatible Dial/backend release pair: "
            f"Dial {dial_sha} requires {', '.join(missing)}; "
            f"backend {backend_sha} does not provide it"
        )

    return {
        "dial_sha": dial_sha,
        "backend_sha": backend_sha,
        "dial_requires": sorted(dial["requires"]),
        "backend_provides": sorted(backend["provides"]),
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dial", required=True, type=Path)
    parser.add_argument("--backend", required=True, type=Path)
    args = parser.parse_args(argv)

    try:
        result = validate_pair(args.dial, args.backend)
    except ContractError as error:
        print(f"release contract validation failed: {error}", file=sys.stderr)
        return 1

    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
