#!/usr/bin/env python3
"""Back, forward and the address down from the top edge, with the column
folded away, in a hidden probe.

Build first (`./build.sh`), then `python3 Tests/edge_bar.py`. Uses the split
suite's harness: hidden, nothing shown, everything removed afterwards.
EDGE_BAR_PICTURES=<folder> also keeps pictures of the window, light and dark.

The card's own watch tells it where the pointer is; here the bench tells it
the same (`edgebar`), so what is checked is the card's say: it may come only
with the column folded away, it comes once the pointer has rested on the
middle of the top edge, stays while the pointer is on it, goes after it has
left, and its buttons are the column's own. Not seen here: a real pointer
at the edge of a window on a screen.
"""
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("edge-bar")
PICTURES = os.environ.get("EDGE_BAR_PICTURES")
t = sv.T()


def ui(**f): return sv.cmd({"do": "ui", **f})
def bar(**f): return sv.cmd({"do": "edgebar", **f})


def picture(name):
    if not PICTURES:
        return
    os.makedirs(PICTURES, exist_ok=True)
    for look in ("light", "dark"):
        ui(look=look)
        time.sleep(0.6)
        sv.cmd({"do": "picture", "path": f"{PICTURES}/edge-bar-{name}-{look}.png", "page": False})
    ui(look="system")


try:
    sv.setup(sidebar=True)
    sv.launch()
    sv.cmd({"do": "resize", "width": 1100, "height": 700, "steps": 1})
    a = sv.page("a")
    sv.cmd({"do": "go", "id": a, "url": f"{sv.BASE}/b"})
    sv.cmd({"do": "wait", "id": a})
    sv.sp("select", id=a)
    time.sleep(0.5)

    s = bar()
    mid = s["window"][0] / 2
    t.ok("the column out: no card to come", not s["wanted"] and not s["shown"], s)
    s = bar(x=mid, y=2, wait=0.5)
    t.ok("the column out: the top edge brings nothing", not s["shown"], s)
    picture("column-out")

    ui(folded=True)
    time.sleep(0.8)
    s = bar()
    t.ok("folded away: the card may come", s["wanted"] and not s["shown"], s)
    picture("folded")
    f = s["frame"]
    t.ok("in the middle of the top", abs(f[0] + f[2] / 2 - mid) <= 1 and f[1] < 12, f)
    # What watches the pointer for it lies over the whole window and takes
    # nothing: the page and the band the window is dragged by are pressed
    # as before.
    under = sv.cmd({"do": "hit", "x": mid, "y": 300})
    t.ok("the page under its watch still takes the press", "Tracker" not in under.get("view", "") and under.get("view"), under)
    band = sv.cmd({"do": "hit", "x": mid, "y": 4})
    t.ok("and the top band still moves the window", band.get("view") == "Strip" and band.get("movableHovered") is True, band)

    s = bar(x=f[0] - 80, y=2, wait=0.5)
    t.ok("the top edge beside its place brings nothing", not s["shown"], s)
    s = bar(x=mid, y=60, wait=0.5)
    t.ok("nor the page under it", not s["shown"], s)
    bar(x=mid, y=2)
    s = bar(x=mid, y=80, wait=0.5)
    t.ok("nor a pointer crossing the edge without stopping", not s["shown"], s)
    s = bar(x=mid, y=2, pressed=True, wait=0.5)
    t.ok("nor one with a button down", not s["shown"], s)

    s = bar(x=mid, y=2, wait=0.05)
    t.ok("at rest on the edge: not at once", not s["shown"], s)
    s = bar(wait=0.4)
    t.ok("at rest on the edge: down after the wait", s["shown"], s)
    picture("down")

    s = bar(x=mid, y=f[1] + f[3] / 2, wait=0.5)
    t.ok("stays under the pointer", s["shown"], s)
    s = bar(x=f[0] - 60, y=200, wait=0.1)
    t.ok("left: still there for a moment", s["shown"], s)
    s = bar(x=f[0] + 20, y=f[1] + 10, wait=0.5)
    t.ok("back on it in time: it stays", s["shown"], s)
    s = bar(x=f[0] - 60, y=200, wait=0.6)
    t.ok("left for good: gone", not s["shown"], s)

    # It hangs in what AppKit takes for title bar, where a press starts the
    # window's drag before a button hears of it, unless the window is held
    # there. Over its Back and over its address the window is held; beside
    # the card it can be moved as before.
    bar(x=mid, y=2)
    s = bar(wait=0.4)
    t.ok("down again", s["shown"], s)
    back = sv.cmd({"do": "hit", "x": f[0] + 7 + 13, "y": f[1] + f[3] / 2, "hover": True})
    t.ok("over its Back the window is held: the press is the button's", back.get("movableHovered") is False, back)
    address = sv.cmd({"do": "hit", "x": f[0] + f[2] - 60, "y": f[1] + f[3] / 2, "hover": True})
    t.ok("and over its address", address.get("movableHovered") is False, address)
    beside = sv.cmd({"do": "hit", "x": f[0] - 60, "y": 4, "hover": True})
    t.ok("beside it the top edge still moves the window", beside.get("movableHovered") is True, beside)

    # ⌘[ under it: the card says where the page went, and stays for the next.
    sv.cmd({"do": "press", "code": 33, "chars": "[", "mods": ["cmd"]})
    time.sleep(1.2)
    st = sv.sp("state")
    t.ok("the page went back under it", sv.url(st, a).endswith("/a"), sv.url(st, a))
    t.ok("and it is still down", bar()["shown"], bar())
    picture("down-back")

    # ⌘L: the field has the window, and the card is in its way no longer.
    sv.cmd({"do": "press", "code": 37, "chars": "l", "mods": ["cmd"]})
    time.sleep(0.6)
    s = bar()
    t.ok("the field up: the card is gone and may not come", not s["wanted"] and not s["shown"], s)
    sv.cmd({"do": "press", "code": 53, "chars": "\x1b", "mods": []})
    time.sleep(0.5)

    bar(x=mid, y=2)
    s = bar(wait=0.4)
    t.ok("the field put away: it comes again", s["shown"], s)
    ui(peek=True)
    time.sleep(0.5)
    s = bar()
    t.ok("the column out over the page: gone, the column has them", not s["wanted"] and not s["shown"], s)
    ui(peek=False)
    time.sleep(0.4)
    ui(folded=False)
    time.sleep(0.8)
    s = bar(x=mid, y=2, wait=0.5)
    t.ok("the column back beside the page: nothing comes", not s["wanted"] and not s["shown"], s)

    ui(sidebar=False)
    time.sleep(0.8)
    ui(folded=True)
    time.sleep(0.8)
    s = bar(x=mid, y=2, wait=0.5)
    t.ok("the strip across the top folded: its own comes down, not the card", not s["wanted"] and not s["shown"], s)
finally:
    t.done()
    sv.finish()
sys.exit(1 if t.failed else 0)
