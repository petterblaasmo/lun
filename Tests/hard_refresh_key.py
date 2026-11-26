#!/usr/bin/env python3
"""⇧⌘R is the hard refresh, and ⌥⌘R is Reading Mode, pressed as real keys.

Build first (`./build.sh`), then `python3 Tests/hard_refresh_key.py`. Uses the
split suite's harness: started hidden, no window made or shown, everything
removed afterwards. The keys go through the app's own event queue (bench
`press`), so the window's key handler takes them as it does a real press:
the menus alone had the new keys at first, and the handler still sent ⇧⌘R
to Reading Mode.

- ⌘R and ⇧⌘R both fetch the page again, and it is still the page;
- ⌥⌘R shows the article alone.
"""
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("hard-refresh-key")
t = sv.T()
hits = []
TEXT = "".join(f"<p>Paragraph {i}. " + "The fjord was still that morning, and the ferry late. " * 8 + "</p>" for i in range(12))


class Page(BaseHTTPRequestHandler):
    def do_GET(self):
        hits.append(self.path)
        body = (f"<!doctype html><title>An article</title><nav id=nav>menu</nav>"
                f"<article><h1>Seven fjords</h1>{TEXT}</article>").encode()
        self.send_response(200); self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)

    def log_message(self, *a): pass


server = ThreadingHTTPServer(("127.0.0.1", 0), Page)
threading.Thread(target=server.serve_forever, daemon=True).start()
URL = f"http://127.0.0.1:{server.server_port}/article"
R = 15  # the R key


def press(*mods): sv.cmd({"do": "press", "code": R, "chars": "r", "mods": list(mods)}); time.sleep(2.0)
def marked(id): return sv.ev(id, "String(window.__mark)")
def nav(id): return sv.ev(id, "String(!!document.getElementById('nav'))")
def fetched(): return len([h for h in hits if h == "/article"])


try:
    sv.setup(); sv.launch()
    a = sv.page("first"); sv.sp("select", id=a); time.sleep(0.5)
    sv.ev(a, f"location.href = '{URL}'; true"); time.sleep(2.0)
    t.ok("the article is loaded, with its menu", nav(a) == "true" and fetched() == 1, (nav(a), fetched()))

    sv.ev(a, "window.__mark = 7; true")
    press("cmd")
    t.ok("⌘R fetches it again", fetched() == 2 and marked(a) == "undefined", (fetched(), marked(a)))

    sv.ev(a, "window.__mark = 7; true")
    press("cmd", "shift")
    t.ok("⇧⌘R fetches it again: the hard refresh", fetched() == 3 and marked(a) == "undefined", (fetched(), marked(a)))
    t.ok("…and it is still the page, not Reading Mode", nav(a) == "true", nav(a))

    press("cmd", "opt")
    t.ok("⌥⌘R shows the article alone: Reading Mode", nav(a) == "false", nav(a))
finally:
    t.done()
    sv.finish()
sys.exit(1 if t.failed else 0)
