# Lun

A small, fast, quiet browser for the Mac. *Lun* is Norwegian for warm and sheltered.

## Download

The newest release is on the [Releases page](https://github.com/petterblaasmo/lun/releases/latest): open `Lun.dmg` and drag Lun to Applications. Apple silicon, macOS 14 or later. Lun keeps itself up to date from there.

It is early: version 0.1.0. Expect rough edges, and [say what you find](https://github.com/petterblaasmo/lun/issues/new/choose).

## What it is

Tabs down the left or across the top, and the page. It runs on WebKit, the engine already in every Mac, so it stays small and opens fast. No account and no telemetry.

- Vertical tabs, spaces, pins and split view
- Built-in ad blocker, reading mode and floating video
- Passwords in the macOS keychain
- Chrome extensions on WebKit's own extension engine (macOS 15.4 or later)

## Not yet

| | Needs |
|---|---|
| Intel Macs | A second build; for now, build it yourself |
| Passkeys and iCloud sync | An Apple provisioning profile, which a build of your own does not have |

## Building it

macOS 14 or later, and Xcode with Swift 6.

| | |
|---|---|
| `swift build` | Debug build |
| `./build.sh` | A double-clickable app in `build/` |
| `SEARCH_DEV=1 ./build.sh` | The same with a yellow icon, named for the branch |
| `./fresh.sh` | Opens the app in a test world, apart from your own data |
| `swift test` | Unit tests |
| `./release.sh --try` | The release files, unnotarised, nothing uploaded |
| `./bench` | Drives a running app from the shell |

## Where your data is

| What | Where |
|---|---|
| Passwords | The macOS keychain, tagged `Lun` |
| History, bookmarks, tabs | `~/Library/Application Support/Lun/` |
| Cookies and site data | WebKit's store for the app |

## Contributing

Bugs, ideas and pull requests are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md). For a security problem, see [SECURITY.md](SECURITY.md) instead of opening an issue.

## License

MIT, see [LICENSE](LICENSE). Third-party parts are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
