"""byearc's "More Arc features": Developer Mode, screenshots in Downloads,
and a pin's glance (DevMode.swift, Screenshots.swift, PinPreview.swift).

Build first (`./build.sh`), then `python3 Tests/arc_extras.py`. A hidden
probe of its own world; nothing is shown, played or signed in to, and the
screenshots folder is one of the world's, never the Mac's own.
"""
import os
import plistlib
import subprocess
import sys
import threading
import time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("arc-extras")

ASKED = []  # (path, Cache-Control, Pragma) for every request


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        ASKED.append((self.path, self.headers.get("Cache-Control", ""), self.headers.get("Pragma", "")))
        if self.path.startswith("/mail"):
            body = b"<!doctype html><title>(3) Probe Mail</title><p>mail"
        else:
            body = b"<!doctype html><title>dev</title><p>local dev page"
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Cache-Control", "max-age=3600")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a): pass


srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
PORT = srv.server_port


def wait(check, within=10, every=0.2):
    end = time.time() + within
    while True:
        r = check()
        if r or time.time() > end: return r
        time.sleep(every)


def open_tab(url):
    tab = sv.cmd({"do": "open", "url": url})
    wait(lambda: not next((t for t in sv.cmd({"do": "tabs"})["tabs"] if t["id"] == tab["id"]), {}).get("loading", True), 10)
    time.sleep(0.5)
    return tab["id"]


def asked(path):
    return [a for a in ASKED if a[0] == path]


def screenshot(folder, name, marked):
    """As the Mac writes one: under a hidden name, marked, then renamed."""
    hidden = folder / ("." + name)
    hidden.write_bytes(b"\x89PNG\r\n\x1a\n")
    if marked is not None:
        value = plistlib.dumps(marked, fmt=plistlib.FMT_BINARY).hex()
        subprocess.run(["xattr", "-wx", "com.apple.metadata:kMDItemIsScreenCapture", value, str(hidden)], check=True)
    hidden.rename(folder / name)


def main():
    t = sv.T()
    try:
        sv.setup()
        sv.launch()
        # The tab in front while the pin is looked at.
        local = open_tab(f"http://127.0.0.1:{PORT}/dev")

        # --- A pin's glance -------------------------------------------------
        # An ordinary tab, not a bench one: bench tabs never sleep.
        mail = sv.sp("open", url=f"http://127.0.0.1:{PORT}/mail")["resultID"]
        time.sleep(2)
        sv.cmd({"do": "pin", "id": mail})
        sv.cmd({"do": "select", "id": local})
        r = sv.cmd({"do": "pinpreview", "id": mail})
        t.ok("pin: on by default", r["on"], r)
        t.ok("pin: the unread count from its title", r["unread"] == "3", r)
        t.ok("pin: no card while the window isn't in front (hidden probe)", r["refusal"] == "window not in front" and not r["shown"], r)
        r = sv.cmd({"do": "pinpreview", "id": mail, "picture": True})
        print("   live pin's picture:", r.get("picture") or "(none: a hidden window paints nothing)")
        # A pin in the space on screen stays awake; one asleep is one put to
        # sleep before it was pinned (or brought back at launch, unopened).
        sv.cmd({"do": "pin", "id": mail, "off": True})
        sv.cmd({"do": "select", "id": local})
        s = sv.cmd({"do": "sleep", "id": mail})
        sv.cmd({"do": "pin", "id": mail})
        s = sv.cmd({"do": "pinpreview", "id": mail})
        t.ok("pin: asleep, as a pin", s["asleep"] and not s["built"], s)
        r = sv.cmd({"do": "pinpreview", "id": mail, "picture": True, "hover": True})
        time.sleep(1)
        after = sv.cmd({"do": "pinpreview", "id": mail})
        t.ok("pin: asleep, asking for its glance doesn't wake it",
             r["asleepAfter"] and not r["builtAfter"] and after["asleep"] and not after["built"], (r, after))
        t.ok("pin: asleep, no unread count (it may be stale)", after["unread"] == "", after)
        t.ok("pin: hovered in a hidden probe, no card", not after["shown"], after)
    finally:
        sv.finish()
    t.done()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
