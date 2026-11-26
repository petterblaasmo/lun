#!/usr/bin/env python3
"""An extension with many site grants costs its scripts once, not once per
grant and tab — in a hidden probe.

Build first (`./build.sh`), then `python3 Tests/extension_memory.py`.
It runs a copy of build/Lun.app under a bundle id of its own, hidden, in
a world of its own with split_view.py's harness; the copy, its WebKit
folders and the world are removed afterwards.

WebKit hands an extension's content scripts and stylesheets to every tab
once for each granted pattern. Built against an older SDK it kept a full
copy of the text each time, so an extension with a large script and a long
list of sites took several GiB in the app's own process; built against a
current one it shares one buffer between them. Nothing in Lun switches that
on: it comes with the SDK the app is built with, and the private call that
forces it switches on every other newer WebKit behaviour too, so it is not
made. This probe is what says whether the build at hand has it.

An extension with a 2 MB script and a 1 MB stylesheet for 32 sites, with
four tabs open:

- the app's own process grows by less than 96 MiB (unshared, the copies
  alone are 32 sites x 4 tabs x 3 MB);
- the script still runs once, apart from the page, and the stylesheet
  applies, on a site it names and on no other;
- switched off, it is gone from new pages and the memory is not kept.
"""
import json
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("extension-memory")
BUNDLE = "com.lunbrowser.lun.extmemory"
work = Path(tempfile.mkdtemp(prefix="search-ext-memory-"))
LIMIT = 96

SITES = [f"https://site{i}.invalid/*" for i in range(31)] + ["http://localhost/*"]
SCRIPT = "/*" + "x" * 2_000_000 + "*/\n" + """
globalThis.memoryRuns = (globalThis.memoryRuns || 0) + 1;
document.addEventListener('DOMContentLoaded', () => {
  document.documentElement.dataset.memoryRuns = String(memoryRuns);
  document.documentElement.dataset.memoryId = chrome.runtime.id;
});
"""
STYLE = "/*" + "x" * 1_000_000 + "*/\nbody { --memory-probe: yes; }"


def probe_copy():
    app = work / "Lun.app"
    shutil.copytree(Path(sv.ROOT, "build", "Lun.app"), app, symlinks=True)
    subprocess.run(["/usr/libexec/PlistBuddy", "-c", f"Set :CFBundleIdentifier {BUNDLE}", str(app / "Contents/Info.plist")], check=True)
    (app / "Contents/embedded.provisionprofile").unlink(missing_ok=True)
    subprocess.run(["codesign", "-f", "-s", "-", "--entitlements", str(Path(sv.ROOT, "Search.entitlements")), "--deep", str(app)],
                   check=True, capture_output=True)
    return str(app)


def footprint():
    """The app's own process, in MiB: where the copies were kept."""
    pid, = sv.pids()
    out = subprocess.run(["vmmap", "-summary", pid], capture_output=True, text=True).stdout
    value, unit = re.search(r"^Physical footprint:\s*([\d.]+)([KMG])", out, re.M).groups()
    return float(value) * {"K": 1 / 1024, "M": 1, "G": 1024}[unit]


def settled(loaded, within=20):
    """The one extension, once it is loaded or not as asked."""
    end = time.time() + within
    while time.time() < end:
        found = sv.cmd({"do": "extensions"})["extensions"]
        if len(found) == 1 and found[0]["loaded"] == loaded:
            return found[0]
        time.sleep(0.2)
    return None


def main():
    t = sv.T()
    sv.APP = probe_copy()
    folder = work / "ext"
    folder.mkdir()
    (folder / "manifest.json").write_text(json.dumps({
        "manifest_version": 3, "name": "Memory", "version": "1.0",
        "host_permissions": SITES,
        "content_scripts": [{"matches": SITES, "js": ["content.js"], "css": ["content.css"], "run_at": "document_start"}],
    }))
    (folder / "content.js").write_text(SCRIPT)
    (folder / "content.css").write_text(STYLE)
    try:
        sv.setup()
        sv.launch()
        first = [x["id"] for x in sv.cmd({"do": "tabs"})["tabs"]]
        pages = [sv.page(f"memory-{i}") for i in range(4)]
        for id in first:
            try: sv.sp("close", id=id)
            except RuntimeError: pass
        time.sleep(3)
        before = footprint()
        sv.cmd({"do": "ext-folder", "path": str(folder), "yes": True})
        ext = settled(True)
        t.ok("the extension with 32 sites loads", ext is not None)
        if not ext:
            return t
        time.sleep(4)
        after = footprint()
        print(f"       the app's own process: {before:.0f} -> {after:.0f} MiB")
        t.ok(f"32 sites in four tabs cost less than {LIMIT} MiB", after - before < LIMIT, f"{after - before:.0f} MiB")
        t.ok("a page it doesn't name gets no script",
             all(sv.ev(p, "document.documentElement.dataset.memoryRuns || ''") == "" for p in pages))

        named = sv.BASE.replace("127.0.0.1", "localhost") + "/named"
        page = sv.sp("open", url=named)["resultID"]
        sv.cmd({"do": "wait", "id": page, "seconds": 10})
        t.ok("on a site it names the script runs once, as the extension's",
             sv.ev(page, "document.documentElement.dataset.memoryRuns") == "1"
             and sv.ev(page, "document.documentElement.dataset.memoryId") == ext["id"],
             sv.ev(page, "JSON.stringify(document.documentElement.dataset)"))
        t.ok("… apart from the page", sv.ev(page, "typeof memoryRuns") == "undefined")
        t.ok("… and its stylesheet applies",
             sv.ev(page, "getComputedStyle(document.body).getPropertyValue('--memory-probe').trim()") == "yes")
        sv.sp("close", id=page)

        sv.cmd({"do": "ext-enable", "id": ext["id"], "on": False})
        t.ok("switched off, it unloads", settled(False) is not None)
        time.sleep(2)
        off = footprint()
        print(f"       switched off: {off:.0f} MiB")
        t.ok("… and keeps no copies", off - before < LIMIT, f"{off - before:.0f} MiB")
        page = sv.sp("open", url=named)["resultID"]
        sv.cmd({"do": "wait", "id": page, "seconds": 10})
        t.ok("… and a new page gets neither script nor stylesheet",
             sv.ev(page, "document.documentElement.dataset.memoryRuns || ''") == ""
             and sv.ev(page, "getComputedStyle(document.body).getPropertyValue('--memory-probe').trim()") == "")
    finally:
        sv.finish()
        for kind in ("WebKit", "Caches", "HTTPStorages"):
            shutil.rmtree(Path.home() / "Library" / kind / BUNDLE, ignore_errors=True)
        shutil.rmtree(work, ignore_errors=True)
    return t


if __name__ == "__main__":
    t = main()
    t.done()
    sys.exit(1 if t.failed else 0)
