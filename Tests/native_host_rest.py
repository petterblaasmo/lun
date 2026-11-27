#!/usr/bin/env python3
"""A host that keeps turning the browser away is not started again and
again, in a hidden probe (#134).

Build first (`./build.sh debug`), then `python3 Tests/native_host_rest.py`.
It runs a copy of build/Lun.app under a bundle id of its own, in a world of
its own with split_view.py's harness, started hidden; the copy, its WebKit
folders and the world are removed afterwards.

1Password's helper checks which browser is calling and ends at once with
status 1 for one it doesn't know; its extension asks again, and Lun started
a process every few seconds (about 500 an hour). Here an extension's worker
connects to a host of the probe's own that does the same, and connects
again a moment after each disconnect. Over `WATCH` seconds:

- the host is started three times, then not again (HostRest: a rest of 30 s
  after three quick, silent ends in a row);
- the worker keeps being told the host has exited, many times, without a
  process behind each answer.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("native-host-rest")
BUNDLE = "com.lunbrowser.lun.nativehostrest"
HOST = "com.lunbrowser.lun.probe.refuser"
WATCH = int(os.environ.get("WATCH", "20"))
work = Path(tempfile.mkdtemp(prefix="search-nativehostrest-"))
log = work / "host.log"

# The host: notes that it started and ends at once, as a helper that turns
# an unknown browser away does.
HOST_SCRIPT = f"""#!/usr/bin/python3 -I
import json, os, sys, time
with open({str(log)!r}, "a") as f: f.write(json.dumps({{"pid": os.getpid(), "t": time.time()}}) + "\\n")
sys.exit(1)
"""

FILES = {
    "manifest.json": json.dumps({
        "manifest_version": 3, "name": "NativeRest", "version": "1.0",
        "background": {"service_worker": "bg.js"},
        "permissions": ["storage", "nativeMessaging"],
    }),
    # Asked by a page of its own ("go"), connects, and connects again 300 ms
    # after every disconnect, counting them.
    "bg.js": f"""
let gone = 0, going = false;
function connect() {{
  const port = chrome.runtime.connectNative({HOST!r});
  port.onDisconnect.addListener(() => {{
    gone += 1;
    chrome.storage.local.set({{ gone }});
    setTimeout(connect, 300);
  }});
}}
chrome.runtime.onMessage.addListener((m, s, reply) => {{
  if (m === "go" && !going) {{ going = true; connect(); }}
  reply(true);
}});
""",
    "page.html": "<!doctype html><p>page</p>",
}


def probe_copy():
    """build/Lun.app under a bundle id of its own, signed ad hoc."""
    app = work / "Lun.app"
    shutil.copytree(Path(sv.ROOT, "build", "Lun.app"), app, symlinks=True)
    subprocess.run(["/usr/libexec/PlistBuddy", "-c", f"Set :CFBundleIdentifier {BUNDLE}", str(app / "Contents/Info.plist")], check=True)
    (app / "Contents/embedded.provisionprofile").unlink(missing_ok=True)
    subprocess.run(["codesign", "-f", "-s", "-", "--entitlements", str(Path(sv.ROOT, "Search.entitlements")), "--deep", str(app)],
                   check=True, capture_output=True)
    return str(app)


def stored(tid):
    key = f"__r{int(time.time() * 1000)}"
    sv.ev(tid, f"window.{key}=null;chrome.storage.local.get(null).then(v=>window.{key}=JSON.stringify(v));1")
    for _ in range(20):
        value = sv.ev(tid, f"window.{key}")
        if value:
            return json.loads(value)
        time.sleep(0.25)
    return {}


def opened(ext_id):
    """A page of the extension's own, once its chrome.runtime is there."""
    tid = sv.cmd({"do": "ext-page", "id": ext_id, "path": "page.html"})["id"]
    for _ in range(40):
        try:
            if sv.ev(tid, "typeof chrome !== 'undefined' && !!chrome.runtime && document.readyState === 'complete'"):
                return tid
        except RuntimeError:
            pass
        time.sleep(0.25)
    return tid


def starts():
    if not log.exists():
        return []
    return [json.loads(line) for line in log.read_text().splitlines() if line.strip()]


def main():
    t = sv.T()
    folder = work / "ext"
    folder.mkdir()
    for name, body in FILES.items():
        (folder / name).write_text(body)
    program = work / "host.py"
    program.write_text(HOST_SCRIPT)
    program.chmod(0o755)
    sv.APP = probe_copy()
    hosts = Path(sv.SUPPORT) / "NativeMessagingHosts"
    try:
        sv.setup()
        hosts.mkdir(parents=True, exist_ok=True)
        sv.launch()
        sv.cmd({"do": "ext-folder", "path": str(folder), "yes": True})
        ext = None
        for _ in range(60):
            ext = next((x for x in sv.cmd({"do": "extensions"})["extensions"] if x["name"] == "NativeRest" and x["loaded"]), None)
            if ext:
                break
            time.sleep(0.25)
        t.ok("the extension loads", ext is not None)
        if not ext:
            return t
        (hosts / f"{HOST}.json").write_text(json.dumps({
            "name": HOST, "description": "probe", "path": str(program), "type": "stdio",
            "allowed_origins": [f"chrome-extension://{ext['id']}/"],
        }))
        page = opened(ext["id"])
        sv.ev(page, "chrome.runtime.sendMessage('go').catch(() => {});1")
        time.sleep(WATCH)
        ran = starts()
        told = stored(opened(ext["id"])).get("gone", 0)
        t.ok("the host turned the extension away three times", len(ran) >= 3, ran)
        t.ok(f"and was not started again in {WATCH} s", len(ran) == 3, f"{len(ran)} starts")
        t.ok("the worker was told the host had exited many more times", told >= 3 * len(ran), f"{told} disconnects, {len(ran)} starts")
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
