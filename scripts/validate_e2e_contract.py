#!/usr/bin/env python3
"""Validate the E2E coverage inventory against checked-out component sources."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = REPO_ROOT / "e2e" / "contracts" / "coverage.json"


def load_manifest(path: Path = DEFAULT_MANIFEST) -> dict:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def flatten_screen_groups(manifest: dict) -> list[str]:
    return [
        screen
        for screens in manifest["dial"]["screen_groups"].values()
        for screen in screens
    ]


def _duplicates(values: Iterable[str]) -> list[str]:
    seen: set[str] = set()
    duplicates: set[str] = set()
    for value in values:
        if value in seen:
            duplicates.add(value)
        seen.add(value)
    return sorted(duplicates)


def validate_manifest(manifest: dict) -> list[str]:
    errors: list[str] = []
    if manifest.get("schema_version") != 1:
        errors.append("schema_version must be 1")

    screens = flatten_screen_groups(manifest)
    duplicates = _duplicates(screens)
    if duplicates:
        errors.append(f"Dial screens assigned to multiple groups: {duplicates}")

    journey_ids = [journey["id"] for journey in manifest.get("journeys", [])]
    duplicate_journeys = _duplicates(journey_ids)
    if duplicate_journeys:
        errors.append(f"Duplicate journey ids: {duplicate_journeys}")

    groups = set(manifest["dial"]["screen_groups"])
    valid_tiers = {"simulated", "rootfs", "hil"}
    valid_priorities = {"P0", "P1", "P2"}
    valid_statuses = {"planned", "implemented", "blocked"}
    for journey in manifest.get("journeys", []):
        unknown_groups = set(journey.get("screen_groups", [])) - groups - {"*"}
        if unknown_groups:
            errors.append(
                f"Journey {journey['id']} references unknown screen groups: "
                f"{sorted(unknown_groups)}"
            )
        unknown_tiers = set(journey.get("tiers", [])) - valid_tiers
        if unknown_tiers:
            errors.append(
                f"Journey {journey['id']} references unknown tiers: {sorted(unknown_tiers)}"
            )
        if journey.get("priority") not in valid_priorities:
            errors.append(f"Journey {journey['id']} has an invalid priority")
        if journey.get("status") not in valid_statuses:
            errors.append(f"Journey {journey['id']} has an invalid status")
        if not journey.get("summary"):
            errors.append(f"Journey {journey['id']} needs a summary")

    for section_name, values in (
        ("dial.api_methods", manifest["dial"]["api_methods"]),
        ("dial.socket_receives", manifest["dial"]["socket_receives"]),
        ("dial.socket_emits", manifest["dial"]["socket_emits"]),
        ("backend.api_routes", manifest["backend"]["api_routes"]),
        ("backend.socket_receives", manifest["backend"]["socket_receives"]),
        ("backend.socket_emits", manifest["backend"]["socket_emits"]),
        ("firmware.uart_incoming_keys", manifest["firmware"]["uart_incoming_keys"]),
        ("firmware.uart_actions", manifest["firmware"]["uart_actions"]),
        ("image.component_sources", manifest["image"]["component_sources"]),
    ):
        duplicates = _duplicates(values)
        if duplicates:
            errors.append(f"{section_name} contains duplicates: {duplicates}")

    if not any(
        journey.get("screen_groups") == ["*"] for journey in manifest["journeys"]
    ):
        errors.append(
            "At least one journey must explicitly cover every Dial screen group"
        )

    return errors


def _read_tree(root: Path, pattern: str) -> str:
    # The NUL sentinel prevents a regex from accidentally matching across two
    # unrelated files when one ends with an incomplete-looking expression.
    return "\n\0\n".join(
        path.read_text(encoding="utf-8", errors="replace")
        for path in sorted(root.glob(pattern))
        if path.is_file()
    )


def _compare(label: str, actual: Iterable[str], expected: Iterable[str]) -> list[str]:
    actual_set = set(actual)
    expected_set = set(expected)
    errors: list[str] = []
    missing = sorted(expected_set - actual_set)
    unexpected = sorted(actual_set - expected_set)
    if missing:
        errors.append(f"{label}: missing from source: {missing}")
    if unexpected:
        errors.append(f"{label}: not inventoried: {unexpected}")
    return errors


def discover_dial(dial_root: Path) -> dict[str, set[str]]:
    screen_source = (
        dial_root / "src/components/store/features/screens/screens-slice.ts"
    ).read_text(encoding="utf-8")
    screen_block = re.search(
        r"export type ScreenType\s*=\s*(?P<body>.*?);", screen_source, re.DOTALL
    )
    if not screen_block:
        raise ValueError("Could not find Dial ScreenType")
    screens = set(re.findall(r"\|\s*'([^']+)'", screen_block.group("body")))

    route_source = (dial_root / "src/navigation/routes.ts").read_text(encoding="utf-8")
    route_matches = re.findall(
        r"^\s{2}(?:'([^']+)'|([A-Za-z0-9_]+)):\s*\{", route_source, re.MULTILINE
    )
    routes = {quoted or bare for quoted, bare in route_matches}

    source = _read_tree(dial_root / "src", "**/*.ts")
    source += "\n" + _read_tree(dial_root / "src", "**/*.tsx")
    api_methods = set(re.findall(r"\bapi\.([A-Za-z][A-Za-z0-9_]*)\s*\(", source))
    socket_receives = set(re.findall(r"socket\.on\(\s*['\"]([^'\"]+)['\"]", source))
    socket_emits = set(re.findall(r"socket\.emit\(\s*['\"]([^'\"]+)['\"]", source))
    return {
        "screens": screens,
        "routes": routes,
        "api_methods": api_methods,
        "socket_receives": socket_receives,
        "socket_emits": socket_emits,
    }


def discover_backend(backend_root: Path) -> dict[str, set[str]]:
    api_source = _read_tree(backend_root / "api", "**/*.py")
    source = _read_tree(backend_root, "*.py") + "\n" + api_source
    routes = set(
        re.findall(
            r'API\.register_handler\(\s*APIVersion\.V1,\s*r"([^"]+)"',
            api_source,
            re.DOTALL,
        )
    )
    socket_receives = set(re.findall(r'@sio\.on\(\s*["\']([^"\']+)["\']', source))
    socket_emits = set(re.findall(r'\.emit\(\s*["\']([^"\']+)["\']', source))

    machine_source = (backend_root / "machine.py").read_text(encoding="utf-8")
    actions: set[str] = set()
    for name in ("ALLOWED_BACKEND_ACTIONS", "ALLOWED_ESP_ACTIONS"):
        match = re.search(rf"{name}\s*=\s*\[(?P<body>.*?)\]", machine_source, re.DOTALL)
        if match:
            actions.update(re.findall(r'["\']([^"\']+)["\']', match.group("body")))

    emulation_source = (
        backend_root / "esp_serial/connection/emulation_data.py"
    ).read_text(encoding="utf-8")
    emulator_source = (
        backend_root / "esp_serial/connection/emulator_serial_connection.py"
    ).read_text(encoding="utf-8")
    scenarios = {"idle"}
    if "ESPRESSO_DATA" in emulation_source and 'b"action,start"' in emulator_source:
        scenarios.add("espresso")
    if "HOME_DATA" in emulation_source and 'b"action,home"' in emulator_source:
        scenarios.add("home")
    if "PURGE_DATA" in emulation_source and 'b"action,purge"' in emulator_source:
        scenarios.add("purge")

    return {
        "api_routes": routes,
        "socket_receives": socket_receives,
        "socket_emits": socket_emits,
        "allowed_actions": actions,
        "emulation_scenarios": scenarios,
    }


def _map_keys(source: str, map_name: str) -> set[str]:
    block = re.search(rf"{map_name}\s*\{{(?P<body>.*?)\}};", source, re.DOTALL)
    if not block:
        raise ValueError(f"Could not find firmware map {map_name}")
    return set(re.findall(r'\{"([^"]+)"', block.group("body")))


def discover_firmware(firmware_root: Path) -> dict[str, set[str]]:
    uart_source = (firmware_root / "lib/FikaUart/FikaUart.cpp").read_text(
        encoding="utf-8"
    )
    firmware_source = _read_tree(firmware_root / "lib", "**/*.cpp")
    firmware_source += "\n" + _read_tree(firmware_root / "lib", "**/*.h")
    firmware_source += "\n" + _read_tree(firmware_root / "src", "**/*.cpp")
    firmware_source += "\n" + _read_tree(firmware_root / "include", "**/*.h")
    outbound_messages: set[str] = set()
    for pattern in (
        r'std::cout[ \t]*<<[ \t]*"([A-Za-z_]+),',
        r'\bbuffer[ \t]*<<[ \t]*"([A-Za-z_]+),',
        r'\bString[ \t]+\w+[ \t]*=[ \t]*"([A-Za-z_]+),',
        r'\buart_print\([ \t]*"([A-Za-z_]+),',
        r'\bsprintf\([^,]+,[ \t]*"([A-Za-z_]+),',
        r'\bmessage[ \t]*<<[ \t]*"([A-Za-z_]+),',
    ):
        outbound_messages.update(re.findall(pattern, firmware_source))
    # Lower-case fragments such as "none,..." are continuations of a Data
    # record, not independent messages. nvs_response is the one lower-case
    # top-level protocol prefix in the current UART contract.
    outbound_messages = {
        message
        for message in outbound_messages
        if message[0].isupper() or message == "nvs_response"
    }
    return {
        "uart_incoming_keys": _map_keys(uart_source, "incomming_keys_map"),
        "uart_actions": _map_keys(uart_source, "command_action_map"),
        "uart_outbound_messages": outbound_messages,
    }


def discover_machine(machine_root: Path) -> dict[str, set[str]]:
    config_source = (machine_root / "config.sh").read_text(encoding="utf-8")
    component_sources = set(
        re.findall(
            r"^(?:readonly\s+|export\s+)?\s*([A-Z0-9_]+)_GIT=",
            config_source,
            re.MULTILINE,
        )
    )
    return {"component_sources": component_sources}


def validate_sources(
    manifest: dict,
    machine_root: Path,
    dial_root: Path,
    backend_root: Path,
    firmware_root: Path,
) -> list[str]:
    errors: list[str] = []
    dial = discover_dial(dial_root)
    expected_screens = flatten_screen_groups(manifest)
    errors += _compare("Dial ScreenType", dial["screens"], expected_screens)
    errors += _compare("Dial routes", dial["routes"], expected_screens)
    errors += _compare(
        "Dial API methods", dial["api_methods"], manifest["dial"]["api_methods"]
    )
    errors += _compare(
        "Dial Socket.IO receives",
        dial["socket_receives"],
        manifest["dial"]["socket_receives"],
    )
    errors += _compare(
        "Dial Socket.IO emits", dial["socket_emits"], manifest["dial"]["socket_emits"]
    )

    backend = discover_backend(backend_root)
    for key, label in (
        ("api_routes", "Backend API routes"),
        ("socket_receives", "Backend Socket.IO receives"),
        ("socket_emits", "Backend Socket.IO emits"),
        ("allowed_actions", "Backend allowed actions"),
        ("emulation_scenarios", "Backend emulation scenarios"),
    ):
        errors += _compare(label, backend[key], manifest["backend"][key])

    firmware = discover_firmware(firmware_root)
    for key, label in (
        ("uart_incoming_keys", "Firmware UART incoming keys"),
        ("uart_actions", "Firmware UART actions"),
        ("uart_outbound_messages", "Firmware UART outbound messages"),
    ):
        errors += _compare(label, firmware[key], manifest["firmware"][key])

    machine = discover_machine(machine_root)
    errors += _compare(
        "Machine component sources",
        machine["component_sources"],
        manifest["image"]["component_sources"],
    )

    service_roots = [
        machine_root / "system-services",
        machine_root / "config/usr/lib/systemd/system",
    ]
    for service in manifest["image"]["required_services"]:
        if not any((root / service).is_file() for root in service_roots):
            errors.append(f"Machine required service is missing: {service}")

    nginx_source = (
        machine_root / "config/etc/nginx/sites-available/default"
    ).read_text(encoding="utf-8")
    for contract in manifest["image"]["nginx_contracts"]:
        if contract not in nginx_source:
            errors.append(f"Machine Nginx contract is missing: {contract}")

    for channel in ("beta", "stable"):
        if not (machine_root / f"images/{channel}.versions.sh").is_file():
            errors.append(f"Machine channel manifest is missing: {channel}")
    if "nightly" not in manifest["image"]["channels"]:
        errors.append("Machine inventory must include nightly config.sh defaults")

    return errors


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--machine", type=Path, default=REPO_ROOT)
    parser.add_argument("--dial", type=Path)
    parser.add_argument("--backend", type=Path)
    parser.add_argument("--firmware", type=Path)
    parser.add_argument(
        "--self-check",
        action="store_true",
        help="Validate only manifest structure; component paths are not required.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    manifest = load_manifest(args.manifest)
    errors = validate_manifest(manifest)

    if not args.self_check:
        missing_args = [
            name
            for name in ("dial", "backend", "firmware")
            if getattr(args, name) is None
        ]
        if missing_args:
            errors.append(
                "Full validation requires component paths: " + ", ".join(missing_args)
            )
        else:
            errors += validate_sources(
                manifest,
                args.machine.resolve(),
                args.dial.resolve(),
                args.backend.resolve(),
                args.firmware.resolve(),
            )

    if errors:
        print("E2E contract inventory validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    screens = flatten_screen_groups(manifest)
    print(
        "E2E contract inventory is valid: "
        f"{len(screens)} Dial screens, "
        f"{len(manifest['backend']['api_routes'])} backend routes, "
        f"{len(manifest['firmware']['uart_actions'])} firmware actions, "
        f"{len(manifest['image']['component_sources'])} image component sources, "
        f"{len(manifest['journeys'])} planned journeys."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
