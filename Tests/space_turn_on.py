"""Turning Spaces on leaves one space, named, and nothing unexplained beside it.

Build first (`./build.sh`), then `python3 Tests/space_turn_on.py`. A hidden
probe with Spaces off brings over a made-up Arc profile with one space,
"School" (a synthetic StorableSidebar.json, never anyone's real Arc data):
its page comes into the one space there is, which takes Arc's name and icon.
Spaces turned on then shows that one space, School, renamable. A stroke over
the tabs toward a next space, with only one, brings the card for a new one,
as it does past the last of several (in Lun: it did nothing there before);
a stroke back puts it away. New Space… brings the card too.

Nothing here makes, shows or brings forward a window.
"""
import json
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("sp-turn-on")


def arc():
    root = f"{sv.SUPPORT}/Import/Arc"
    os.makedirs(f"{root}/User Data/Default", exist_ok=True)
    items = [{"id": "s-0", "title": "Ex", "data": {"tab": {"savedURL": "https://example.com/", "savedTitle": "Ex"}}},
             {"id": "s", "childrenIds": ["s-0"]}]
    spaces = [{"title": "School", "profile": {"default": {}}, "containerIDs": ["pinned", "s"],
               "customInfo": {"iconType": {"icon": "graduationcap"}}}]
    sidebar = {"sidebar": {"containers": [{"spaces": spaces, "items": items, "topAppsContainerIDs": []}]}}
    Path(f"{root}/StorableSidebar.json").write_text(json.dumps(sidebar))
    Path(f"{root}/User Data/Default/History").write_bytes(b"")


def main():
    t = sv.T()
    try:
        sv.setup(**{"spaces": False, "start.fresh": False})
        arc()
        sv.launch()
        out = sv.cmd({"do": "import", "from": "Arc", "what": ["spaces"]}).get("arc") or {}
        t.ok("one Arc space, Spaces off: it comes into the one space there is",
             out.get("spaces") == 0 and out.get("usesSpaces") is False and out.get("names") == ["School"], out)

        sv.cmd({"do": "ui", "spaces": True})
        time.sleep(1)
        st = sv.cmd({"do": "space"})
        t.ok("Spaces on: one space, School", [s["name"] for s in st["spaces"]] == ["School"] and st["current"] == "School",
             st["spaces"])
        menu = [m["title"] for m in st["menu"]]
        t.ok("and it can be renamed", "Rename “School”…" in menu, menu)

        sv.cmd({"do": "space", "action": "swipe", "dx": -400})
        time.sleep(1)
        st = sv.cmd({"do": "space"})
        t.ok("a stroke toward a next space, with one: the card for a new one, still School",
             st["making"] and st["current"] == "School" and len(st["spaces"]) == 1, (st["making"], st["current"]))
        sv.cmd({"do": "space", "action": "swipe", "dx": 400})
        time.sleep(1)
        st = sv.cmd({"do": "space"})
        t.ok("a stroke back puts the card away, and nothing was made",
             not st["making"] and st["current"] == "School" and len(st["spaces"]) == 1, (st["making"], st["current"]))

        sv.cmd({"do": "space", "action": "menu", "title": "New Space…"})
        time.sleep(1)
        t.ok("New Space… brings the card too", sv.cmd({"do": "space"})["making"], sv.cmd({"do": "space"})["making"])
    finally:
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


main()
