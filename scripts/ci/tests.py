#!/usr/bin/env python3
"""Runs one shard of the unit tests on CI, each test class in a process of its own.

    scripts/ci/tests.py --list tests.txt --shard 1 --of 4

Why one process per class: a class that leaves something behind (a window,
a preference, the app's activation policy, a page still loading) can no
longer fail the classes after it, so a red run means a test failed by itself.
Starting a process costs well under a second.

A class that fails is run once more, alone. A test that passes the second
time is reported as flaky (a warning, not a failure). One that fails twice
fails the run, unless it is listed in Tests/known-failures.txt, which is
reported as a warning with its reason, so the list can only shrink.

The classes are spread over the shards by how long each took last time
(Tests/ci-times.json, written by the Unit tests job from every shard's times)
or, for a class not in it, by how many tests it has.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE = "SearchTests"
# A class that takes longer than this is stopped and counted as failed.
CLASS_LIMIT = 600
# Seconds a test is guessed to take, for a class with no time on record.
GUESS_PER_TEST = 0.4

FAILURE = re.compile(r"^(?P<file>/\S+?\.swift):(?P<line>\d+): error: -\[" + MODULE +
                     r"\.(?P<cls>\w+) (?P<test>\w+)\] : (?P<message>.*)$")
STARTED = re.compile(r"^Test Case '-\[" + MODULE + r"\.(\w+) (\w+)\]' started")
FINISHED = re.compile(r"^Test Case '-\[" + MODULE + r"\.(\w+) (\w+)\]' (passed|failed|skipped)")


def classes(listing: Path) -> dict[str, int]:
    """Each class in the listing with how many tests it has."""
    counts: dict[str, int] = {}
    for line in listing.read_text().splitlines():
        line = line.strip()
        if not line.startswith(MODULE + "."):
            continue
        cls = line[len(MODULE) + 1:].split("/", 1)[0]
        counts[cls] = counts.get(cls, 0) + 1
    return counts


def shards(counts: dict[str, int], times: dict[str, float], of: int) -> list[list[str]]:
    """The classes spread over `of` shards, the longest first, each to the
    shard with the least so far. The same input always gives the same split."""
    weight = {c: times.get(c, n * GUESS_PER_TEST) for c, n in counts.items()}
    order = sorted(weight, key=lambda c: (-weight[c], c))
    load = [0.0] * of
    out: list[list[str]] = [[] for _ in range(of)]
    for c in order:
        i = min(range(of), key=lambda k: (load[k], k))
        out[i].append(c)
        load[i] += weight[c]
    return [sorted(s) for s in out]


def known(path: Path) -> dict[str, str]:
    """Tests known to fail, `Class/test` to the reason given after a #."""
    out: dict[str, str] = {}
    if not path.exists():
        return out
    for line in path.read_text().splitlines():
        if line.lstrip().startswith("#"):
            continue
        name, _, why = line.partition("#")
        name = name.strip()
        if name:
            out[name] = why.strip() or "known to fail"
    return out


def run(cls: str, bundle: Path, log) -> dict:
    """Runs one class alone. What failed, whether it crashed, how long it took."""
    started = time.monotonic()
    proc = subprocess.Popen(["xcrun", "xctest", "-XCTest", f"{MODULE}.{cls}", str(bundle)],
                            cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                            errors="replace")
    failures: list[dict] = []
    running = None
    finished = 0
    lines: list[str] = []
    # A test that hangs prints nothing: a timer stops it, not the next line.
    stopped = threading.Event()
    def stop():
        stopped.set()
        proc.kill()
    timer = threading.Timer(CLASS_LIMIT, stop)
    timer.start()
    assert proc.stdout
    for line in proc.stdout:
        log.write(line)
        lines.append(line)
        line = line.rstrip("\n")
        if (m := FAILURE.match(line)):
            failures.append(m.groupdict())
        elif (m := STARTED.match(line)):
            running = m.group(2)
        elif FINISHED.match(line):
            running = None
            finished += 1
    proc.wait()
    timer.cancel()
    timed_out = stopped.is_set()
    took = time.monotonic() - started
    # A process that ended badly with no failure said: it crashed, or was
    # stopped, in the test that was running.
    crashed = (proc.returncode != 0 and not failures) or timed_out
    if crashed:
        what = f"timed out after {CLASS_LIMIT} s" if timed_out else f"the test process ended with code {proc.returncode}"
        failures.append({"file": "", "line": "0", "cls": cls, "test": running or "(before its first test)",
                         "message": what, "tail": "".join(lines[-30:])})
    return {"failures": failures, "crashed": crashed, "took": took, "finished": finished}


def unique(failures: list[dict]) -> list[dict]:
    """One line per test, the first of its failures, with how many it had."""
    out: dict[tuple, dict] = {}
    for f in failures:
        key = (f["cls"], f["test"])
        if key in out:
            out[key]["count"] += 1
        else:
            out[key] = {**f, "count": 1}
    for f in out.values():
        if f["count"] > 1:
            f["message"] += f" (and {f['count'] - 1} more failures in this test)"
    return list(out.values())


def annotate(kind: str, title: str, f: dict, text: str) -> None:
    where = ""
    if f.get("file"):
        path = os.path.relpath(f["file"], ROOT) if f["file"].startswith(str(ROOT)) else f["file"]
        where = f" file={path},line={f['line']}"
    text = text.replace("%", "%25").replace("\r", "").replace("\n", "%0A")
    print(f"::{kind}{where},title={title}::{text}", flush=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", type=Path, required=True, help="the output of `swift test list`")
    ap.add_argument("--shard", type=int, default=1)
    ap.add_argument("--of", type=int, default=1)
    ap.add_argument("--bundle", type=Path, default=ROOT / ".build/debug/SearchTests.xctest")
    ap.add_argument("--times", type=Path, default=ROOT / "Tests/ci-times.json")
    ap.add_argument("--known", type=Path, default=ROOT / "Tests/known-failures.txt")
    ap.add_argument("--out", type=Path, default=ROOT / "ci-out")
    ap.add_argument("--only", help="run just these classes, comma-separated (to try it locally)")
    args = ap.parse_args()

    counts = classes(args.list)
    times = json.loads(args.times.read_text()) if args.times.exists() else {}
    if args.only:
        mine = args.only.split(",")
    else:
        mine = shards(counts, times, args.of)[args.shard - 1]
    expected = known(args.known)
    args.out.mkdir(parents=True, exist_ok=True)

    print(f"Shard {args.shard} of {args.of}: {len(mine)} classes, {sum(counts.get(c, 0) for c in mine)} tests", flush=True)
    took: dict[str, float] = {}
    real: list[dict] = []
    flaky: list[dict] = []
    expected_seen: list[dict] = []
    with open(args.out / f"shard-{args.shard}.log", "w") as log:
        for cls in mine:
            print(f"::group::{cls}", flush=True)
            first = run(cls, args.bundle, log)
            took[cls] = round(first["took"], 1)
            outcome = "passed"
            if first["failures"]:
                again = run(cls, args.bundle, log)
                failed_again = {(f["cls"], f["test"]) for f in again["failures"]}
                for f in first["failures"]:
                    key = f"{f['cls']}/{f['test']}"
                    if (f["cls"], f["test"]) not in failed_again:
                        flaky.append(f)
                    elif key in expected or f"{f['cls']}" in expected:
                        expected_seen.append({**f, "why": expected.get(key) or expected.get(f["cls"])})
                    else:
                        real.append(f)
                # Failed only the second time: as real as the first.
                firsts = {(f["cls"], f["test"]) for f in first["failures"]}
                for f in again["failures"]:
                    if (f["cls"], f["test"]) not in firsts:
                        flaky.append(f)
                outcome = "failed" if any(f["cls"] == cls for f in real) else "flaky or known"
            print(f"{cls}: {outcome} in {first['took']:.1f} s", flush=True)
            print("::endgroup::", flush=True)

    real, flaky, expected_seen = unique(real), unique(flaky), unique(expected_seen)
    for f in real:
        annotate("error", f"{f['cls']}.{f['test']}", f, f["message"] + ("\n" + f["tail"] if f.get("tail") else ""))
    for f in flaky:
        annotate("warning", f"Flaky: {f['cls']}.{f['test']}", f,
                 "Failed, then passed when its class ran again: " + f["message"])
    for f in expected_seen:
        annotate("warning", f"Known failure: {f['cls']}.{f['test']}", f, f"{f['why']} (Tests/known-failures.txt)")
    seen_expected = {f"{f['cls']}/{f['test']}" for f in expected_seen} | {f["cls"] for f in expected_seen}
    passing_now = [k for k in expected if k.split("/")[0] in mine and k not in seen_expected]

    (args.out / f"times-{args.shard}.json").write_text(json.dumps(took, indent=1, sort_keys=True))
    result = {"shard": args.shard, "classes": len(mine), "real": real, "flaky": flaky,
              "known": expected_seen, "known_passing": passing_now,
              "seconds": round(sum(took.values()), 1)}
    (args.out / f"result-{args.shard}.json").write_text(json.dumps(result, indent=1))

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as s:
            s.write(f"### Shard {args.shard} of {args.of}\n\n")
            s.write(f"{len(mine)} classes in {result['seconds']} s: "
                    f"{len(real)} failed, {len(flaky)} flaky, {len(expected_seen)} known.\n\n")
            if real or flaky or expected_seen:
                s.write("| Test | | Message |\n|---|---|---|\n")
                for kind, group in (("failed", real), ("flaky", flaky), ("known", expected_seen)):
                    for f in group:
                        message = f["message"].replace("|", "\\|")[:200]
                        s.write(f"| `{f['cls']}.{f['test']}` | {kind} | {message} |\n")
                s.write("\n")
            if passing_now:
                s.write("Listed as known failures but passed: " + ", ".join(f"`{k}`" for k in passing_now) +
                        ". Take them off Tests/known-failures.txt.\n\n")
    print(f"Shard {args.shard}: {len(real)} failed, {len(flaky)} flaky, {len(expected_seen)} known, "
          f"{result['seconds']} s", flush=True)
    return 1 if real else 0


if __name__ == "__main__":
    sys.exit(main())
