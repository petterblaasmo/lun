#!/usr/bin/env python3
"""Pages out of sight load a few at a time (LoadTurns), in the app itself.

Build first (`./build.sh`, or `./build.sh debug`), then
`python3 Tests/tabs_loading.py`. Twenty links are opened behind the page on
screen, each on a server of its own that takes a second and a half to
answer. Half the Mac's processors' worth of them load at once (two to
eight), so:

- never more than that many are being answered at the same time;
- every row says it is loading from the moment it was opened;
- a tab picked while it waits is asked for at once, not after the rest;
- every one of the twenty has loaded in the end, with its own page.

Nothing is shown on screen.
"""
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("tabs-loading")
COUNT = 20
TURNS = min(8, max(2, (os.cpu_count() or 4) // 2))
lock = threading.Lock()
answering = 0
most = 0
asked = []


class Slow(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        global answering, most
        if not self.path.startswith("/page/"):
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        with lock:
            answering += 1
            most = max(most, answering)
            asked.append((self.path.rsplit("/", 1)[-1], time.time()))
        try:
            time.sleep(1.5)
            body = f"<!doctype html><title>Page {self.path.rsplit('/', 1)[-1]}</title><p>page".encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            with lock:
                answering -= 1


# A server for each page: on one, WebKit's few connections to a site would
# make them take turns whatever Lun did.
PORTS = []
for _ in range(COUNT):
    server = ThreadingHTTPServer(("127.0.0.1", 0), Slow)
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    PORTS.append(server.server_port)


def pages():
    return [x for x in sv.cmd({"do": "tabs"})["tabs"] if "/page/" in x["url"]]


def main():
    t = sv.T()
    try:
        sv.setup()
        sv.launch()
        began = time.time()
        ids = [sv.sp("open", url=f"http://127.0.0.1:{port}/page/{n}", foreground=False, atEnd=True)["resultID"]
               for n, port in enumerate(PORTS)]
        now = pages()
        t.ok("twenty tabs behind the page", len(now) == COUNT, len(now))
        t.ok("each says it is loading from the moment it was opened", all(x["loading"] for x in now),
             [x["loading"] for x in now])
        time.sleep(0.6)
        with lock:
            early = [name for name, _ in asked]
        t.ok(f"{TURNS} are asked for at once, the rest wait", len(early) == TURNS, early)

        # The last one opened is still waiting: picked, it is asked for now.
        sv.cmd({"do": "select", "id": ids[-1]})
        time.sleep(0.4)
        with lock:
            picked = [name for name, _ in asked]
        t.ok("a tab picked while it waits is asked for at once, ahead of the tabs waiting before it",
             picked[TURNS:TURNS + 1] == [str(COUNT - 1)], picked)

        for _ in range(600):
            now = pages()
            if all(not x["loading"] and x["title"].startswith("Page ") for x in now):
                break
            time.sleep(0.1)
        took = time.time() - began
        titles = sorted(int(x["title"].split()[-1]) for x in now if x["title"].startswith("Page "))
        t.ok("every one of the twenty has loaded, with its own page", titles == list(range(COUNT)), (titles, round(took, 1)))
        # The one picked loads besides the turns.
        t.ok(f"never more than {TURNS} out of sight were answered at once", most <= TURNS + 1, most)
        with lock:
            names = [name for name, _ in asked]
        t.ok("and each page was asked for once", sorted(names, key=int) == [str(n) for n in range(COUNT)], names)
        print(f"   all twenty loaded {took:.1f} s after the first was opened, {TURNS} at a time")
    except Exception as error:
        t.ok("ran to the end", False, repr(error))
    finally:
        sv.finish()
    t.done()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
