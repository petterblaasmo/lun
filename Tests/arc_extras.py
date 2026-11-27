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
        sv.setup(**{"downloads.screenshots": True})
        shots = Path(sv.SUPPORT) / "Screenshots"
        shots.mkdir(parents=True)
        subprocess.run(["defaults", "write", sv.SUITE, "downloads.screenshots.folder", "-string", str(shots)], check=True)
        # Already there before: never listed.
        screenshot(shots, "Screenshot 2026-11-25 at 08.00.00.png", True)
        sv.launch()

        # --- Screenshots in Downloads ---------------------------------------
        r = wait(lambda: (lambda s: s if s["folder"] else None)(sv.cmd({"do": "screenshots"})), 5)
        t.ok("shots: watching the world's folder, not refused",
             r and Path(r["folder"]).resolve() == shots.resolve() and not r["refused"], r)
        screenshot(shots, "Screenshot 2026-11-25 at 23.00.00.png", True)
        screenshot(shots, "holiday.png", None)
        screenshot(shots, "Screenshot 2026-11-25 at 23.01.00.png", False)
        r = wait(lambda: (lambda s: s if any(c["name"].endswith("23.00.00.png") for c in s["completed"]) else None)(
            sv.cmd({"do": "screenshots"})), 5) or sv.cmd({"do": "screenshots"})
        names = [c["name"] for c in r["completed"]]
        time.sleep(0.8)
        names = [c["name"] for c in sv.cmd({"do": "screenshots"})["completed"]]
        t.ok("shots: the new screenshot is listed", "Screenshot 2026-11-25 at 23.00.00.png" in names, names)
        t.ok("shots: … as a Screenshot", any(c["from"] == "Screenshot" for c in r["completed"]), r["completed"])
        t.ok("shots: nothing else (old one, other picture, one marked not a capture)", len(names) == 1, names)
        r = sv.cmd({"do": "screenshots", "set": False})
        screenshot(shots, "Screenshot 2026-11-25 at 23.05.00.png", True)
        time.sleep(1)
        names = [c["name"] for c in sv.cmd({"do": "screenshots"})["completed"]]
        t.ok("shots: off, nothing more", len(names) == 1 and not r["on"], names)
    finally:
        sv.finish()
    t.done()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
