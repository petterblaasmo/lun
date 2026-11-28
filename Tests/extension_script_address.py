#!/usr/bin/env python3
"""An extension's own script in a page can find its files, in a hidden probe.

Build first (`./build.sh debug`), then `python3 Tests/extension_script_address.py`.
It runs a copy of build/Lun.app under a bundle id of its own, in a world of
its own with split_view.py's harness, started hidden; the copy, its WebKit
folders and the world are removed afterwards.

FrankerFaceZ's content script adds <script src="<extension>/web/avalon.js">
to Twitch; that bundle finds its styles, fonts and chunks from
document.currentScript.src (webpack's automatic public path), and in the
page's world WebKit gives an extension's address as
webkit-masked-url://hidden/, so they pointed nowhere (#228). The browser now
tells such a script its address (ExtensionPageScript.addresses). A fixture
extension puts its script in a local page the way FrankerFaceZ does. Checked:

- the script reads its own address, as the content script wrote it, every
  time over many loads (from WebKit's memory the file runs at once);
- so does one given its address after it was put in the page, one in a
  frame, and one the browser runs itself because the page's policy refused it;
- the page reads the element as before, masked, property and attribute,
  and so does a script of the page's own while it runs; its listeners hear
  nothing of what the content script's shim says;
- a file the manifest doesn't make web-accessible doesn't run.
"""
import json
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("ext-script-address")
BUNDLE = "com.lunbrowser.lun.extscriptaddress"
MASKED = "webkit-masked-url://hidden/"
work = Path(tempfile.mkdtemp(prefix="lun-extscriptaddress-"))


class Site(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?")[0]
        frame = b"<iframe src='/inner'></iframe>" if path == "/framing" else b""
        # The page listens for what the content script's shim says.
        ears = (b"<script nonce=abc>for (const where of [window, document]) where.addEventListener('search-script-address', "
                b"(e) => { document.documentElement.dataset.heard = String(e.detail); }, true);</script>")
        body = b"<!doctype html><title>t</title>" + ears + b"<p>page</p>" + frame
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        if path == "/strict":
            # YouTube's, in short (as in extension_page_script.py).
            self.send_header("Content-Security-Policy", "script-src 'unsafe-eval' 'self' 'unsafe-inline' https://www.google.com")
            self.send_header("Content-Security-Policy", "script-src 'nonce-abc' 'unsafe-inline' 'strict-dynamic' https: http: 'unsafe-eval'")
            self.send_header("Content-Security-Policy", "require-trusted-types-for 'script'")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


FILES = {
    "manifest.json": json.dumps({
        "manifest_version": 3, "name": "ScriptAddress", "version": "1.0",
        "background": {"service_worker": "sw.js"},
        "content_scripts": [{"matches": ["http://127.0.0.1/*"], "js": ["cs.js"], "run_at": "document_idle", "all_frames": True}],
        "web_accessible_resources": [{"resources": ["web/*"], "matches": ["http://127.0.0.1/*"]}],
    }),
    "sw.js": "chrome.runtime.onMessage.addListener(() => {});",
    # What it reads as its own address, as webpack's public path reads it.
    "web/main.js": """
(() => {
  const d = document.documentElement.dataset, s = document.currentScript;
  const tag = s && s.dataset.tag || "None";
  d["src" + tag] = s ? s.src : "none";
  d["attr" + tag] = s ? String(s.getAttribute("src")) : "none";
  // Run by the browser, document.currentScript is a property it put there.
  d["by" + tag] = Object.getOwnPropertyDescriptor(document, "currentScript") ? "the browser" : "WebKit";
})();
""",
    "hidden.js": "document.documentElement.dataset.hidden = document.currentScript.src;",
    # FrankerFaceZ's way: async, anonymous, a query against the cache.
    "cs.js": """
const add = (file, tag, late) => {
  const s = document.createElement("script");
  const address = chrome.runtime.getURL(file) + "?_=" + tag;
  s.async = true; s.crossOrigin = "anonymous"; s.dataset.tag = tag;
  if (!late) s.src = address;
  document.head.appendChild(s);
  if (late) s.src = address;
};
document.documentElement.dataset.base = chrome.runtime.getURL("");
add("web/main.js", "One");
add("web/main.js", "Late", true);
add("hidden.js", "Hidden");
""",
}

LOOK = "JSON.stringify(Object.assign({}, document.documentElement.dataset))"


def probe_copy():
    """build/Lun.app under a bundle id of its own, signed ad hoc."""
    app = work / "Lun.app"
    shutil.copytree(Path(sv.ROOT, "build", "Lun.app"), app, symlinks=True)
    subprocess.run(["/usr/libexec/PlistBuddy", "-c", f"Set :CFBundleIdentifier {BUNDLE}", str(app / "Contents/Info.plist")], check=True)
    (app / "Contents/embedded.provisionprofile").unlink(missing_ok=True)
    subprocess.run(["codesign", "-f", "-s", "-", "--entitlements", str(Path(sv.ROOT, "Search.entitlements")), "--deep", str(app)],
                   check=True, capture_output=True)
    return str(app)


def look(tid, js=LOOK, within=10, until=lambda d: False):
    end = time.time() + within
    found = {}
    while time.time() < end:
        # Between two documents there is nothing to ask.
        try:
            found = json.loads(sv.ev(tid, js) or "{}")
        except RuntimeError:
            found = {}
        if until(found):
            break
        time.sleep(0.2)
    return found


def main():
    t = sv.T()
    site = ThreadingHTTPServer(("127.0.0.1", 0), Site)
    threading.Thread(target=site.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{site.server_port}"
    folder = work / "ext"
    (folder / "web").mkdir(parents=True)
    for name, body in FILES.items():
        (folder / name).write_text(body)
    sv.APP = probe_copy()
    try:
        sv.setup()
        sv.launch()
        sv.cmd({"do": "ext-folder", "path": str(folder), "yes": True})
        ext = None
        for _ in range(60):
            ext = next((x for x in sv.cmd({"do": "extensions"})["extensions"] if x["name"] == "ScriptAddress" and x["loaded"]), None)
            if ext:
                break
            time.sleep(0.5)
        t.ok("the extension loads", ext is not None)
        if not ext:
            return t
        own = f"chrome-extension://{ext['id']}/"
        ran = lambda d: "srcOne" in d and "srcLate" in d

        tid = sv.sp("open", url=base + "/page")["resultID"]
        d = look(tid, until=ran)
        t.ok("its script reads its own address, as the content script wrote it", d.get("srcOne") == own + "web/main.js?_=One", d)
        t.ok("one given its address after it was put in the page reads it too", d.get("srcLate") == own + "web/main.js?_=Late", d)
        t.ok("the attribute stays as WebKit gives it", d.get("attrOne") == MASKED, d)
        time.sleep(1)
        seen = json.loads(sv.ev(tid, "JSON.stringify(Array.from(document.querySelectorAll('script[data-tag]'), (s) => [s.src, s.getAttribute('src')]).flat())"))
        t.ok("the page reads the elements as before, masked", len(seen) == 6 and all(x == MASKED for x in seen), seen)
        # A script of the page's own, while it is the one running.
        sv.ev(tid, "(() => { const s = document.createElement('script'); s.textContent = "
                   "\"document.documentElement.dataset.pageSaw = document.querySelector('script[data-tag=One]').src\"; document.head.appendChild(s); })(); 1")
        d = look(tid, within=3, until=lambda d: "pageSaw" in d)
        t.ok("and so does a script of the page's own while it runs", d.get("pageSaw") == MASKED, d)
        t.ok("a file that isn't web-accessible doesn't run", "hidden" not in d, d)
        t.ok("the page's own listeners hear no address", "heard" not in d, d)

        # Every time: from the second load on the file is in WebKit's
        # memory and runs at once.
        told = 0
        loads = 25
        for i in range(loads):
            sv.cmd({"do": "go", "id": tid, "url": f"{base}/page?{i}"})
            d = look(tid, js=f"location.search === '?{i}' ? {LOOK} : '{{}}'", within=8, until=ran)
            told += d.get("srcOne") == own + "web/main.js?_=One" and d.get("srcLate") == own + "web/main.js?_=Late"
        t.ok(f"over {loads} more loads, every time", told == loads, told)

        sv.cmd({"do": "go", "id": tid, "url": base + "/framing"})
        inner = "JSON.stringify(frames[0] && frames[0].document.documentElement ? Object.assign({}, frames[0].document.documentElement.dataset) : {})"
        d = look(tid, js=inner, until=ran)
        t.ok("in a frame too", d.get("srcOne") == own + "web/main.js?_=One", d)

        # Refused by the page's policy, the browser runs the file itself
        # (ExtensionPageScript.run), and the script reads its address there too.
        sv.cmd({"do": "go", "id": tid, "url": base + "/strict"})
        time.sleep(6)
        d = look(tid, within=10, until=ran)
        t.ok("and when the browser runs it for a page whose policy refuses it",
             d.get("byOne") == "the browser" and d.get("srcOne") == own + "web/main.js", d)
        time.sleep(0.5)
        seen = sv.ev(tid, "document.querySelector('script[data-tag=One]').src")
        t.ok("after which the page reads that element masked again", seen == MASKED, seen)
    finally:
        sv.finish()
        for kind in ("WebKit", "Caches", "HTTPStorages"):
            shutil.rmtree(Path.home() / "Library" / kind / BUNDLE, ignore_errors=True)
        shutil.rmtree(work, ignore_errors=True)
    return t


if __name__ == "__main__":
    result = main()
    result.done()
    sys.exit(1 if result.failed else 0)
