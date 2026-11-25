# Lun

A small, fast, quiet browser for the Mac. *Lun* is Norwegian for warm and sheltered.

Early days: there is nothing to download yet, and the app still shows Search's name and icon.

## What it is

Tabs down the left or across the top, and the page. It runs on WebKit, the engine already in every Mac, so it stays small and opens fast. No account and no telemetry.

- Vertical tabs, spaces, pins and split view
- Built-in ad blocker, reading mode and floating video
- Passwords in the macOS keychain
- Chrome extensions on WebKit's own extension engine (macOS 15.4 or later)

## Not yet

| | Needs |
|---|---|
| Updates | A site to serve them from |
| Passkeys and iCloud sync | An Apple provisioning profile |
| Developer tools packages | The update feed |

## Building it

macOS 14 or later, and Xcode with Swift 6.

| | |
|---|---|
| `swift build` | Debug build |
| `./build.sh` | A double-clickable app in `build/` |
| `SEARCH_DEV=1 ./build.sh` | The same with a yellow icon, named for the branch |
| `./fresh.sh` | Opens the app in a test world, apart from your own data |
| `swift test` | Unit tests |
| `./bench` | Drives a running app from the shell |

Internal names (`Sources/Search`, `SEARCH_*`) are kept on purpose: it keeps Search's updates easy to merge.

## Where your data is

| What | Where |
|---|---|
| Passwords | The macOS keychain, tagged `Lun` |
| History, bookmarks, tabs | `~/Library/Application Support/Lun/` |
| Cookies and site data | WebKit's store for the app |

## Credit and license

Lun is built on [Search](https://github.com/driceroland/Search) by Office Commun and its contributors. It is not made or endorsed by them.

MIT, see [LICENSE](LICENSE). Third-party parts are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
