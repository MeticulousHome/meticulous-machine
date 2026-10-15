#!/usr/bin/env python3
"""Does the built image boot, and is it what the build says it is?

Phase 1 of the image validation (docs/testing/validation-architecture.md). Runs
against the container e2e/image/boot.sh started: the image's own systemd on an
ARM64 computer, no network, an empty /meticulous-user, the backend on its
built-in ESP32 emulator. Each check prints one line and goes into a Markdown
table (--summary); the exit status is 1 when one fails.

Usage: sudo e2e/image/check_image.py --rootfs DIR --image CHANNEL
           [--versions images/<channel>.versions.sh] [--bundle emmc-bundle.raucb]
           [--summary FILE] [--report FILE]
"""

import argparse
import json
import re
import shutil
import subprocess
import time
import urllib.request
from pathlib import Path

MACHINE = "image"
HERE = Path(__file__).resolve().parent

# The services a machine needs to work that need no hardware of their own.
SERVICES = ("meticulous-backend", "meticulous-watcher", "nginx")


def leader() -> str:
    return subprocess.run(
        ["machinectl", "show", MACHINE, "-p", "Leader", "--value"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()


def inside(*command: str, timeout: float = 60) -> subprocess.CompletedProcess:
    """Run a command in the image, as root, with the image's own files."""
    return subprocess.run(
        ["nsenter", "--target", leader(), "--all", "--", *command],
        capture_output=True, text=True, timeout=timeout,
    )


def get(url: str, timeout: float = 5) -> tuple[int, str]:
    """An HTTP GET from inside the image's network (it has no other)."""
    script = (
        "import sys, urllib.request, urllib.error\n"
        "try:\n"
        f"    r = urllib.request.urlopen({url!r}, timeout={timeout})\n"
        "    print(r.status); print(r.read().decode(errors='replace'))\n"
        "except urllib.error.HTTPError as e:\n"
        "    print(e.code); print(e.read().decode(errors='replace'))\n"
    )
    done = inside("/usr/bin/python3", "-c", script, timeout=timeout + 10)
    if done.returncode != 0:
        return 0, done.stderr.strip().splitlines()[-1] if done.stderr.strip() else "no answer"
    status, _, body = done.stdout.partition("\n")
    return int(status), body


def until(predicate, timeout_s: float, every_s: float = 2):
    """Poll `predicate` until it returns something truthy; its last answer."""
    deadline = time.monotonic() + timeout_s
    while True:
        answer = predicate()
        if answer or time.monotonic() > deadline:
            return answer
        time.sleep(every_s)


def machine_only_units() -> dict[str, str]:
    """Units that fail here only because the machine's hardware or network is missing."""
    units = {}
    for line in (HERE / "machine-only-units.txt").read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            unit, _, reason = line.partition(" ")
            units[unit] = reason.strip()
    return units


# ---- the checks -----------------------------------------------------------------
# Each returns (ok, what it saw). ok is None for what is only reported.


def check_boots(args):
    done = inside("systemctl", "is-system-running", "--wait", timeout=600)
    state = done.stdout.strip()
    return state in ("running", "degraded"), f"systemd reached `{state}`"


def check_failed_units(args):
    done = inside("systemctl", "list-units", "--state=failed", "--plain", "--no-legend", "--no-pager")
    failed = sorted(line.split()[0] for line in done.stdout.splitlines() if line.strip())
    allowed = machine_only_units()
    unexpected = [u for u in failed if not any(re.fullmatch(pattern, u) for pattern in allowed)]
    expected = [u for u in failed if u not in unexpected]
    seen = f"unexpected: {', '.join(unexpected) or 'none'}; need the machine: {', '.join(expected) or 'none'}"
    return not unexpected, seen


def check_services(args):
    def states():
        answer = {s: inside("systemctl", "is-active", s).stdout.strip() for s in SERVICES}
        return answer if all(v == "active" for v in answer.values()) else None

    answer = until(states, 120) or {s: inside("systemctl", "is-active", s).stdout.strip() for s in SERVICES}
    return all(v == "active" for v in answer.values()), ", ".join(f"{s} {v}" for s, v in answer.items())


def check_backend_api(args):
    def settings():
        status, body = get("http://127.0.0.1:8080/api/v1/settings")
        return (status, body) if status == 200 else None

    answer = until(settings, 180, 3)
    if not answer:
        status, body = get("http://127.0.0.1:8080/api/v1/settings")
        return False, f"/api/v1/settings answered {status}: {body[:200]}"
    status, body = get("http://127.0.0.1:8080/api/v1/smoke-validation")
    smoke = json.loads(body) if status == 200 else {}
    ok = smoke.get("backend_initialized") is True
    return ok, f"settings 200; smoke-validation {status}: backend_initialized={smoke.get('backend_initialized')}"


def check_nginx_routes(args):
    # / is the web app, /api the backend, /health the watcher.
    routes = {path: get(f"http://127.0.0.1{path}")[0] for path in ("/", "/api/v1/settings", "/health/status")}
    ok = all(status == 200 for status in routes.values())
    return ok, ", ".join(f"{p} {s}" for p, s in routes.items())


def check_identity(args):
    channel = (args.rootfs / "opt/image-build-channel").read_text().strip()
    version = (args.rootfs / "opt/image-build-version").read_text().strip()
    ok = channel == args.image and version.endswith(f"-{args.image}")
    return ok, f"/opt/image-build-channel `{channel}`, /opt/image-build-version `{version}`"


def summary_components(rootfs: Path) -> dict[str, dict[str, str]]:
    """What /opt/summary.txt says each component was built from."""
    components, name = {}, None
    for line in (rootfs / "opt/summary.txt").read_text(errors="replace").splitlines():
        if m := re.fullmatch(r"## (.+) ##", line.strip()):
            name = m.group(1)
            components[name] = {}
        elif name and (m := re.match(r"(Branch|Commit): (\S+)", line)):
            components[name].setdefault(m.group(1).lower(), m.group(2))
    return components


def pinned(versions: Path) -> dict[str, dict[str, str]]:
    """What images/<channel>.versions.sh asks for: {component: {branch, rev}}."""
    pins = {}
    for m in re.finditer(r'^export (\w+?)_(BRANCH|REV)="([^"]*)"', versions.read_text(), re.M):
        pins.setdefault(m.group(1).lower().replace("_", "-"), {})[m.group(2).lower()] = m.group(3)
    return pins


def check_versions(args):
    if not args.versions:
        return None, "no versions.sh given"
    built = summary_components(args.rootfs)
    problems = []
    for component, pin in pinned(args.versions).items():
        got = built.get(component)
        if got is None:
            problems.append(f"{component}: not in /opt/summary.txt")
            continue
        if "branch" in pin and got.get("branch") != pin["branch"]:
            problems.append(f"{component}: branch `{got.get('branch')}`, pinned `{pin['branch']}`")
        rev = pin.get("rev", "HEAD")
        if rev != "HEAD" and not (got.get("commit") or "").startswith(rev):
            problems.append(f"{component}: commit `{(got.get('commit') or '')[:12]}`, pinned `{rev[:12]}`")
    empty = sorted(c for c, info in built.items() if not info)
    seen = "; ".join(problems) or f"{len(built)} components as pinned"
    if empty:
        seen += f" (no branch or commit recorded: {', '.join(empty)})"
    return not problems, seen


def check_firmware(args):
    folder = args.rootfs / "opt/meticulous-firmware/esp32-s3"
    missing = [f for f in ("bootloader.bin", "partitions.bin", "boot_app0.bin", "firmware.bin") if not (folder / f).is_file()]
    if missing:
        return False, f"missing in /opt/meticulous-firmware/esp32-s3: {', '.join(missing)}"
    found = re.search(rb"\d+\.\d+\.\d+-\d+-g([0-9a-f]{7,})", (folder / "firmware.bin").read_bytes())
    commit = summary_components(args.rootfs).get("firmware", {}).get("commit", "")
    if not found:
        return False, "firmware.bin carries no version string"
    version = found.group(0).decode()
    return commit.startswith(found.group(1).decode()), f"firmware.bin `{version}`, built from `{commit[:12]}`"


def check_update_channel(args):
    # ota.py: a machine that boots an image it has not run before (a new one,
    # or one just updated) follows that image's channel.
    expected = args.image

    def channel():
        done = inside("cat", "/etc/hawkbit/channel")
        return done.stdout.strip() if done.stdout.strip() == expected else None

    got = until(channel, 60) or inside("cat", "/etc/hawkbit/channel").stdout.strip()
    return got == expected, f"/etc/hawkbit/channel `{got}` on a new machine (expected `{expected}`)"


def check_rauc_bundle(args):
    if not args.bundle:
        return None, "no bundle given"
    shutil.copy(args.bundle, args.rootfs / "run/validation-bundle.raucb")
    conf = (args.rootfs / "etc/rauc/system.conf").read_text()
    compatible = re.search(r"^compatible=(.+)$", conf, re.M).group(1).strip()
    keyring = re.search(r"^path=(.+)$", conf.split("[keyring]", 1)[1], re.M).group(1).strip()
    done = inside("rauc", "info", "--output-format=json", "/run/validation-bundle.raucb", timeout=180)
    if done.returncode != 0:
        return False, f"the image's rauc refuses this build's bundle: {done.stderr.strip()[-300:]}"
    info = json.loads(done.stdout)
    ok = info.get("compatible") == compatible
    return ok, f"signature verified with `{keyring}`; bundle compatible `{info.get('compatible')}`, image `{compatible}`"


def check_dial(args):
    binary = args.rootfs / "usr/bin/meticulous-dial"
    if not binary.is_file():
        return False, "/usr/bin/meticulous-dial missing"
    head = binary.read_bytes()[:20]
    arm64 = head[:4] == b"\x7fELF" and head[18:20] == b"\xb7\x00"
    state = inside("systemctl", "is-active", "meticulous-dial").stdout.strip()
    return arm64, f"ARM64 binary installed: {arm64}; service `{state}` (it needs Weston, which needs a display)"


CHECKS = [
    ("The image boots", check_boots),
    ("No service fails, except what needs the machine", check_failed_units),
    ("Backend, watcher and nginx are running", check_services),
    ("The backend answers", check_backend_api),
    ("nginx routes the web app, the API and /health", check_nginx_routes),
    ("The image is the channel it was built for", check_identity),
    ("Every component as images/<channel>.versions.sh pins it", check_versions),
    ("It carries the firmware it was built with", check_firmware),
    ("A new machine follows its image's update channel", check_update_channel),
    ("Its RAUC accepts this build's update bundle", check_rauc_bundle),
    ("The Dial is installed", check_dial),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--rootfs", type=Path, required=True)
    parser.add_argument("--image", required=True, help="the channel the image was built for")
    parser.add_argument("--versions", type=Path)
    parser.add_argument("--bundle", type=Path)
    parser.add_argument("--summary", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()

    results = []
    for title, check in CHECKS:
        try:
            ok, seen = check(args)
        except Exception as error:  # a check that cannot run is a failure, said plainly
            ok, seen = False, f"{type(error).__name__}: {error}"
        mark = {True: "ok", False: "FAIL", None: "--"}[ok]
        print(f"[{mark}] {title}: {seen}", flush=True)
        results.append({"check": title, "ok": ok, "seen": seen})

    failed = [r for r in results if r["ok"] is False]
    if args.summary:
        icon = {True: "✅", False: "❌", None: "➖"}
        lines = [
            f"## The `{args.image}` image boots and is what the build says",
            "",
            "Informative for now: it does not block the upload to hawkBit.",
            "",
            "| | Check | What it saw |",
            "|---|---|---|",
            *(f"| {icon[r['ok']]} | {r['check']} | {r['seen'].replace('|', '/')} |" for r in results),
        ]
        with args.summary.open("a") as summary:
            summary.write("\n".join(lines) + "\n")
    if args.report:
        args.report.write_text(json.dumps(results, indent=1))
    raise SystemExit(1 if failed else 0)


if __name__ == "__main__":
    main()
