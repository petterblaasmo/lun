#!/usr/bin/env python3
"""The Bookmarks page: a tree of folders beside what the folder picked holds,
as a table or a grid, in a hidden probe.

Build first (`./build.sh debug`), then `python3 Tests/bookmarks_page.py`. The
app is started hidden in a world of its own with made-up bookmarks written to
its file. The page is asked what a hand would do on it through bench `marks`
with "page" (BookmarksPage.swift): a folder picked, list or grid, words in
the search box, one found shown where it lives, and something let go over a
row, a tile or a folder of the tree. A drop goes through the same code a
hand's does from the moment it lands; the carrying itself is the Mac's, and
is tried by hand.

Checked: what the page shows for each folder; that the layout is remembered
across a relaunch; that a drop reorders a folder's bookmarks and its folders,
moves one into a folder, and refuses a folder into itself or what is inside
it; that the file keeps its shape (the same keys for every bookmark, nothing
added); and that a folder of 2,000 builds only the rows in sight.
`--pictures DIR` saves the page, light and dark.
"""
import json
import os
import struct
import sys
import time
import uuid
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("bm-page")


def png(rgb, size=32):
    """A square of one colour, as a site's icon."""
    row = b"\x00" + bytes(rgb) * size
    chunk = lambda kind, data: struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(row * size)) + chunk(b"IEND", b""))


node = lambda **f: {"id": str(uuid.uuid4()).upper(), **f}
site = lambda title, url: node(title=title, url=url)
NORWAY = ["Seven fjords worth the ferry", "Ferry times, Hardangerfjord", "Bus 450, Bergen to Odda", "Where to eat in Ålesund",
          "Bergen harbour camera", "Fish soup from Bergen", "fjord, noun"]
TREE = [
    node(title="Home", children=[site(f"Start {n}", f"https://start.example/{n}") for n in range(1, 7)]),
    node(title="Travel", children=[
        node(title="Norway", children=[
            node(title="Lofoten", children=[site(f"Lofoten {n}", f"https://atlas.example/lofoten/{n}") for n in range(1, 5)]),
            # A folder between two bookmarks in the file: the page shows the
            # folders apart, and a drop still lands beside the right one.
            site(NORWAY[0], "https://atlas.example/fjords"),
            node(title="Ferries", children=[site(f"Ferry {n}", f"https://kart.example/ferries/{n}") for n in range(1, 4)]),
            site(NORWAY[1], "https://kart.example/hardanger"),
            site(NORWAY[2], "https://kart.example/routes/450"),
            site(NORWAY[3], "https://atlas.example/alesund"),
            site(NORWAY[4], "https://harbour-cam.example/"),
            site(NORWAY[5], "https://kettle.example/fiskesuppe"),
            site(NORWAY[6], "https://ord.example/fjord"),
        ]),
        node(title="Food", children=[site(f"Recipe {n}", f"https://kettle.example/recipes/{n}") for n in range(1, 6)]),
        site("Packing list", "https://notes.example/packing"),
        site("Night trains", "https://rail.example/night"),
    ]),
    node(title="Work", children=[site(f"Doc {n}", f"https://docs.example/{n}") for n in range(1, 5)]),
    site("Example Domain", "https://example.com/"),
    site("Weather, West Norway", "https://weather.example/west"),
]
ICONS = {"atlas.example": (45, 108, 223), "kart.example": (32, 160, 160), "kettle.example": (240, 130, 40),
         "ord.example": (245, 190, 50), "start.example": (120, 90, 220), "docs.example": (40, 170, 90),
         "notes.example": (40, 170, 90), "rail.example": (220, 70, 70), "weather.example": (70, 150, 230)}
BIG = 2000


def page(**f):
    return sv.cmd({"do": "marks", "page": f})


def kept():
    """The folder's children by title, as the list is kept."""
    rows = page()["list"]
    return [(r["depth"], r["label"]) for r in rows]


def under(folder):
    """The titles straight under a folder, in the order they are kept."""
    rows = kept()
    at = next(i for i, r in enumerate(rows) if r[1] == folder)
    depth = rows[at][0]
    out = []
    for d, label in rows[at + 1:]:
        if d <= depth: break
        if d == depth + 1: out.append(label)
    return out


def shape(nodes):
    """Every bookmark's keys in a file, for seeing nothing was added."""
    keys = set()
    for n in nodes:
        keys.add(tuple(sorted(n)))
        keys |= shape(n.get("children") or [])
    return keys


def world(tree):
    sv.setup()
    os.system(f"defaults write {sv.SUITE} look -string light")
    os.makedirs(f"{sv.SUPPORT}/icons", exist_ok=True)
    json.dump(tree, open(f"{sv.SUPPORT}/bookmarks.json", "w"))
    for host, rgb in ICONS.items():
        open(f"{sv.SUPPORT}/icons/{host}.png", "wb").write(png(rgb))


def show():
    sv.cmd({"do": "resize", "width": 1280, "height": 900, "steps": 1}); time.sleep(0.4)
    sv.cmd({"do": "ui", "bookmarks": True}); time.sleep(0.8)


def main():
    # Absolute: the app writes the pictures, from where it runs.
    pictures = os.path.abspath(sys.argv[sys.argv.index("--pictures") + 1]) if "--pictures" in sys.argv else None
    t = sv.T()
    try:
        world(TREE)
        sv.launch()
        show()

        p = page()
        t.ok("it opens at the top level, as a list", p["path"] == [] and p["layout"] == "list" and p["tree"], p)
        t.ok("the top level: its folders apart from its bookmarks",
             p["folders"] == ["Home", "Travel", "Work"] and p["bookmarks"] == ["Example Domain", "Weather, West Norway"], p)
        t.ok("…and said in words", p["summary"] == "3 folders, 2 bookmarks", p["summary"])

        if pictures:
            os.makedirs(pictures, exist_ok=True)
            for look in ("light", "dark"):
                sv.cmd({"do": "ui", "look": look}); time.sleep(0.9)
                sv.cmd({"do": "picture", "path": f"{pictures}/bookmarks-top-{look}.png", "page": False})
            sv.cmd({"do": "ui", "look": "light"}); time.sleep(0.9)

        p = page(pick="Norway")
        t.ok("a folder picked: the way to it, its folders and its bookmarks",
             p["path"] == ["Travel", "Norway"] and p["folders"] == ["Lofoten", "Ferries"] and p["bookmarks"] == NORWAY, p)
        t.ok("…and said in words", p["summary"] == "2 folders, 7 bookmarks", p["summary"])
        if pictures:
            for look in ("light", "dark"):
                sv.cmd({"do": "ui", "look": look}); time.sleep(0.9)
                sv.cmd({"do": "picture", "path": f"{pictures}/bookmarks-list-{look}.png", "page": False})
            # A drag stopped on its way: the line between two rows, and a
            # folder of the tree lit to take it.
            for look in ("light", "dark"):
                sv.cmd({"do": "ui", "look": look}); time.sleep(0.9)
                page(held=[NORWAY[3], NORWAY[1], "before", "pane"])
                sv.cmd({"do": "picture", "path": f"{pictures}/bookmarks-carry-{look}.png", "page": False})
                page(held=[NORWAY[3], "Food", "into", "tree"])
                sv.cmd({"do": "picture", "path": f"{pictures}/bookmarks-onto-{look}.png", "page": False})
                page(held=[])
            sv.cmd({"do": "ui", "look": "light"}); time.sleep(0.9)

        # Reordering: a bookmark among the bookmarks, the folder that lies
        # between them in the file notwithstanding.
        page(drop=[NORWAY[3], NORWAY[0], "before"])
        want = [NORWAY[3]] + NORWAY[:3] + NORWAY[4:]
        p = page()
        t.ok("a bookmark let go over the top of the first row goes first", p["bookmarks"] == want, p["bookmarks"])
        t.ok("…and the folders stay where they were", p["folders"] == ["Lofoten", "Ferries"], p["folders"])
        page(drop=[NORWAY[3], NORWAY[6], "after"])
        want = NORWAY[:3] + NORWAY[4:] + [NORWAY[3]]
        t.ok("…over the bottom of the last row, last", page()["bookmarks"] == want, page()["bookmarks"])
        page(drop=[NORWAY[3], NORWAY[4], "before"])
        t.ok("…and back where it was", page()["bookmarks"] == NORWAY, page()["bookmarks"])
        before = under("Norway")
        page(drop=[NORWAY[1], NORWAY[0], "after"])
        t.ok("let go beside the row it already follows: nothing moves, the folder between them neither",
             under("Norway") == before, (before, under("Norway")))

        page(drop=["Ferries", "Lofoten", "before"])
        t.ok("a folder among the folders", page()["folders"] == ["Ferries", "Lofoten"], page()["folders"])
        page(drop=["Ferries", "Lofoten", "after"])
        t.ok("…and back", page()["folders"] == ["Lofoten", "Ferries"], page()["folders"])
        before = under("Norway")
        page(drop=["Lofoten", NORWAY[2], "before"])
        t.ok("a folder over a bookmark's row goes nowhere", under("Norway") == before, under("Norway"))

        # Onto a folder: the tile beside the tree, or its row in the tree.
        page(drop=[NORWAY[6], "Ferries", "before"])
        p = page()
        t.ok("a bookmark over any part of a folder goes into it",
             p["bookmarks"] == NORWAY[:6] and under("Ferries")[-1] == NORWAY[6], (p["bookmarks"], under("Ferries")))
        page(drop=[NORWAY[6], "Norway", "into"])
        t.ok("…and onto the folder it came from, back at its end", page()["bookmarks"] == NORWAY, page()["bookmarks"])
        page(drop=[NORWAY[5], "", "into"])
        t.ok("onto Top Level: out of every folder", NORWAY[5] in [r[1] for r in kept() if r[0] == 0], kept()[-3:])
        page(drop=[NORWAY[5], "Norway", "into"])
        page(drop=[NORWAY[5], NORWAY[6], "before"])
        t.ok("…and back among the others", page()["bookmarks"] == NORWAY, page()["bookmarks"])

        # A folder never goes into itself or what is inside it.
        whole = kept()
        page(drop=["Travel", "Norway", "into"])
        page(drop=["Travel", "Lofoten", "into"])
        page(drop=["Norway", "Norway", "into"])
        page(drop=["Travel", "Food", "before"])
        t.ok("a folder into itself, into what is inside it, or beside what is inside it: refused",
             kept() == whole, [r for r in kept() if r[0] < 2])
        page(drop=["Food", "Norway", "into"])
        t.ok("a folder into the folder beside it", "Food" in under("Norway") and "Food" not in under("Travel"), under("Norway"))
        page(drop=["Food", "Travel", "into"])
        t.ok("…and back, after the folder it stood after", page(pick="Travel")["folders"] == ["Norway", "Food"], under("Travel"))
        page(pick="Norway")

        # Search, as before: flat, and one found is shown where it lives.
        p = page(find="bergen")
        t.ok("search finds in names and addresses", set(p["found"]) == {NORWAY[2], NORWAY[4], NORWAY[5]}, p.get("found"))
        page(pick="")
        p = page(show=NORWAY[4])
        t.ok("Show in Folder: the folder it is in, the search put away",
             p["path"] == ["Travel", "Norway"] and NORWAY[4] in p["bookmarks"], p)

        # The grid, and that it is remembered.
        p = page(layout="grid")
        t.ok("the grid shows the same bookmarks", p["layout"] == "grid" and p["bookmarks"] == NORWAY and p["kept"] == "grid", p)
        if pictures:
            for look in ("light", "dark"):
                sv.cmd({"do": "ui", "look": look}); time.sleep(0.9)
                sv.cmd({"do": "picture", "path": f"{pictures}/bookmarks-grid-{look}.png", "page": False})
            sv.cmd({"do": "ui", "look": "light"}); time.sleep(0.9)
        page(drop=[NORWAY[0], NORWAY[1], "after"])
        t.ok("a drop on a tile's far half goes after it", page()["bookmarks"][:2] == [NORWAY[1], NORWAY[0]], page()["bookmarks"])
        page(drop=[NORWAY[0], NORWAY[1], "before"])

        sv.quit(); time.sleep(0.5)
        saved = json.load(open(f"{sv.SUPPORT}/bookmarks.json"))
        t.ok("the file keeps its shape: the same keys, nothing added", shape(saved) == shape(TREE), shape(saved))
        t.ok("…and every bookmark it had", sorted(shape_ids(saved)) == sorted(shape_ids(TREE)))
        sv.launch()
        show()
        t.ok("list or grid is remembered", page()["layout"] == "grid", page()["layout"])
        page(layout="list")

        # A narrow window: no room for the tree, and the way up is in the path.
        sv.cmd({"do": "resize", "width": 620, "height": 700, "steps": 1}); time.sleep(0.6)
        p = page(pick="Norway")
        t.ok("narrow: the tree gives way, the folder still shows", not p["tree"] and p["bookmarks"] == NORWAY, p)
        if pictures:
            sv.cmd({"do": "picture", "path": f"{pictures}/bookmarks-narrow-light.png", "page": False})
        sv.quit(); time.sleep(0.5)

        # A folder of thousands, as another browser brings: only the rows in
        # sight are built.
        world([node(title="Imported", children=[site(f"Page {n}", f"https://many.example/{n}") for n in range(BIG)])])
        sv.launch()
        show()
        p = page(pick="Imported")
        # Grouped as the Mac's region groups a number: 2,000 or 2 000.
        t.ok(f"a folder of {BIG}: all of them counted", "".join(c for c in p["summary"] if c.isdigit()) == str(BIG), p["summary"])
        t.ok("…and only the rows in sight built", 0 < p["lines"] < 200, p["lines"])
    finally:
        t.done(); sv.finish()
        os.system(f"defaults delete {sv.SUITE} >/dev/null 2>&1; rm -f ~/Library/Preferences/{sv.SUITE}.plist")
    sys.exit(1 if t.failed else 0)


def shape_ids(nodes):
    out = []
    for n in nodes:
        out.append((n["id"], n["title"], n.get("url")))
        out += shape_ids(n.get("children") or [])
    return out


if __name__ == "__main__":
    main()
