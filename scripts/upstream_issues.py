#!/usr/bin/env python3
"""Copies upstream Search's open issues into Lun, once each.

    python3 scripts/upstream_issues.py            copy what isn't here yet
    python3 scripts/upstream_issues.py --dry-run  say what would be copied

Run by hand with `gh` signed in, and every hour by
.github/workflows/upstream-issues.yml. Each copy carries a marker naming
its upstream number, so nothing is copied twice, whatever state the copy
is in now. Numbers in scripts/upstream-issues-skip.txt are never copied:
issues Lun already fixed, or chose not to take.

A copy is quiet upstream: @names are broken so nobody is notified, and
upstream's issues are named in code, not linked, so their pages get no
"mentioned this issue". Bare #numbers in the text are upstream's, not
Lun's, so they are named the same way.
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

UPSTREAM = "driceroland/Search"
REPO = "petterblaasmo/lun"
LABEL = "upstream"
MARKER = re.compile(r"<!-- upstream-issue: driceroland/Search#(\d+) -->")
SKIP = Path(__file__).with_name("upstream-issues-skip.txt")
ZWSP = "&#8203;"


def gh(*args, stdin=None):
    out = subprocess.run(["gh", *args], input=stdin, capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"gh {' '.join(args[:3])}: {out.stderr.strip()}")
    return out.stdout


def skipped():
    if not SKIP.exists():
        return set()
    numbers = set()
    for line in SKIP.read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            numbers.add(int(line))
    return numbers


def copied():
    listed = json.loads(gh("issue", "list", "-R", REPO, "--label", LABEL, "--state", "all",
                           "--limit", "5000", "--json", "body"))
    return {int(m) for issue in listed for m in MARKER.findall(issue["body"] or "")}


def quiet_text(text):
    """Breaks @names and names upstream's issues in code, outside code."""
    text = re.sub(r"https://github\.com/driceroland/Search/(?:issues|pull)/(\d+)\S*",
                  lambda m: f"`{UPSTREAM}#{m.group(1)}`", text)
    text = re.sub(r"(?<![\w`])([\w.-]+/[\w.-]+#\d+)", r"`\1`", text)
    text = re.sub(r"(?<![\w&/`#])#(\d+)\b", lambda m: f"Search #{ZWSP}{m.group(1)}", text)
    return re.sub(r"(?<![\w`])@(?=[A-Za-z0-9])", "@" + ZWSP, text)


def quiet(body):
    """Leaves fenced and inline code as it was written."""
    parts = re.split(r"(```.*?```|`[^`\n]*`)", body, flags=re.S)
    return "".join(p if p.startswith("`") else quiet_text(p) for p in parts)


def copy_body(issue):
    when = issue["createdAt"][:10]
    who = issue["author"]["login"] if issue.get("author") else "someone"
    text = quiet(issue["body"] or "").strip() or "_No description upstream._"
    return (f"<!-- upstream-issue: {UPSTREAM}#{issue['number']} -->\n"
            f"> Copied from `{UPSTREAM}#{issue['number']}`, opened by **{who}** on {when}.\n\n"
            f"{text}\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    upstream = json.loads(gh("issue", "list", "-R", UPSTREAM, "--state", "open", "--limit", "500",
                             "--json", "number,title,body,author,createdAt"))
    have = copied() | skipped()
    new = sorted((i for i in upstream if i["number"] not in have), key=lambda i: i["number"])
    if not new:
        print("nothing new upstream")
        return
    if not args.dry_run:
        gh("label", "create", LABEL, "-R", REPO, "--color", "C5DEF5",
           "--description", f"Copied from {UPSTREAM}", "--force")
    for issue in new:
        if args.dry_run:
            print(f"would copy {UPSTREAM}#{issue['number']}: {issue['title']}")
            continue
        url = gh("issue", "create", "-R", REPO, "--title", issue["title"], "--label", LABEL,
                 "--body-file", "-", stdin=copy_body(issue)).strip()
        print(f"copied {UPSTREAM}#{issue['number']} → {url}")


if __name__ == "__main__":
    main()
