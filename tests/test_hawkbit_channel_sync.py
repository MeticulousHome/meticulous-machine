"""Regression tests for sync_update_channel_to_image in create_config.sh.

The function reconciles /etc/hawkbit/channel against the channel the running
image was built from, so that an image flashed from a different channel moves
the machine onto that channel. It must do that exactly once per image, and
must not touch a channel the user picked afterwards.
"""

import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
CREATE_CONFIG = REPO_ROOT / "config" / "etc" / "hawkbit" / "create_config.sh"

IMAGE_DATE = "Wed, 05 Aug 2026 22:47:20 +0000"


def extract_function() -> str:
    """Lift sync_update_channel_to_image out of create_config.sh.

    The script reads i2c, mmc and the u-boot partitions at top level, so it
    cannot be sourced on a build host; the function is extracted and run alone.
    """
    lines = CREATE_CONFIG.read_text().splitlines()
    start = next(
        i for i, line in enumerate(lines)
        if line.startswith("sync_update_channel_to_image()")
    )
    end = next(i for i in range(start, len(lines)) if lines[i] == "}")
    return "\n".join(lines[start:end + 1])


def run_sync(tmp_path, *, channel, state, image_channel, build_date=IMAGE_DATE):
    """Run one reconciliation; return the resulting (channel, state file)."""
    channel_file = tmp_path / "channel"
    state_file = tmp_path / "hawkbit-image-id"

    if channel is not None:
        channel_file.write_text(channel + "\n")
    if state is not None:
        state_file.write_text(state)

    script = (
        extract_function()
        + '\nsync_update_channel_to_image "$1" "$2"\n'
    )
    result = subprocess.run(
        ["bash", "-c", script, "bash", image_channel, build_date],
        env={
            "PATH": "/usr/bin:/bin",
            "HAWKBIT_CHANNEL_FILE": str(channel_file),
            "HAWKBIT_IMAGE_STATE_FILE": str(state_file),
        },
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr

    return (
        channel_file.read_text().strip() if channel_file.exists() else None,
        state_file.read_text().strip() if state_file.exists() else None,
    )


def test_records_image_id_when_channel_already_matches(tmp_path):
    """The regression: a machine whose channel already matches its image.

    The image id must still be recorded. Leaving it unwritten makes every
    later run re-detect the same image as new.
    """
    channel, state = run_sync(
        tmp_path, channel="stable", state=None, image_channel="stable"
    )

    assert channel == "stable"
    assert state == f"stable|{IMAGE_DATE}"


def test_user_channel_survives_once_image_is_recorded(tmp_path):
    """A channel the user picks after the image is recorded must be left alone.

    This is the user-visible bug: the first channel change was reverted,
    because changing the channel restarts rauc-hawkbit-updater, which reruns
    this script before the new channel has been reported.
    """
    run_sync(tmp_path, channel="stable", state=None, image_channel="stable")

    # The user switches to beta; the updater restart reruns the reconciliation.
    channel, state = run_sync(
        tmp_path,
        channel="beta",
        state=(tmp_path / "hawkbit-image-id").read_text(),
        image_channel="stable",
    )

    assert channel == "beta"
    assert state == f"stable|{IMAGE_DATE}"


def test_new_image_from_other_channel_moves_the_machine(tmp_path):
    """Preserved intent: a genuinely new image overrides the current channel."""
    channel, state = run_sync(
        tmp_path,
        channel="stable",
        state=f"stable|{IMAGE_DATE}",
        image_channel="beta",
        build_date="Thu, 06 Aug 2026 10:00:00 +0000",
    )

    assert channel == "beta"
    assert state == "beta|Thu, 06 Aug 2026 10:00:00 +0000"


def test_same_image_is_a_no_op(tmp_path):
    """An unchanged image id must not touch the channel at all."""
    channel, state = run_sync(
        tmp_path,
        channel="beta",
        state=f"stable|{IMAGE_DATE}",
        image_channel="stable",
    )

    assert channel == "beta"
    assert state == f"stable|{IMAGE_DATE}"


@pytest.mark.parametrize("image_channel", ["", "UNKNOWN"])
def test_unknown_image_channel_is_ignored(tmp_path, image_channel):
    """An unresolvable build channel must never rewrite anything."""
    channel, state = run_sync(
        tmp_path, channel="beta", state=None, image_channel=image_channel
    )

    assert channel == "beta"
    assert state is None
