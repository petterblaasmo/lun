#!/usr/bin/env python3
"""The floating video's page keeps the size it had in its tab (Float.kept).

Build first (`./build.sh`), then `python3 Tests/float_kept.py`. A local
page plays a video beside a column, its player sized by its own script 0.4 s
after a resize, as YouTube's is. Floated and landed with the bench's `film
float|land` in a hidden probe (both windows off every screen), by ⇧⌘P, by
switching tabs and by switching apps, the page must never be given another
size, going out or coming back: no still is put over the little window,
which is shown once the page is drawn in it with the video alone, and the
tab is uncovered as soon as the page is itself again, with no late player to
wait for. The little window shows the part of the page the picture is in,
at its own size and resized: by where the views and the layers put it, and
by the window read back from the window server, the video's own picture
included. A page pinched larger can't keep its size, and is laid out at the
window's as before, under a still (float_settle.py holds that way).
"""
import functools
import json
import shutil
import struct
import sys
import tempfile
import threading
import time
import zlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("float-kept")

# The picture says where it is: four quarters, red and green over blue and
# yellow, and a white square that moves. The player at a size its script
# sets 0.4 s after the last resize, and never at once.
PAGE = """<!doctype html><meta charset=utf-8><title>kept</title>
<style>body{margin:0;display:flex;gap:16px;background:#fff}
#player{background:#000;margin:16px}#side{flex:1;min-width:200px}#side div{height:90px;margin:8px;background:#ddd}
video{width:100%;height:100%;display:block}</style>
<div id=player><video muted playsinline></video></div>
<div id=side><div></div><div></div><div></div><div></div></div>
<canvas width=320 height=180 style="display:none"></canvas>
<script>
var c=document.querySelector('canvas'),g=c.getContext('2d'),n=0;
setInterval(function(){
  g.fillStyle='#e00';g.fillRect(0,0,160,90);g.fillStyle='#0c0';g.fillRect(160,0,160,90);
  g.fillStyle='#00e';g.fillRect(0,90,160,90);g.fillStyle='#ee0';g.fillRect(160,90,160,90);
  g.fillStyle='#fff';g.fillRect((n++*3)%300,80,20,20);
},40);
var v=document.querySelector('video'); v.srcObject=c.captureStream(25);
// Heard, then muted: only a video somebody watches floats on its own
// (Isolate.real), and a muted one is what WebKit stops out of sight.
v.muted=false; v.play().then(function(){setTimeout(function(){v.muted=true},400);});
var p=document.getElementById('player'), later=null, resizes=0;
function fit(){var w=Math.round(innerWidth*0.6);p.style.width=w+'px';p.style.height=Math.round(w*9/16)+'px';}
fit();
addEventListener('resize',function(){resizes++;clearTimeout(later);later=setTimeout(fit,400);});
</script>"""

LIMIT_SEEN, LIMIT_LAND = 800, 300


def close(a, b, by=2):
    return len(a) == len(b) and all(abs(x - y) <= by for x, y in zip(a, b))


def film(action, path, seconds, via="key"):
    sv.cmd({"do": "film", "action": action, "path": path, "seconds": seconds, "via": via})
    return json.loads(Path(path + ".json").read_text())


def when(rows, test):
    """The first time something holds, on the hosts' clock."""
    return next((r["t"] for r in rows if test(r)), None)


def pixels(path):
    """A PNG's size and rows of (r, g, b): eight bits a channel, as the
    bench writes one."""
    data = Path(path).read_bytes()
    at, parts, wide, high, kind = 8, [], 0, 0, 6
    while at < len(data):
        length, name = struct.unpack(">I4s", data[at:at + 8])
        body = data[at + 8:at + 8 + length]
        if name == b"IHDR":
            wide, high, depth, kind = struct.unpack(">IIBB", body[:10])
            assert depth == 8 and kind in (2, 6), (depth, kind)
        elif name == b"IDAT":
            parts.append(body)
        at += 12 + length
    step = 4 if kind == 6 else 3
    raw, line, rows, before = zlib.decompress(b"".join(parts)), wide * step, [], bytearray(wide * step)
    for y in range(high):
        way, row = raw[y * (line + 1)], bytearray(raw[y * (line + 1) + 1:(y + 1) * (line + 1)])
        for i in range(line):
            left = row[i - step] if i >= step else 0
            up, corner = before[i], before[i - step] if i >= step else 0
            if way == 1: row[i] = (row[i] + left) & 255
            elif way == 2: row[i] = (row[i] + up) & 255
            elif way == 3: row[i] = (row[i] + (left + up) // 2) & 255
            elif way == 4:
                p = left + up - corner
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - corner)
                row[i] = (row[i] + (left if pa <= pb and pa <= pc else up if pb <= pc else corner)) & 255
        rows.append(row)
        before = row
    return wide, high, [[tuple(r[x * step:x * step + 3]) for x in range(wide)] for r in rows]


def quarters(path):
    """Whether the window read back shows the picture whole: its quarters'
    colours in the window's quarters, a little in from the corners and from
    the middle, where the white square passes."""
    wide, high, rows = pixels(path)
    def at(x, y): return rows[int(high * y)][int(wide * x)]
    red, green, blue, yellow = at(0.12, 0.15), at(0.88, 0.15), at(0.12, 0.85), at(0.88, 0.85)
    right = (red[0] > 150 and red[1] < 110 and red[2] < 110 and green[1] > 150 and green[0] < 160 and green[2] < 130
             and blue[2] > 150 and blue[0] < 90 and blue[1] < 90 and yellow[0] > 170 and yellow[1] > 170 and yellow[2] < 150)
    return right, {"size": [wide, high], "red": red, "green": green, "blue": blue, "yellow": yellow}


def shown(t, name, out, tab):
    """Where the page is in the little window, and what the window shows."""
    shows = sv.cmd({"do": "float", "action": "shows"})
    page, views, layers = shows.get("page") or [0, 0], shows.get("views") or [], shows.get("layers") or []
    window = [shows.get("width", 0), shows.get("height", 0)]
    t.ok(f"{name}: the layers drawn are where the views put the page", len(views) == 4 and close(views, layers, 0.5), shows)
    if len(views) != 4 or not page[0]:
        return
    # The picture as `contain` fits it in the page, isolated: sixteen by nine.
    by = min(page[0] / 16, page[1] / 9)
    picture = [(page[0] - 16 * by) / 2, (page[1] - 9 * by) / 2, 16 * by, 9 * by]
    scale = views[2] / page[0]
    seen = [views[0] + picture[0] * scale, views[1] + picture[1] * scale, picture[2] * scale, picture[3] * scale]
    fit = min(window[0] / 16, window[1] / 9)
    want = [(window[0] - 16 * fit) / 2, (window[1] - 9 * fit) / 2, 16 * fit, 9 * fit]
    t.ok(f"{name}: the picture is as large as it goes whole in the window, in the middle", close(seen, want, 1.5),
         {"seen": [round(n, 1) for n in seen], "want": [round(n, 1) for n in want], "window": window})
    t.ok(f"{name}: a point of the page is as wide as it is tall", abs(views[2] / page[0] - views[3] / page[1]) < 0.002, shows)
    shot = sv.cmd({"do": "float", "action": "shot", "path": f"{out}/{name.replace(' ', '-').replace(',', '')}.png"})
    if shot.get("error"):
        # Nothing to read a window back with: said, and not counted.
        print(f"  --   {name}: the window could not be read back ({shot['error']})")
        return
    right, found = quarters(shot["saved"])
    t.ok(f"{name}: the window read back shows the picture whole, live", right and close(found["size"], window, 1), found)


def round_trip(t, out, via, tab):
    """Out and back by one way: the page never another size, nothing over
    the little window, and the tab uncovered at once."""
    name = {"key": "⇧⌘P", "switch": "switching tabs", "app": "switching apps"}[via]
    size = sv.cmd({"do": "eval", "id": tab, "js": "JSON.stringify([innerWidth, innerHeight])"})["value"]
    tabs = json.loads(size)

    went = film("float", f"{out}/{via}-float", 1.5, via)
    shift = went["shift"]
    frames = [dict(f, t=f["t"] + shift) for f in went["frames"]]
    hosts = went["hosts"]
    out_there = [h for h in hosts if h["in"] == "float"]
    up = when(hosts, lambda h: h["in"] == "float")
    t.ok(f"{name}, out: the page keeps its tab's size in the little window",
         bool(out_there) and all(h["kept"] for h in out_there) and all(close(s[1:], tabs) for s in went["sizes"])
         and all(close(f["page"], tabs) for f in frames),
         {"sizes": went["sizes"], "layouts": sorted({tuple(f["page"]) for f in frames}), "tab": tabs})
    t.ok(f"{name}, out: no still is put over the little window", all(h["still"] == "none" for h in hosts),
         sorted({h["still"] for h in hosts}))
    seen = when(out_there, lambda h: not h["unseen"])
    alone = when(frames, lambda f: f["isolated"])
    t.ok(f"{name}, out: the window is shown only once the page has drawn the video alone",
         None not in (up, seen, alone) and alone <= seen and out_there[0]["unseen"], {"up": up, "alone": alone, "seen": seen})
    t.ok(f"{name}, out: and within {LIMIT_SEEN} ms of opening",
         None not in (up, seen) and seen - up < LIMIT_SEEN - 20, {"up": up, "seen": seen})
    t.ok(f"{name}, out: the page is in a window all the way",
         not went["unwindowed"] and all(h["in"] != "none" for h in hosts), went["unwindowed"][:5])
    t.ok(f"{name}, out: the video plays on", bool(frames) and all(f["playing"] for f in frames[-10:]), frames[-1:])
    if via == "key":
        shown(t, f"{name}, out", out, tab)
        sv.cmd({"do": "float", "action": "size", "args": [700]})
        shown(t, f"{name}, made larger", out, tab)
        still = sv.cmd({"do": "eval", "id": tab, "js": "JSON.stringify([innerWidth, innerHeight, resizes])"})["value"]
        t.ok(f"{name}, made larger: the page is not laid out again", json.loads(still) == [*tabs, 0], still)
    time.sleep(1.5)

    came = film("land", f"{out}/{via}-land", 2.5, via)
    shift = came["shift"]
    frames = [dict(f, t=f["t"] + shift) for f in came["frames"]]
    hosts = came["hosts"]
    final = frames[-1]
    up = when(hosts, lambda h: h["in"] == "tab" and h["cover"])
    down = when(hosts, lambda h: up is not None and h["t"] > up and not h["cover"])
    t.ok(f"{name}, back: the tab is covered as the page comes home", up is not None and up < 100, up)
    t.ok(f"{name}, back: the page comes home at the size it left at, and is never another",
         all(close(s[1:], tabs) for s in came["sizes"]) and all(close(f["page"], tabs) for f in frames),
         {"sizes": came["sizes"], "layouts": sorted({tuple(f["page"]) for f in frames})})
    itself = when(frames, lambda f: not f["isolated"] and close(f["video"], final["video"]))
    drawn = when(hosts, lambda h: h["in"] == "tab" and close(h["drawn"]["video"] or [0, 0], final["video"]))
    t.ok(f"{name}, back: the cover comes off only once the page is itself again, drawn",
         None not in (down, itself, drawn) and itself < down and drawn <= down,
         {"itself": itself, "drawn": drawn, "down": down})
    late = [f for f in frames if not f["isolated"] and not close(f["video"], final["video"])]
    t.ok(f"{name}, back: with no late player to wait for, within {LIMIT_LAND} ms",
         not late and None not in (up, down) and down - up < LIMIT_LAND - 20, {"up": up, "down": down, "late": late[:2]})
    t.ok(f"{name}, back: the video plays on", bool(frames) and all(f["playing"] for f in frames[-10:]), frames[-1:])
    resizes = sv.cmd({"do": "eval", "id": tab, "js": "resizes"})["value"]
    t.ok(f"{name}: out and back, the page was told of no resize", resizes == 0, resizes)


def main():
    pages = tempfile.mkdtemp(prefix="search-float-kept-")
    Path(pages, "kept.html").write_text(PAGE)
    Path(pages, "other.html").write_text("<!doctype html><meta charset=utf-8><title>other</title><p>another page")

    class Quiet(SimpleHTTPRequestHandler):
        def log_message(self, *args):
            pass
    server = ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=pages))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    out = tempfile.mkdtemp(prefix="search-float-kept-film-")
    t = sv.T()
    try:
        sv.setup(); sv.launch()
        sv.cmd({"do": "window"}); time.sleep(1)
        base = f"http://127.0.0.1:{server.server_port}"
        # Somewhere to switch to, and the video, in front.
        sv.sp("open", url=f"{base}/other.html")
        tab = sv.sp("open", url=f"{base}/kept.html")["resultID"]
        sv.cmd({"do": "select", "id": tab}); time.sleep(2)
        for via in ("key", "switch", "app"):
            round_trip(t, out, via, tab)
            time.sleep(2)

        # Pinched larger, the view shows a part of the page: it can't keep
        # its size, and goes out laid out at the window's, under the still.
        sv.cmd({"do": "magnify", "id": tab, "scale": 1.5})
        went = film("float", f"{out}/pinched-float", 1.5)
        there = [h for h in went["hosts"] if h["in"] == "float"]
        t.ok("pinched larger: the page is laid out at the little window's size, under the video's frame",
             bool(there) and not any(h["kept"] or h["unseen"] for h in there) and there[0]["still"] == "frame"
             and any(close(s[1:], went["view"]) for s in went["sizes"]),
             {"first": there[:1], "sizes": went["sizes"], "view": went["view"]})
        time.sleep(1.5)
        film("land", f"{out}/pinched-land", 2.5)
        sv.cmd({"do": "magnify", "id": tab, "scale": 1})
    finally:
        t.done(); sv.finish()
        server.shutdown()
        shutil.rmtree(pages, ignore_errors=True); shutil.rmtree(out, ignore_errors=True)
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
