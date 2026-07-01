#!/bin/sh
set -eu

if [ "${1:-}" = "--output" ]; then
  if [ "$#" -ne 2 ]; then
    echo "usage: $0 [--output path]" >&2
    exit 2
  fi
  output_path="$2"
  tmp_path="$(mktemp "${output_path}.XXXXXX")"
  trap 'rm -f "$tmp_path"' EXIT
  "$0" > "$tmp_path"
  mv "$tmp_path" "$output_path"
  trap - EXIT
  exit 0
fi

python3 - <<'PY'
from datetime import datetime, timezone
import json
import os
import sys
import time
import urllib.parse
import urllib.error
import urllib.request

repo = "TelegramMessenger/Telegram-iOS"
queries = [
    ("recent bugs", f"repo:{repo} is:issue is:open label:bug updated:>=2025-01-01"),
    ("crashes", f"repo:{repo} is:issue is:open crash in:title,body"),
    ("freezes and performance", f"repo:{repo} is:issue is:open freeze OR performance OR memory in:title,body"),
    ("chat opening and scrolling", f"repo:{repo} is:issue is:open \"opening chats\" OR \"scrolling bug\" OR \"switching active chats\" OR \"Saved Messages\" in:title,body"),
    ("media", f"repo:{repo} is:issue is:open gif OR sticker OR video OR media in:title,body"),
    ("notifications", f"repo:{repo} is:issue is:open notification OR watch in:title,body"),
]

headers = {
    "Accept": "application/vnd.github+json",
    "User-Agent": "custom-telegram-ios-audit",
}
token = os.environ.get("GITHUB_TOKEN")
if token:
    headers["Authorization"] = f"Bearer {token}"

def fetch_json(request):
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            if error.code == 403 and attempt < 2:
                reset = error.headers.get("X-RateLimit-Reset")
                if reset:
                    delay = max(1, min(90, int(reset) - int(time.time()) + 2))
                    print(f"GitHub search rate limit reached; sleeping {delay}s", file=sys.stderr)
                    time.sleep(delay)
                    continue
            raise

print("# GitHub Bug Snapshot")
print()
print(f"Repository: `{repo}`")
print(f"Generated: `{datetime.now(timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')}`")
print()

seen = set()
for title, query in queries:
    params = urllib.parse.urlencode({
        "q": query,
        "sort": "updated",
        "order": "desc",
        "per_page": "25",
    })
    request = urllib.request.Request(
        f"https://api.github.com/search/issues?{params}",
        headers=headers,
    )
    payload = fetch_json(request)

    print(f"## {title.title()}")
    print()
    print(f"Total matches: {payload.get('total_count', 0)}")
    print()

    for item in payload.get("items", []):
        number = item["number"]
        if number in seen:
            continue
        seen.add(number)
        labels = ", ".join(label["name"] for label in item.get("labels", [])) or "-"
        item_title = " ".join(item["title"].split())
        print(f"- [#{number} {item_title}]({item['html_url']})")
        print(f"  updated: {item['updated_at']} | labels: {labels}")
    print()
PY
