#!/usr/bin/env python3
# SPDX-License-Identifier: 0BSD
"""Publish the hub's public feeds (news.json / issues.json) to Forge storage.

The game never needs the secret key: it reads the published files from
https://forge.boqsc.eu/~/<project>/news.json. Only this tool does.

Usage:
  set FORGE_KEY=fsk_...
  python addons/hub/publish/publish_feeds.py newsletter --title "..." --body "..."
  python addons/hub/publish/publish_feeds.py issue --title "..." --body "..." --kind bug
  python addons/hub/publish/publish_feeds.py version --set 1.0.0-dev
  python addons/hub/publish/publish_feeds.py show

The script downloads the current feed (if any), merges the new entry, then
uploads the result. It never prints the key.
"""
import json
import os
import sys
import urllib.request

BASE = "https://forge.boqsc.eu"
PROJECT = "fg_7d1ddfd4506e8593"
FEED_LIMIT = 50


def key():
    value = os.environ.get("FORGE_KEY", "").strip()
    if not value.startswith("fsk_"):
        sys.exit("FORGE_KEY must be set to a Forge key (fsk_...).")
    return value


def fetch(name):
    url = f"{BASE}/~/{PROJECT}/{name}"
    try:
        with urllib.request.urlopen(url, timeout=20) as response:
            parsed = json.loads(response.read().decode("utf-8"))
    except Exception as error:  # noqa: BLE001 - any failure means "no feed yet"
        print(f"{name}: no published copy ({error})")
        return {"items": []}
    if isinstance(parsed, list):
        return {"items": parsed}
    if not isinstance(parsed.get("items"), list):
        return {"items": []}
    return parsed


def upload(name, payload):
    url = f"{BASE}/api/files?path={name}"
    body = json.dumps(payload, indent=1).encode("utf-8")
    request = urllib.request.Request(url, data=body, method="POST", headers={
        "Authorization": "Bearer " + key(),
        "Content-Type": "application/json",
    })
    with urllib.request.urlopen(request, timeout=30) as response:
        print(f"{name}: {response.read().decode('utf-8')}")


def add(feed, entry):
    payload = fetch(feed)
    payload["items"].insert(0, entry)
    payload["items"] = payload["items"][:FEED_LIMIT]
    upload(feed, payload)


def main(argv):
    if not argv or argv[0] == "show":
        for name in ("news.json", "issues.json"):
            data = fetch(name)
            print(f"{name}: {len(data['items'])} item(s)")
            for item in data["items"][:5]:
                print("  -", item.get("title", "?"))
        return 0
    command = argv[0]
    options = {}
    rest = argv[1:]
    for index in range(0, len(rest) - 1, 2):
        options[rest[index].lstrip("-")] = rest[index + 1]
    stamp = __import__("datetime").datetime.utcnow().strftime("%Y-%m-%d")
    if command == "newsletter":
        add("news.json", {"title": options.get("title", "Update"), "body": options.get("body", ""), "date": stamp})
    elif command == "version":
        version = options.get("set", "")
        add("news.json", {"title": "Latest version " + version, "body": "Announced by the publisher.", "date": stamp, "latest_version": version})
    elif command == "issue":
        add("issues.json", {"title": options.get("title", "Issue"), "body": options.get("body", ""), "kind": options.get("kind", "bug"), "status": options.get("status", "open"), "date": stamp})
    elif command == "clear":
        upload("news.json" if options.get("feed", "news") == "news" else "issues.json", {"items": []})
    else:
        sys.exit(__doc__)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
