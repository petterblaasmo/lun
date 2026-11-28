#!/usr/bin/env python3
"""Another browser's sign-ins, brought into a hidden probe and sent to a page.

Build first (`./build.sh debug`), then, hidden and under the probe lock:
`lockf -t 900 /private/tmp/claude-501/search-probe.lock python3 Tests/import_sign_ins.py`.

Made-up Chrome and Arc profiles go in this world's own Import/ folder (see
Chromium.base): a "Cookies" each as Chromium writes it on the Mac (file
version 24: v10, AES-128-CBC, the SHA-256 of the host before each value, a
key stretched from the profile's own "Safe Storage" file, which a test run
reads instead of the keychain). Never a real browser's files, never the
real keychain.

A local page on 127.0.0.1 answers with the Cookie header it was sent, so
what came over is seen where it matters: on the request. No window is made
or shown.
"""
import hashlib
import sqlite3
import subprocess
import sys
import threading
import time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("import-sign-ins")


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        body = f"<!doctype html><title>sent</title><p id=sent>{self.headers.get('Cookie', '')}</p>".encode()
        self.send_response(200); self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)

    def log_message(self, *a): pass


def wrapped(value, host, passphrase):
    """v10 + AES-128-CBC under sixteen spaces, the host's hash first."""
    key = hashlib.pbkdf2_hmac("sha1", passphrase.encode(), b"saltysalt", 1003, 16)
    plain = hashlib.sha256(host.encode()).digest() + value.encode()
    out = subprocess.run(["openssl", "enc", "-aes-128-cbc", "-K", key.hex(), "-iv", "20" * 16],
                         input=plain, capture_output=True, check=True).stdout
    return b"v10" + out


def chromium_cookies(root, passphrase, rows, wrapped_with=None):
    """A browser folder with one profile, "Default", and its Network/Cookies.
    A row: host, name, value, seconds from now (None: ends with the session),
    http-only, and the host its value is hashed for when not its own."""
    profile = Path(root) / "Default"
    (profile / "Network").mkdir(parents=True, exist_ok=True)
    (Path(root) / "Safe Storage").write_text(passphrase)
    (profile / "Bookmarks").write_text("{}")
    db = sqlite3.connect(profile / "Network" / "Cookies")
    db.execute("CREATE TABLE meta(key LONGVARCHAR NOT NULL UNIQUE PRIMARY KEY, value LONGVARCHAR)")
    db.execute("INSERT INTO meta VALUES ('version', '24'), ('last_compatible_version', '24')")
    # Chromium's own table (CreateV24Schema).
    db.execute("""CREATE TABLE cookies(creation_utc INTEGER NOT NULL, host_key TEXT NOT NULL,
        top_frame_site_key TEXT NOT NULL, name TEXT NOT NULL, value TEXT NOT NULL, encrypted_value BLOB NOT NULL,
        path TEXT NOT NULL, expires_utc INTEGER NOT NULL, is_secure INTEGER NOT NULL, is_httponly INTEGER NOT NULL,
        last_access_utc INTEGER NOT NULL, has_expires INTEGER NOT NULL, is_persistent INTEGER NOT NULL,
        priority INTEGER NOT NULL, samesite INTEGER NOT NULL, source_scheme INTEGER NOT NULL,
        source_port INTEGER NOT NULL, last_update_utc INTEGER NOT NULL, source_type INTEGER NOT NULL,
        has_cross_site_ancestor INTEGER NOT NULL)""")
    for index, (host, name, value, lasts, http_only, hashed_for) in enumerate(rows):
        # Microseconds since 1601.
        expires = 0 if lasts is None else int((time.time() + lasts + 11_644_473_600) * 1_000_000)
        blob = wrapped(value, hashed_for or host, wrapped_with or passphrase)
        db.execute("INSERT INTO cookies VALUES (?, ?, '', ?, '', ?, '/', ?, 0, ?, 0, ?, ?, 1, -1, 1, 80, 0, 1, 0)",
                   (index + 1, host, name, blob, expires, int(http_only), int(lasts is not None), int(lasts is not None)))
    db.commit(); db.close()


def main():
    t = sv.T()
    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    page = f"http://127.0.0.1:{srv.server_port}/"
    try:
        sv.setup()
        imp = Path(sv.SUPPORT) / "Import"
        month = 30 * 86400
        chromium_cookies(imp / "Google/Chrome", "chrome-key", [
            ("127.0.0.1", "seen", "by-the-page", month, False, None),
            ("127.0.0.1", "kept", "from-scripts", month, True, None),
            ("127.0.0.1", "old", "expired", -60, False, None),
            ("127.0.0.1", "tab", "session", None, False, None),
            ("127.0.0.1", "moved", "another-hosts", month, False, "elsewhere.example"),
            ("elsewhere.example", "other", "not-this-hosts", month, False, None),
        ])
        # Arc's were wrapped with a key that isn't the one it hands over.
        chromium_cookies(imp / "Arc/User Data", "arc-key", [
            ("127.0.0.1", "locked", "never-read", month, False, None),
            ("127.0.0.1", "shut", "never-read", month, True, None),
        ], wrapped_with="a-key-from-before")
        sv.launch()

        tab = sv.sp("open", url=page)["resultID"]; time.sleep(1.2)
        t.ok("nothing is sent before", sv.ev(tab, "document.getElementById('sent').textContent") == "")
        t.ok("counting asked for no key", sv.cmd({"do": "import-preview"}).get("keyAskedEver") == 0)

        out = sv.cmd({"do": "import", "from": "Arc", "what": ["signins"]}).get("signins")
        t.ok("a key that opens nothing brings nothing, and says how many", out == {"cookies": 0, "session": 0, "partitioned": 0, "unread": 2}, out)

        out = sv.cmd({"do": "import", "from": "Chrome", "what": ["signins"]}).get("signins")
        t.ok("Chrome's came: three, one session cookie left, one not its host's", out == {"cookies": 3, "session": 1, "partitioned": 0, "unread": 1}, out)
        t.ok("each key asked for once", sv.cmd({"do": "import-preview"}).get("keyAskedEver") == 2)

        sv.cmd({"do": "go", "id": tab, "url": page}); time.sleep(1.2)
        sent = sv.ev(tab, "document.getElementById('sent').textContent") or ""
        names = sorted(pair.split("=")[0] for pair in sent.split("; ") if pair)
        t.ok("the page's request carries them, the http-only one too", names == ["kept", "seen"], names)
        script = sv.ev(tab, "document.cookie") or ""
        t.ok("a script sees only the one it may", [pair.split("=")[0] for pair in script.split("; ") if pair] == ["seen"])
    finally:
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
