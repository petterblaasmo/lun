#!/usr/bin/env python3
"""Split View › Scroll Together, in a hidden probe.

Build first (`./build.sh`), then `python3 Tests/scroll_together.py`. Uses the
split suite's harness: hidden, nothing shown, everything removed afterwards.

Two long pages side by side. Off, each scrolls alone. On (the divider's menu,
here through the bench's `split scrollTogether`), a page scrolled takes the
other by as much, either way round, and the other's own word of that scroll
sends nothing back. A page at its end stays there while the other goes on.
A new page loaded in one moves the other nowhere. Kept with the session.

A page tells of its scroll on the next animation frame, and a page nobody
can see is given none: here each page's frames are stood in for by a timer,
in Search's own world (frames()). The rest is the app's own: the page's
scroll event, its word to the app, the other page moved and marked, and
that page's word known as an echo. Not seen here: two pages on a screen
under a hand.
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("scroll-together")
t = sv.T()


def y(id):
    return sv.ev(id, "window.scrollY")


def scroll(id, to, hand=True):
    """As a hand's scroll reaches the page: a wheel event, the page moved,
    and its own scroll event told of it. `hand` False: the page moved by
    itself, as when its place is put back after a reload."""
    wheel = "window.dispatchEvent(new WheelEvent('wheel')); " if hand else ""
    sv.ev(id, f"{wheel}window.scrollTo(0, {to}); 0")


def frames(*ids):
    """An animation frame for a page out of sight: a timer, for the script
    that tells of its scroll (ScrollRelay.script), which lives in Search's
    own world."""
    for id in ids:
        sv.cmd({"do": "eval", "id": id, "world": "search",
                "js": "window.requestAnimationFrame = function (f) { return setTimeout(f, 0); }; 0"})


def settled(id, want, within=4):
    """The page's place once it is `want`, or what it is after `within`."""
    until = time.time() + within
    got = y(id)
    while abs(got - want) > 1 and time.time() < until:
        time.sleep(0.1)
        got = y(id)
    return got


def together(st):
    return [s.get("together") for s in st.get("splits", [])]


try:
    sv.setup(splitView=True)
    sv.launch()
    a = sv.page("long")
    b = sv.page("tall")
    sv.sp("pair", id=b, **{"with": a}, side="right")
    time.sleep(1)
    frames(a, b)
    st = sv.sp("state")
    t.ok("off to begin with", together(st) == [False], st.get("splits"))

    scroll(a, 300)
    time.sleep(0.8)
    t.ok("off: the other page stays", y(b) == 0, y(b))

    sv.sp("focus", id=a)
    st = sv.sp("scrollTogether")
    t.ok("on, this split's own", together(sv.sp("state")) == [True], st)
    scroll(a, 800)
    t.ok("on: the other goes down by as much", abs(settled(b, 500) - 500) <= 1, y(b))
    time.sleep(0.6)
    t.ok("on: the first isn't pushed on by the other's word", abs(y(a) - 800) <= 1, y(a))

    scroll(b, 400)
    t.ok("on: the other leads as well, up by 100", abs(settled(a, 700) - 700) <= 1, y(a))
    time.sleep(0.6)
    t.ok("on: and stays where it was put", abs(y(b) - 400) <= 1 and abs(y(a) - 700) <= 1, (y(a), y(b)))

    # /tall is 5000 points; /long 20000. Past the short one's end, it stays
    # at its end and the long one goes on.
    end = sv.ev(b, "document.documentElement.scrollHeight - window.innerHeight")
    scroll(a, 12000)
    t.ok("on: a page at its end stays there", abs(settled(b, end) - end) <= 1, (y(b), end))
    time.sleep(0.6)
    t.ok("on: the longer one goes on alone", abs(y(a) - 12000) <= 1, y(a))
    scroll(b, end - 200)
    t.ok("on: back up from its end, the other comes too", abs(settled(a, 11800) - 11800) <= 1, y(a))

    # A new page in one pane starts at its top: that is no scroll.
    before = y(a)
    sv.cmd({"do": "go", "id": b, "url": f"{sv.BASE}/long"})
    time.sleep(2)
    t.ok("on: a new page loaded beside it moves nothing", abs(y(a) - before) <= 1, (before, y(a)))
    # The new page going somewhere before a hand is on it, as a reloaded
    # page goes back to where it was: no scroll of yours either.
    frames(b)
    scroll(b, 600, hand=False)
    time.sleep(1)
    t.ok("on: nor does a page settling in by itself", abs(y(a) - before) <= 1, (before, y(a)))
    scroll(b, 850)
    t.ok("on: and from there it takes the other along", abs(settled(a, before + 250) - (before + 250)) <= 1, (before, y(a)))

    sv.sp("save")
    sv.quit()
    sv.launch()
    time.sleep(1)
    st = sv.sp("state")
    t.ok("relaunch: still on for that split", together(st) == [True], st.get("splits"))
    a, b = st["splits"][0]["tabs"]
    sv.sp("focus", id=a)
    sv.sp("scrollTogether")
    t.ok("off again from the same line", together(sv.sp("state")) == [False], sv.sp("state").get("splits"))
    sv.cmd({"do": "wait", "id": a})
    sv.cmd({"do": "wait", "id": b})
    time.sleep(1)
    frames(a, b)
    start = y(b)
    scroll(a, 1500)
    time.sleep(0.8)
    t.ok("off: each alone again", abs(y(b) - start) <= 1, (start, y(b)))
finally:
    t.done()
    sv.finish()
sys.exit(1 if t.failed else 0)
