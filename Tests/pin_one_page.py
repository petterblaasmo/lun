#!/usr/bin/env python3
"""A pin kept in every space keeps one page in a window, in a hidden probe:
which space has the page, that it is the same document still running after
a switch, what each space keeps in front, and what stays apart (a space with
its own sign-ins, another window, another profile).

Build first (`./build.sh`), then `python3 Tests/pin_one_page.py`. It uses the
split suite's harness in a world of its own (see split_view.use()), so it
can run beside that suite.
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("pin-one-page")


def command(operation, **fields):
    return sv.cmd({"do": operation, **fields})


def settled(window=1, done=lambda state: True, within=5):
    """The window's state once `done` says so and two looks in a row agree:
    a switch taken, and what follows it a turn later (pins matched to the
    row, the page in front woken) in. Waited for, not slept through."""
    deadline = time.monotonic() + within
    last = None
    while True:
        state = sv.sp("state", window=window)
        look = (state["spaceID"], state["activeID"], [tab["id"] for tab in state["tabs"]], state["everywhere"])
        if (done(state) and look == last) or time.monotonic() > deadline:
            return state
        last = look
        time.sleep(0.05)


def space(action, window=1, **fields):
    before = sv.sp("state", window=window)
    command("space", action=action, window=window, **fields)
    if action == "go":
        target = before["spaceIDs"][fields["index"] - 1]
        return settled(window, lambda state: state["spaceID"] == target)
    if action == "new":
        return settled(window, lambda state: len(state["spaceIDs"]) > len(before["spaceIDs"])
                       and state["spaceID"] == state["spaceIDs"][-1])
    if action == "swipe":
        return settled(window, lambda state: state["spaceID"] != before["spaceID"])
    return settled(window, lambda state: before["spaceID"] not in state["spaceIDs"])


def select(tab):
    command("select", id=tab)


def shared(state):
    return next(tab for tab in state["tabs"] if tab["id"] in state["everywhere"])


def front(state):
    return next(tab for tab in state["tabs"] if tab["id"] == state["activeID"])


def share(tab, **fields):
    command("pin", id=tab, **fields)
    command("pin", id=tab, everywhere=True, **fields)


def case_same_document_runs_on(t):
    """the page goes along, still running: by ⌃1–⌃9, by a swipe, and back"""
    sv.setup(spaces=True, **{"float.leave": False})
    sv.launch()
    command("window")
    sv.page("loose")
    pin = sv.page("player")
    share(pin)
    sv.ev(pin, "window.marker = 'live'; window.ticks = 0; setInterval(() => window.ticks++, 50); scrollTo(0, 0); true")
    web = shared(sv.sp("state"))["web"]
    cold = space("new", name="Second")
    t.ok("a space not yet gone to opens on an empty tab", front(cold)["blank"], front(cold))
    there = shared(cold)
    t.ok("…with the pin's page beside it: the same tab and view", there["id"] == pin and there["web"] == web,
         (pin, web, there))
    sv.page("second-loose")
    before = sv.ev(pin, "window.ticks")
    time.sleep(1.5)
    after = sv.ev(pin, "[window.marker, window.ticks]")
    t.ok("the same document, still running there", after[0] == "live" and after[1] > before, (before, after))
    back = space("go", index=1)
    t.ok("the first space has it again, in front as it was left",
         shared(back)["web"] == web and back["activeID"] == pin, (back["activeID"], shared(back)))
    # Two fingers to the next space: its page shown ahead, then taken.
    swiped = space("swipe", dx=-180)
    t.ok("a swipe takes the next space", swiped["spaceID"] == swiped["spaceIDs"][1], swiped["spaceID"])
    t.ok("…its own tab in front", front(swiped)["url"].endswith("/second-loose"), front(swiped))
    t.ok("…and the page came", shared(swiped)["id"] == pin and shared(swiped)["web"] == web, shared(swiped))
    select(pin)
    time.sleep(0.5)
    home = space("swipe", dx=180)
    t.ok("in front in both, a swipe back keeps it in front", home["activeID"] == pin and shared(home)["web"] == web,
         (home["activeID"], shared(home)))
    last = sv.ev(pin, "[window.marker, window.ticks]")
    t.ok("…the document never loaded again", last[0] == "live" and last[1] > after[1], (after, last))
    built = [tab for tab in sv.sp("state")["tabs"] if tab["id"] in sv.sp("state")["everywhere"] and tab["web"]]
    t.ok("one view for the pin in the row", len(built) == 1, built)


def case_two_pins_and_restart(t):
    """two pins at one address, and a restart"""
    sv.setup(spaces=True, **{"start.fresh": False})
    sv.launch()
    command("window")
    pins = []
    for marker in ["first", "second"]:
        tab = sv.page("same-url")
        share(tab)
        sv.ev(tab, f"window.name = '{marker}'")
        pins.append(tab)
    views = {x["id"]: x["web"] for x in sv.sp("state")["tabs"] if x["id"] in pins}
    cold = space("new", name="Second")
    there = {x["id"]: x["web"] for x in cold["tabs"] if x["id"] in pins}
    t.ok("two pins at one address each bring their own page", there == views, (views, there))
    names = [sv.ev(tab, "window.name") for tab in pins]
    t.ok("…and their own document", names == ["first", "second"], names)
    sv.page("second-loose")
    back = space("go", index=1)
    t.ok("the first space still has its pin in front", back["activeID"] == pins[1], back["activeID"])
    sv.sp("save")
    sv.quit()
    sv.launch()
    restored = sv.sp("state")
    active = restored["activeID"]
    t.ok("after a restart the pin is in front again", active == restored["everywhere"][1],
         (active, restored["everywhere"]))
    web = next(x["web"] for x in restored["tabs"] if x["id"] == active)
    t.ok("…with its page", bool(web), web)
    second = space("go", index=2)
    t.ok("the second space has its own tab in front", front(second)["url"].endswith("/second-loose"), front(second))
    same = next(x["web"] for x in second["tabs"] if x["id"] == active)
    t.ok("…and the pin there is the same page", same == web, (web, same))


def case_live_page_past_a_separate_space(t):
    """a page left running in one space, a space with its own sign-ins gone through, then the next"""
    sv.setup(spaces=True, **{"float.leave": False})
    sv.launch()
    command("window")
    pin = sv.page("home")
    share(pin)
    sv.ev(pin, "window.marker = 'live'")
    web = shared(sv.sp("state"))["web"]
    space("new", name="Second")
    sv.page("loose")
    space("go", index=1)
    select(pin)
    apart = shared(space("new", name="Separate", fresh=True))
    t.ok("the space with its own sign-ins has a tab of its own", apart["id"] != pin and apart["web"] != web, apart)
    # Straight from the separate space: the page is still in the first
    # space's row, parked, and comes from there.
    there = shared(space("go", index=2))
    t.ok("from there, the next space signed in with the first has the page", there["id"] == pin and there["web"] == web,
         (pin, web, there))
    select(pin)
    marker = sv.ev(pin, "window.marker")
    t.ok("…the same document", marker == "live", marker)
    back = space("go", index=1)
    t.ok("…and the first space has it again, in front as it was left",
         shared(back)["web"] == web and back["activeID"] == pin, (back["activeID"], shared(back)))
    again = shared(space("go", index=3))
    t.ok("the separate space still has its own", again["id"] == apart["id"], (apart, again))


def case_restart_in_a_separate_space(t):
    """a restart in a space with its own sign-ins: the spaces signed in together still share one page"""
    sv.setup(spaces=True, **{"pins.home": False, "pins.peek": False, "start.fresh": False})
    sv.launch()
    command("window")
    pin = sv.page("home")
    share(pin)
    space("new", name="Second")
    sv.page("loose")
    separate = space("new", name="Separate", fresh=True)["spaceID"]
    sv.sp("save")
    sv.quit()
    sv.launch()
    came = sv.sp("state")["spaceID"]
    t.ok("back in the separate space", came == separate, (came, separate))
    documents = []
    for index in (1, 2):
        state = space("go", index=index)
        page = shared(state)
        select(page["id"])
        command("wait", id=page["id"])
        page = shared(sv.sp("state"))
        t.ok(f"space {index}: the pin has a page", bool(page["web"]), page)
        seen = sv.ev(page["id"], "(() => { const seen = !!window.revisited; window.revisited = true; return seen })()")
        t.ok(f"space {index}: {'the document seen before' if documents else 'a document not seen before'}",
             seen == bool(documents), seen)
        documents.append((page["id"], page["web"]))
    t.ok("one page for both spaces", documents[0] == documents[1], documents)


def case_deletion_and_what_stays_apart(t):
    """a space deleted under the page, and what never shares it"""
    sv.setup(spaces=True)
    sv.launch()
    command("window")
    pin = sv.page("source")
    share(pin)
    sv.ev(pin, "document.cookie = 'login=shared;path=/'; window.marker = 'survivor'")
    original = shared(sv.sp("state"))["web"]
    space("new", name="Deleted while visible")
    # The new window has never switched spaces. Its own live document
    # must survive when the first window deletes the space both show.
    command("windows", action="front", n=1)
    command("windows", action="new")
    copy = shared(sv.sp("state", window=2))["id"]
    command("select", id=copy, window=2)
    command("wait", id=copy, window=2)
    command("eval", id=copy, window=2, js="window.marker = 'second window'")
    space("delete")
    moved = shared(sv.sp("state", window=2))
    marker = command("eval", id=copy, window=2, js="window.marker")["value"]
    t.ok("its space deleted in another window, a window keeps its page of the pin",
         moved["id"] == copy and marker == "second window", (copy, moved, marker))
    here = shared(sv.sp("state"))
    t.ok("…and the window that deleted it took its page along", here["id"] == pin and here["web"] == original, here)
    command("windows", action="close", n=2)
    space("new", name="Survives")
    space("go", index=1)
    separate = shared(space("new", name="Separate", fresh=True))["id"]
    select(separate)
    command("wait", id=separate)
    apart = sv.ev(separate, "[window.marker || null, document.cookie]")
    t.ok("a space with its own sign-ins has a page and cookies of its own", apart == [None, ""], apart)
    sv.ev(separate, "document.cookie = 'login=separate;path=/'; window.marker = 'separate'")
    command("windows", action="new")
    time.sleep(1)
    space("go", index=1, window=2)
    copy = shared(sv.sp("state", window=2))["id"]
    command("select", id=copy, window=2)
    command("wait", id=copy, window=2)
    other = shared(sv.sp("state", window=2))["web"]
    t.ok("another window has a page of its own", other != original, (original, other))
    # The first space, whose row has the page while the separate one is on
    # screen, deleted from the other window.
    space("delete", window=2)
    apart = sv.ev(separate, "[window.marker, document.cookie]")
    t.ok("the space with the page deleted elsewhere, the separate space is untouched",
         apart == ["separate", "login=separate"], apart)
    survivor = shared(space("go", index=1))["web"]
    t.ok("…and the page is in a space that is left", survivor == original, (original, survivor))
    select(pin)
    kept = sv.ev(pin, "[window.marker, document.cookie]")
    t.ok("…as it was", kept == ["survivor", "login=shared"], kept)

    command("profile", action="new", name="Other profile")
    command("profile", action="window", name="Other profile")
    time.sleep(1)
    theirs = sv.sp("state", window=3)["everywhere"]
    t.ok("another profile has none of these pins", not theirs, theirs)
    other = sv.sp("open", url=sv.BASE + "/source", window=3)["resultID"]
    command("wait", id=other, window=3)
    share(other, window=3)
    view = shared(sv.sp("state", window=3))["web"]
    seen = command("eval", id=other, js="[window.marker || null, document.cookie]", window=3).get("value")
    t.ok("its own pin at the same address is another page, signed in apart", view != original and seen == [None, ""],
         (view, seen))
    mine = sv.ev(pin, "window.marker")
    t.ok("…and this profile's is as it was", mine == "survivor", mine)


def case_only_in_this_space(t):
    """a pin kept by one space again"""
    sv.setup(spaces=True, **{"float.leave": False})
    sv.launch()
    command("window")
    space("new", name="Second")
    sv.page("other")
    space("go", index=1)
    pin = sv.page("home")
    share(pin)
    sv.ev(pin, "window.marker = 'original'")
    came = shared(space("go", index=2))
    t.ok("the other space has the page", came["id"] == pin, came)
    command("pin", id=pin, everywhere=False)
    elsewhere = space("go", index=1)["everywhere"]
    t.ok("kept by this space alone, the other spaces have it no more", not elsewhere, elsewhere)
    space("go", index=2)
    marker = sv.ev(pin, "window.marker")
    t.ok("…and this space still has its page", marker == "original", marker)
    command("pin", id=pin, everywhere=True)
    again = shared(space("go", index=1))
    t.ok("kept in every space again, it goes along again", again["id"] == pin, again)
    marker = sv.ev(pin, "window.marker")
    t.ok("…the same document", marker == "original", marker)


def main():
    t = sv.T()
    for case in [case_same_document_runs_on, case_two_pins_and_restart, case_live_page_past_a_separate_space,
                 case_restart_in_a_separate_space, case_deletion_and_what_stays_apart, case_only_in_this_space]:
        print(f"— {case.__doc__}")
        try:
            case(t)
        except Exception as error:
            t.ok(f"{case.__name__} ran to the end", False, repr(error))
        finally:
            sv.finish()
    t.done()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
