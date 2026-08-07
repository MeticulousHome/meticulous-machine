#!/usr/bin/env python3

import argparse
import importlib.util
import os
from pathlib import Path


POLLING_TIME_KEY = "pollingTime"
HOURLY_POLLING_TIME = "01:00:00"


class PollingConfigurationError(Exception):
    """A sanitized failure configuring Hawkbit tenant polling."""


def load_management_client():
    client_path = Path(__file__).with_name("hawkbit-upload.py")
    spec = importlib.util.spec_from_file_location("hawkbit_upload", client_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.HawkbitMgmtClient


def configure_hourly_polling(client, apply=False, output=print):
    try:
        current_value = client.get_config(POLLING_TIME_KEY)
    except Exception:
        raise PollingConfigurationError(
            "Failed to read the current Hawkbit pollingTime."
        ) from None

    output(f"Current Hawkbit pollingTime: {current_value}")

    if current_value == HOURLY_POLLING_TIME:
        output("Hawkbit pollingTime is already 01:00:00; no change is needed.")
        return

    if not apply:
        output(
            f"[DRY RUN] Would change Hawkbit pollingTime from "
            f"{current_value} to {HOURLY_POLLING_TIME}."
        )
        return

    try:
        client.set_config(POLLING_TIME_KEY, HOURLY_POLLING_TIME)
    except Exception:
        raise PollingConfigurationError(
            "Failed to write the Hawkbit pollingTime."
        ) from None

    try:
        readback_value = client.get_config(POLLING_TIME_KEY)
    except Exception:
        raise PollingConfigurationError(
            "Failed to read back the Hawkbit pollingTime."
        ) from None

    if readback_value != HOURLY_POLLING_TIME:
        raise PollingConfigurationError(
            "Hawkbit pollingTime readback did not equal 01:00:00."
        )

    output("Hawkbit pollingTime readback verified: 01:00:00.")


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Idempotently configure hourly Hawkbit tenant polling."
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Write the change. Without this flag, the operation is a dry run.",
    )
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    required_environment = (
        "HAWKBIT_SERVER",
        "HAWKBIT_PORT",
        "HAWKBIT_USER",
        "HAWKBIT_PASSWORD",
    )
    missing = [name for name in required_environment if not os.environ.get(name)]
    if missing:
        print(f"Missing required environment variables: {', '.join(missing)}")
        return 1

    try:
        port = int(os.environ["HAWKBIT_PORT"])
    except ValueError:
        print("HAWKBIT_PORT must be an integer.")
        return 1

    management_client = load_management_client()
    client = management_client(
        os.environ["HAWKBIT_SERVER"],
        port,
        username=os.environ["HAWKBIT_USER"],
        password=os.environ["HAWKBIT_PASSWORD"],
    )

    if not args.apply:
        print("[DRY RUN] No changes will be sent to Hawkbit.")

    try:
        configure_hourly_polling(client, apply=args.apply)
    except PollingConfigurationError as error:
        print(f"Error: {error}")
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
