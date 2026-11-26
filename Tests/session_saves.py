#!/usr/bin/env python3
"""The row of tabs saved off the main thread, in the app itself (hidden probe).

Build first (`./build.sh`, or `./build.sh debug`), then
`python3 Tests/session_saves.py`. The row is saved in the background
(Disk, Session.write): a moment after a tab closes, and at once on the way
out. So:

- a tab closed is out of session.json a moment later, without a quit;
- the app killed outright (SIGKILL: nothing on the way out runs) after that
  moment comes back with the tabs that were left, and not the closed one;
- killed in the middle of a run of tabs opening and closing with the row
  saved after each, six times, a different moment in each time,
  session.json is a whole row every time, and the app starts from it;
- quit just after a tab closed, before that moment is up, it comes back
  without that tab.

Nothing is shown on screen.
"""
import json
import os
import random
import signal
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("session-saves")


def saved():
    """session.json as it is this instant: its pages' names, in order."""
    row = json.load(open(f"{sv.SUPPORT}/session.json"))
    assert isinstance(row["tabs"], list) and isinstance(row["active"], int)
    for tab in row["tabs"]:
        assert isinstance(tab["url"], str) and isinstance(tab["title"], str)
    return [tab["url"].rsplit("/", 1)[-1] for tab in row["tabs"] if tab["url"].startswith(sv.BASE)]


def open_tabs():
    return [x["url"].rsplit("/", 1)[-1] for x in sv.sp("state")["tabs"] if x["url"].startswith(sv.BASE)]


def settles(want, within=4):
    """Whether session.json comes to hold `want`: a close is saved a moment
    after it (Browser.rememberSession), not in the same step."""
    end = time.time() + within
    while time.time() < end:
        try:
            if saved() == want:
                return True
        except (OSError, ValueError, AssertionError, KeyError):
            pass
        time.sleep(0.1)
    return False


def kill():
    for pid in sv.pids():
        os.kill(int(pid), signal.SIGKILL)
    for _ in range(50):
        if not sv.pids():
            break
        time.sleep(0.1)
    sv.started.clear()


def main():
    t = sv.T()
    try:
        sv.setup()
        sv.launch()
        ids = {name: sv.page(name) for name in "abcde"}

        sv.sp("close", id=ids["b"])
        t.ok("a tab closed is out of session.json a moment later, without a quit", settles(list("acde")), saved())

        # Killed outright, once another close has been saved.
        sv.sp("close", id=ids["d"])
        settled = settles(list("ace"))
        kill()
        t.ok("killed after a tab closed: the file has the tabs that were left", settled and saved() == list("ace"), saved())
        sv.launch()
        t.ok("and the app comes back with them", open_tabs() == list("ace"), open_tabs())

        # Killed in the middle of a run of saves.
        whole = 0
        for round in range(6):
            stop = threading.Event()
            saves = [0]

            def churn():
                n = 0
                while not stop.is_set():
                    n += 1
                    try:
                        if n % 10 == 1:
                            sv.sp("open", url=f"{sv.BASE}/churn{round}-{n}", foreground=False)
                        # The row saved now, as pinning or moving a tab saves
                        # it: one save after another, as fast as they go.
                        sv.sp("save")
                        saves[0] += 1
                    except Exception:
                        return

            worker = threading.Thread(target=churn, daemon=True)
            worker.start()
            time.sleep(0.5 + random.random() * 1.5)
            kill()
            stop.set()
            worker.join(5)
            try:
                row = saved()
                sv.launch()
                back = open_tabs()
                if back == row and row[:3] == list("ace") and len(row) > 3:
                    whole += 1
                else:
                    print("   round", round, "file", row, "app", back)
                print(f"   round {round}: killed {saves[0]} saves in, {len(row)} tabs in the file")
            except Exception as error:
                print("   round", round, "error", error)
                sv.launch()
        t.ok("killed mid-save six times: a whole row each time, and the app starts from it", whole == 6, whole)

        # Quit just after a tab closed.
        left = open_tabs()
        last = next(x["id"] for x in sv.sp("state")["tabs"] if x["url"].endswith("/" + left[-1]))
        sv.sp("close", id=last)
        sv.quit()
        t.ok("quit just after a tab closed: the file is without it", saved() == left[:-1], (saved(), left))
        sv.launch()
        t.ok("and so is the app when it comes back", open_tabs() == left[:-1], open_tabs())
    except Exception as error:
        t.ok("ran to the end", False, repr(error))
    finally:
        sv.finish()
    t.done()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
