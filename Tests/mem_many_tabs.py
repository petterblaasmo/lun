#!/usr/bin/env python3
"""Lun's own memory with many tabs: where it goes (mem-many-tabs).

Build first (`./build.sh`), then
`python3 Tests/mem_many_tabs.py [N ...] [--rounds R] [--idle S] [--heap] [--vmmap] [--dir D] [--out FILE]`.
PERF_APP=/path/to/Lun.app times another build (a copy kept for before/after).

The world is upstream's perf_many_tabs.py's, kept here: three spaces of N
loose tabs (half, a third, the rest), each with 6 pins (3 as rows) and a
third of its tabs in groups of 6, one folded, on quiet local pages; started
hidden the same way. Per N: the app's footprint (phys_footprint, as
Activity Monitor's Memory column shows it) and its RSS a few seconds after
restore and again after S seconds idle (default 30). With --dir, the
footprint's categories are kept there, and --vmmap adds the regions summary
(MALLOC, CoreAnimation, IOSurface, …), --heap the malloc zones' classes by
count and bytes (`heap -s`). MEM_HOLD=1 keeps the probe running until
Return (or until the file MEM_HOLD_FILE names is removed), for
`malloc_history PID -callTree` and the like: the app ignores
MallocStackLogging from its environment (hardened runtime), but those tools
turn the light stack logging on themselves when they attach.

Footprint, not RSS: RSS counts the frameworks' shared pages, the same in
every app, and is what the 271 MB measured in phase 1 was; Activity
Monitor's Memory column is the footprint.

Nothing here makes, shows, orders in or brings forward a window.
"""
import json
import os
import re
import struct
import subprocess
import sys
import threading
import time
import uuid
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("mem-many-tabs")
# Another build of the app to measure (a copy kept for before/after).
if os.environ.get("PERF_APP"):
    sv.APP = os.environ["PERF_APP"]
IDS = [sv.FIRST_SPACE.upper(), "5E4C0000-0000-4000-8000-0000000020B2", "5E4C0000-0000-4000-8000-0000000020B3"]
SHARE = [0.5, 0.3, 0.2]


# --- pages -----------------------------------------------------------------
def _png():
    raw = b"".join(b"\x00" + b"\x20\x80\xf0\xff" * 16 for _ in range(16))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 16, 16, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


PNG = _png()
LOREM = ("Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et "
         "dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris. ")


def kind(i):
    k = i % 10
    return "static" if k < 6 else "timer" if k < 8 else "mail" if k == 8 else "anim"


def page(path):
    m = re.match(r"/p/(\w+)/(\d+)", path)
    name, i = (m.group(1), int(m.group(2))) if m else ("x", 0)
    k = kind(i)
    paras = "".join(f"<h2>Section {s}</h2><p>{LOREM * 6}</p>" for s in range(20))
    head = f"<link rel=icon href='/icon/{name}-{i}.png'>"
    script = ""
    if k == "timer":
        script = ("<div id=clock></div><script>setInterval(()=>{clock.textContent=new Date().toISOString()},1000);"
                  "setInterval(()=>fetch('/ping').catch(()=>{}),15000)</script>")
    elif k == "mail":
        script = ("<script>let n=0;setInterval(()=>{n=(n+1)%40;document.title=`(${n}) Inbox — "
                  f"{name} {i}`" "},3000)</script>")
    elif k == "anim":
        script = ("<div id=b style='width:300px;height:60px;background:#08f'></div><script>"
                  "(function f(t){b.style.transform=`translateX(${(t/10)%200}px)`;requestAnimationFrame(f)})(0)</script>")
    return f"<!doctype html><html><head><meta charset=utf-8><title>{name} {i} {k}</title>{head}</head><body>{script}{paras}</body></html>".encode()


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/icon/"):
            body, ctype = PNG, "image/png"
        elif self.path == "/ping":
            body, ctype = b"ok", "text/plain"
        else:
            body, ctype = page(self.path), "text/html"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "max-age=3600")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a): pass


srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{srv.server_port}"


# --- the world -------------------------------------------------------------
def counts(n):
    a = [int(n * s) for s in SHARE]
    a[0] += n - sum(a)
    return a


def world(n):
    os.makedirs(sv.SUPPORT, exist_ok=True)
    json.dump([{"id": i, "name": f"S{k}", "colour": k + 2, "sharesSignIns": True} for k, i in enumerate(IDS)],
              open(f"{sv.SUPPORT}/spaces.json", "w"))
    for k, (sid, loose) in enumerate(zip(IDS, counts(n))):
        tabs, groups = [], []
        for p in range(6):
            tabs.append({"url": f"{BASE}/p/pin{k}/{p}", "title": f"pin {k}.{p}", "pin": "ABCDEF"[p],
                         "pinID": str(uuid.UUID(int=(k + 1) * 1000 + p)).upper(), "listed": p >= 3})
        grouped = loose // 3
        for i in range(loose):
            e = {"url": f"{BASE}/p/s{k}/{i}", "title": f"space {k} tab {i}, a title of a usual length"}
            if i < grouped:
                g = i // 6
                if g == len(groups):
                    groups.append({"id": str(uuid.UUID(int=(k + 1) * 100000 + g)).upper(), "name": f"Folder {g}",
                                   "collapsed": g == 1})
                e["groupID"] = groups[g]["id"]
            tabs.append(e)
        shape = {"tabs": tabs, "active": len(tabs) - 1, "groups": groups}
        json.dump(shape, open(f"{sv.SUPPORT}/" + ("session.json" if k == 0 else f"session-{sid}.json"), "w"))


def app_pid():
    p = sv.pids()
    return int(p[0]) if p else 0


def launch():
    if os.path.exists(sv.SOCK):
        os.remove(sv.SOCK)
    before = sv.running()
    env = ["--env", f"SEARCH_PROBE={sv.W}", "--env", "SEARCH_MEASURE=1"]
    subprocess.run(["open", "-n", "-g", "-j", *env, sv.APP])
    for _ in range(900):
        if os.path.exists(sv.SOCK):
            break
        time.sleep(0.02)
    time.sleep(0.5)
    sv.started.update((sv.running() - before) & sv.holding())


def footprint(pid):
    out = subprocess.run(["footprint", "-p", str(pid)], capture_output=True, text=True).stdout
    m = re.search(r"Footprint:\s*([\d.]+)\s*([KMG]B)", out)
    if not m:
        return None, out
    v = float(m.group(1)) * {"KB": 1 / 1024, "MB": 1, "GB": 1024}[m.group(2)]
    return round(v, 1), out


def rss(pid):
    out = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    return round(int(out) / 1024, 1) if out else None


def vmmap(pid):
    out = subprocess.run(["vmmap", "--summary", str(pid)], capture_output=True, text=True).stdout
    rows = {}
    for line in out.splitlines():
        m = re.match(r"^(\S.*?)\s{2,}([\d.]+[KMG]?)\s+([\d.]+[KMG]?)\s+([\d.]+[KMG]?)\s+([\d.]+[KMG]?)", line)
        if m and not line.startswith("REGION"):
            rows[m.group(1).strip()] = {"virtual": m.group(2), "resident": m.group(3), "dirty": m.group(4), "swapped": m.group(5)}
    return rows, out


def heap(pid, top=40):
    out = subprocess.run(["heap", "-s", str(pid)], capture_output=True, text=True).stdout
    return out


def measure(n, rnd, idle, opts):
    out = {"n": n, "round": rnd}
    sv.setup(sidebar=True, spaces=True, **{"tabs.groups": True})
    world(n)
    launch()
    sv.cmd({"do": "resize", "width": 1280, "height": 820, "steps": 1})
    time.sleep(6)
    pid = app_pid()
    out["tabs"] = len(sv.cmd({"do": "tabs"})["tabs"])
    out["restoreMB"], _ = footprint(pid)
    out["restoreRSS"] = rss(pid)
    time.sleep(idle)
    out["idleMB"], fp = footprint(pid)
    out["idleRSS"] = rss(pid)
    tag = opts.get("tag", "m")
    d = opts.get("dir")
    if d:
        os.makedirs(d, exist_ok=True)
        Path(f"{d}/{tag}-{n}-{rnd}.footprint.txt").write_text(fp)
    if opts.get("vmmap"):
        rows, raw = vmmap(pid)
        if d:
            Path(f"{d}/{tag}-{n}-{rnd}.vmmap.txt").write_text(raw)
    if opts.get("heap"):
        raw = heap(pid)
        if d:
            Path(f"{d}/{tag}-{n}-{rnd}.heap.txt").write_text(raw)
    if opts.get("hold"):
        print(json.dumps(out), flush=True)
        print(f"holding pid {pid}; press Return to quit", file=sys.stderr, flush=True)
        if os.environ.get("MEM_HOLD_FILE"):
            Path(os.environ["MEM_HOLD_FILE"]).write_text(str(pid))
            while os.path.exists(os.environ["MEM_HOLD_FILE"]):
                time.sleep(1)
        else:
            sys.stdin.readline()
    sv.quit()
    return out


def main():
    args = sys.argv[1:]
    val = lambda k, d: args[args.index(k) + 1] if k in args else d
    rounds = int(val("--rounds", 1))
    idle = float(val("--idle", 30))
    outfile = val("--out", None)
    opts = {"vmmap": "--vmmap" in args, "heap": "--heap" in args, 
            "hold": os.environ.get("MEM_HOLD") == "1", "tag": val("--tag", "m"), "dir": val("--dir", None)}
    skip = {args.index(k) + 1 for k in ("--rounds", "--idle", "--out", "--tag", "--dir") if k in args}
    ns = [int(a) for i, a in enumerate(args) if a.isdigit() and i not in skip] or [50, 200, 400]
    try:
        for rnd in range(rounds):
            for n in (ns if rnd % 2 == 0 else list(reversed(ns))):
                res = measure(n, rnd, idle, opts)
                line = json.dumps(res)
                print(line, flush=True)
                if outfile:
                    with open(outfile, "a") as f:
                        f.write(line + "\n")
    finally:
        sv.finish()


if __name__ == "__main__":
    main()
