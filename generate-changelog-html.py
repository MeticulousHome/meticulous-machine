#!/usr/bin/env python3
"""
generate-changelog-html.py

Reads all images/changes/<channel>/<timestamp>.changelog.yaml files and
produces a self-contained static HTML page showing the build changelog
for each channel, sorted newest-first.

Usage:
    python3 generate-changelog-html.py <changes_dir> <output_html>

Example:
    python3 generate-changelog-html.py images/changes/ _site/index.html
"""

import os
import sys
from pathlib import Path


def parse_changelog_yaml(filepath):
    """
    Minimal YAML parser for our well-known changelog format.
    Avoids requiring PyYAML as a dependency.

    Returns a dict with keys: channel, timestamp, versions, changes
    """
    result = {
        "channel": "",
        "timestamp": "",
        "versions": {},
        "changes": {},
    }

    current_section = None  # "versions" or "changes"
    current_component = None
    current_field = None  # for tracking multi-line fields in changes

    with open(filepath, "r") as f:
        for raw_line in f:
            line = raw_line.rstrip("\n")

            # Skip comments and empty lines
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue

            # Top-level keys (no indentation)
            if not line.startswith(" ") and not line.startswith("\t"):
                if line.startswith("channel:"):
                    result["channel"] = _extract_value(line)
                    current_section = None
                    current_component = None
                elif line.startswith("timestamp:"):
                    result["timestamp"] = _extract_value(line)
                    current_section = None
                    current_component = None
                elif line.startswith("versions:"):
                    current_section = "versions"
                    current_component = None
                elif line.startswith("changes:"):
                    current_section = "changes"
                    current_component = None
                continue

            # Indented content
            indent = len(line) - len(line.lstrip())

            if current_section == "versions" and indent == 2:
                # "  linux: "f7e1dec...""
                key, val = _parse_kv(stripped)
                if key and val:
                    result["versions"][key] = val

            elif current_section == "changes":
                if indent == 2 and ":" in stripped:
                    # "  backend:" - component name
                    comp_name = stripped.rstrip(":").strip()
                    if comp_name and comp_name != "{}":
                        current_component = comp_name
                        result["changes"][current_component] = {
                            "old_rev": None,
                            "new_rev": None,
                            "commits": [],
                        }
                    current_field = None

                elif indent == 4 and current_component:
                    key, val = _parse_kv(stripped)
                    if key == "old_rev":
                        result["changes"][current_component]["old_rev"] = (
                            val if val != "null" else None
                        )
                    elif key == "new_rev":
                        result["changes"][current_component]["new_rev"] = val
                    elif key == "commits:":
                        current_field = "commits"
                    elif key == "commits":
                        # "commits: []" or similar
                        current_field = None

                elif indent == 6 and current_component and stripped.startswith("- hash:"):
                    # "      - hash: "abc123""
                    _, val = _parse_kv(stripped.lstrip("- "))
                    result["changes"][current_component]["commits"].append(
                        {"hash": val or "", "message": ""}
                    )

                elif indent == 8 and current_component and stripped.startswith("message:"):
                    _, val = _parse_kv(stripped)
                    if (
                        result["changes"][current_component]["commits"]
                        and val is not None
                    ):
                        result["changes"][current_component]["commits"][-1][
                            "message"
                        ] = val

    return result


def _extract_value(line):
    """Extract value from 'key: value' or 'key: "value"'."""
    _, _, val = line.partition(":")
    val = val.strip().strip('"').strip("'")
    return val


def _parse_kv(s):
    """Parse 'key: value' returning (key, value). Value is unquoted."""
    if ":" not in s:
        return s.rstrip(":"), None
    key, _, val = s.partition(":")
    key = key.strip().lstrip("- ")
    val = val.strip().strip('"').strip("'")
    return key, val if val else None


def generate_html(changes_dir, output_path):
    changes_root = Path(changes_dir)

    if not changes_root.exists():
        print(f"Changes directory {changes_dir} does not exist, generating empty page.")
        channels = {}
    else:
        # Discover channels and their changelog files
        channels = {}
        for channel_dir in sorted(changes_root.iterdir()):
            if not channel_dir.is_dir():
                continue
            channel_name = channel_dir.name
            files = sorted(channel_dir.glob("*.changelog.yaml"), reverse=True)
            if files:
                channels[channel_name] = files

    # Parse all changelogs
    channel_data = {}
    for channel_name, files in channels.items():
        entries = []
        for f in files:
            try:
                entry = parse_changelog_yaml(f)
                entries.append(entry)
            except Exception as e:
                print(f"Warning: Failed to parse {f}: {e}")
        channel_data[channel_name] = entries

    # Determine display order: stable first, beta second, then alphabetical
    priority = {"stable": 0, "beta": 1}
    sorted_channels = sorted(
        channel_data.keys(), key=lambda c: (priority.get(c, 99), c)
    )

    # Build HTML
    html_parts = []
    html_parts.append(
        """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Meticulous Image Build Changelog</title>
<style>
  :root {
    --bg: #0d1117;
    --surface: #161b22;
    --border: #30363d;
    --text: #e6edf3;
    --text-muted: #8b949e;
    --accent: #58a6ff;
    --green: #3fb950;
    --red: #f85149;
    --orange: #d29922;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
    background: var(--bg);
    color: var(--text);
    line-height: 1.6;
    padding: 2rem;
    max-width: 960px;
    margin: 0 auto;
  }
  h1 {
    font-size: 1.8rem;
    margin-bottom: 1.5rem;
    border-bottom: 1px solid var(--border);
    padding-bottom: 0.5rem;
  }
  .tabs {
    display: flex;
    gap: 0.5rem;
    margin-bottom: 1.5rem;
    border-bottom: 1px solid var(--border);
    padding-bottom: 0;
  }
  .tab {
    padding: 0.5rem 1rem;
    cursor: pointer;
    border: 1px solid transparent;
    border-bottom: none;
    border-radius: 6px 6px 0 0;
    background: transparent;
    color: var(--text-muted);
    font-size: 0.95rem;
    transition: all 0.15s;
  }
  .tab:hover { color: var(--text); }
  .tab.active {
    background: var(--surface);
    color: var(--text);
    border-color: var(--border);
    font-weight: 600;
  }
  .channel-content { display: none; }
  .channel-content.active { display: block; }
  .build-entry {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 6px;
    margin-bottom: 1rem;
    padding: 1rem 1.25rem;
  }
  .build-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 0.75rem;
  }
  .build-timestamp {
    font-size: 0.9rem;
    color: var(--text-muted);
    font-family: monospace;
  }
  .component-section { margin-bottom: 0.75rem; }
  .component-name {
    font-weight: 600;
    color: var(--accent);
    font-size: 0.95rem;
    margin-bottom: 0.25rem;
  }
  .rev-info {
    font-size: 0.8rem;
    color: var(--text-muted);
    font-family: monospace;
    margin-bottom: 0.25rem;
  }
  .commit-list {
    list-style: none;
    padding-left: 1rem;
  }
  .commit-list li {
    font-size: 0.85rem;
    padding: 0.15rem 0;
    color: var(--text);
  }
  .commit-hash {
    font-family: monospace;
    color: var(--green);
    font-size: 0.8rem;
    margin-right: 0.5rem;
  }
  .no-changes {
    color: var(--text-muted);
    font-style: italic;
  }
  .badge {
    display: inline-block;
    font-size: 0.75rem;
    padding: 0.1rem 0.5rem;
    border-radius: 10px;
    font-weight: 600;
  }
  .badge-initial {
    background: rgba(56, 139, 253, 0.15);
    color: var(--accent);
  }
  .badge-updated {
    background: rgba(63, 185, 80, 0.15);
    color: var(--green);
  }
  .empty-state {
    text-align: center;
    padding: 3rem;
    color: var(--text-muted);
  }
</style>
</head>
<body>
<h1>Meticulous Image Build Changelog</h1>
"""
    )

    if not sorted_channels:
        html_parts.append('<div class="empty-state">No changelogs available yet.</div>')
    else:
        # Tabs
        html_parts.append('<div class="tabs">')
        for i, ch in enumerate(sorted_channels):
            active = " active" if i == 0 else ""
            html_parts.append(
                f'<div class="tab{active}" onclick="switchTab(\'{ch}\')">{ch}</div>'
            )
        html_parts.append("</div>")

        # Channel content
        for i, ch in enumerate(sorted_channels):
            active = " active" if i == 0 else ""
            html_parts.append(f'<div class="channel-content{active}" id="channel-{ch}">')

            entries = channel_data[ch]
            if not entries:
                html_parts.append(
                    '<div class="empty-state">No builds recorded for this channel.</div>'
                )
            else:
                for entry in entries:
                    html_parts.append('<div class="build-entry">')
                    html_parts.append('<div class="build-header">')
                    ts = entry.get("timestamp", "unknown")
                    display_ts = ts.replace("T", " ").replace("-", ":", 2) if "T" in ts else ts
                    # Only replace the time-separator dashes, not the date ones
                    # Format: 2026-02-26T00-00-00 -> 2026-02-26 00:00:00
                    if "T" in ts:
                        date_part, _, time_part = ts.partition("T")
                        display_ts = f"{date_part} {time_part.replace('-', ':')}"
                    html_parts.append(f'<span class="build-timestamp">{_html_escape(display_ts)}</span>')
                    html_parts.append("</div>")

                    changes = entry.get("changes", {})
                    if not changes:
                        html_parts.append('<div class="no-changes">No component changes in this build.</div>')
                    else:
                        for comp_name, comp_data in changes.items():
                            html_parts.append('<div class="component-section">')
                            old = comp_data.get("old_rev")
                            is_initial = old is None
                            badge_class = "badge-initial" if is_initial else "badge-updated"
                            badge_text = "initial" if is_initial else "updated"
                            html_parts.append(
                                f'<div class="component-name">{_html_escape(comp_name)} '
                                f'<span class="badge {badge_class}">{badge_text}</span></div>'
                            )

                            new_rev = comp_data.get("new_rev", "")
                            if is_initial:
                                html_parts.append(
                                    f'<div class="rev-info">pinned to {_html_escape(new_rev[:12])}</div>'
                                )
                            else:
                                html_parts.append(
                                    f'<div class="rev-info">'
                                    f'{_html_escape(old[:12] if old else "?")} &rarr; {_html_escape(new_rev[:12])}'
                                    f"</div>"
                                )

                            commits = comp_data.get("commits", [])
                            if commits:
                                html_parts.append('<ul class="commit-list">')
                                for c in commits:
                                    h = _html_escape(c.get("hash", ""))
                                    m = _html_escape(c.get("message", ""))
                                    html_parts.append(
                                        f'<li><span class="commit-hash">{h}</span>{m}</li>'
                                    )
                                html_parts.append("</ul>")

                            html_parts.append("</div>")

                    html_parts.append("</div>")

            html_parts.append("</div>")

    html_parts.append(
        """
<script>
function switchTab(channel) {
  document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
  document.querySelectorAll('.channel-content').forEach(c => c.classList.remove('active'));
  event.target.classList.add('active');
  document.getElementById('channel-' + channel).classList.add('active');
}
</script>
</body>
</html>"""
    )

    # Write output
    output = Path(output_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(html_parts))
    print(f"Changelog HTML written to {output_path}")


def _html_escape(s):
    """Basic HTML escaping."""
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <changes_dir> <output_html>")
        sys.exit(1)

    generate_html(sys.argv[1], sys.argv[2])
