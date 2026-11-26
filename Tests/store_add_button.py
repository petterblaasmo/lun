#!/usr/bin/env python3
"""The Chrome Web Store's own page offers "Add to Lun", and pressing it
installs — against the real store, in a hidden probe.

Build first (`./build.sh`), then `python3 Tests/store_add_button.py`
(with a path after it, a picture of the page goes there). It runs a copy of build/Lun.app under a bundle id of its own, hidden, in
a world of its own with split_view.py's harness; the copy, its WebKit
folders and the world are removed afterwards.

This one needs the network: it opens an extension's page in the store as
it is today. The store's markup is generated and changes, and the button
is put into it by a script that leans on as little of it as it can
(StoreRelay.swift): the store's own install button is the disabled one
that names Chrome, and its "Switch to Chrome" banner the block around the
enabled one that does. Run this when the store looks different, and
before a release. What is checked:

- the page gets a button that says "Add to Lun", in sight and enabled,
  with the store's own grey one hidden behind it;
- no "Switch to Chrome" button is left in sight;
- pressed, it installs the extension the tab's address names, and then
  says "Added to Lun";
- on the store's front page, which is no extension's, there is no button.

If the first fails, the page still has a way in: the "Add this extension
to Lun" pill at the foot of the window shows wherever the page's button
could not be placed (StoreOffer).
"""
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("store-add-button")
BUNDLE = "com.lunbrowser.lun.storebutton"
work = Path(tempfile.mkdtemp(prefix="search-store-button-"))

# Any small extension that will stay in the store: uBlock Origin Lite.
ID = "ddkjiahejlhfcafbddmgiahcphecmpfh"
LISTING = f"https://chromewebstore.google.com/detail/ublock-origin-lite/{ID}"
FRONT = "https://chromewebstore.google.com/category/extensions"

# The button in sight: the store keeps the pages it has left, hidden,
# beside the one it shows.
OURS = """(() => {
  const all = [...document.querySelectorAll('button[data-office="add"]')];
  const seen = all.filter((b) => { const r = b.getBoundingClientRect(); return r.width > 0 && r.height > 0; });
  const b = seen[0];
  if (!b) return JSON.stringify({ placed: all.length, seen: 0 });
  const r = b.getBoundingClientRect();
  return JSON.stringify({ placed: all.length, seen: seen.length, text: (b.innerText || '').trim(), disabled: b.disabled,
    width: Math.round(r.width), height: Math.round(r.height) });
})()"""
THEIRS = """(() => {
  const shown = (b) => { const r = b.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
  const buttons = [...document.querySelectorAll('button')].filter((b) => !b.dataset.office || b.dataset.office === 'theirs');
  return JSON.stringify({
    grey: buttons.filter((b) => b.disabled && /chrome/i.test(b.textContent || '') && shown(b)).length,
    hidden: document.querySelectorAll('button[data-office="theirs"]').length,
    switchTo: buttons.filter((b) => !b.disabled && /chrome/i.test(b.getAttribute('aria-label') || '') && shown(b)).length,
    banners: document.querySelectorAll('[data-office="banner"], [data-office="promo"]').length,
  });
})()"""

CONSENT = """(() => {
  const form = document.querySelector('form[action*="consent.google.com/save"]');
  const button = form && form.querySelector('button, input[type="submit"]');
  if (button) button.click();
  return !!button;
})()"""


def probe_copy():
    app = work / "Lun.app"
    shutil.copytree(Path(sv.ROOT, "build", "Lun.app"), app, symlinks=True)
    subprocess.run(["/usr/libexec/PlistBuddy", "-c", f"Set :CFBundleIdentifier {BUNDLE}", str(app / "Contents/Info.plist")], check=True)
    (app / "Contents/embedded.provisionprofile").unlink(missing_ok=True)
    subprocess.run(["codesign", "-f", "-s", "-", "--entitlements", str(Path(sv.ROOT, "Search.entitlements")), "--deep", str(app)],
                   check=True, capture_output=True)
    return str(app)


def read(page, js):
    import json
    try:
        got = sv.ev(page, js)
    except RuntimeError:
        return {}
    return json.loads(got) if isinstance(got, str) else {}


def until(check, within=30, every=0.5):
    end = time.time() + within
    got = check()
    while not got and time.time() < end:
        time.sleep(every)
        got = check()
    return got


def main():
    t = sv.T()
    sv.APP = probe_copy()
    try:
        sv.setup()
        sv.launch()
        page = sv.sp("open", url=LISTING)["resultID"]
        sv.cmd({"do": "wait", "id": page, "seconds": 30})
        until(lambda: sv.ev(page, "document.title") or "", within=20)
        # A browser Google hasn't seen before is asked about cookies first,
        # in some countries. Answered no, as the first of its two forms.
        if sv.ev(page, "location.hostname") == "consent.google.com":
            print("       asked about cookies first: answered no")
            sv.ev(page, CONSENT)
            until(lambda: sv.ev(page, "location.hostname") == "chromewebstore.google.com", within=30)
            sv.cmd({"do": "wait", "id": page, "seconds": 30})
        title = sv.ev(page, "document.title") or ""
        address = sv.ev(page, "location.href") or ""
        print(f"       the store answered: {title!r} at {address}")
        t.ok("the extension's page in the store opens", address.startswith("https://chromewebstore.google.com/detail/") and ID in address, address)

        ours = until(lambda: (lambda o: o if o.get("seen") else None)(read(page, OURS)), within=30) or read(page, OURS)
        print(f"       the page's button: {ours}")
        t.ok("the page has a button of Lun's, in sight", ours.get("seen") == 1, ours)
        t.ok("… that says Add to Lun", ours.get("text") == "Add to Lun", ours.get("text"))
        t.ok("… and can be pressed", ours.get("disabled") is False and ours.get("width", 0) > 40, ours)
        theirs = read(page, THEIRS)
        print(f"       the store's own: {theirs}")
        t.ok("the store's grey button is hidden behind it", theirs.get("hidden", 0) >= 1 and theirs.get("grey") == 0, theirs)
        t.ok("no Switch to Chrome is left in sight", theirs.get("switchTo") == 0, theirs)
        # A picture of the page as it stands, for a person to look at.
        if len(sys.argv) > 1:
            sv.cmd({"do": "shot", "id": page, "path": str(Path(sys.argv[1]).resolve()), "width": 1100})

        # Pressed as a person would: the usual question, answered yes.
        sv.cmd({"do": "ext-answer", "answer": "yes"})
        sv.ev(page, """(() => { const b = [...document.querySelectorAll('button[data-office="add"]')]
          .find((b) => b.getBoundingClientRect().width > 0); if (b) b.click(); return !!b; })()""")
        ext = until(lambda: next((x for x in sv.cmd({"do": "extensions"})["extensions"] if x["id"] == ID and x["loaded"]), None),
                    within=90, every=1)
        t.ok("pressed, it installs the extension the address names", ext is not None,
             sv.cmd({"do": "extensions"})["extensions"])
        if ext:
            print(f"       installed: {ext.get('name')} {ext.get('version', '')}")
        said = until(lambda: (lambda o: o if o.get("text") == "Added to Lun" else None)(read(page, OURS)), within=10) or read(page, OURS)
        t.ok("… and then says Added to Lun, and can't be pressed again",
             said.get("text") == "Added to Lun" and said.get("disabled") is True, said)

        front = sv.sp("open", url=FRONT)["resultID"]
        sv.cmd({"do": "wait", "id": front, "seconds": 30})
        time.sleep(3)
        none = read(front, OURS)
        t.ok("the store's front page, no extension's, gets no button", none.get("seen") == 0, none)
        t.ok("… and no Switch to Chrome either", read(front, THEIRS).get("switchTo") == 0, read(front, THEIRS))
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
