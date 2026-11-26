# Contributing to Lun

Thank you for looking. Lun is small on purpose, and most of the work is in keeping it that way.

## Reporting a bug or an idea

Open an [issue](https://github.com/petterblaasmo/lun/issues/new/choose). For a bug, say what you did, what you expected and what happened, with the version from Lun › About. Send Feedback in the app opens a draft with the version already filled in.

Security problems go through [SECURITY.md](SECURITY.md), not an issue.

## Building and running

macOS 14 or later, and Xcode with Swift 6.

| | |
|---|---|
| `swift build` | Debug build |
| `./build.sh` | A double-clickable app in `build/` |
| `./fresh.sh` | Opens the app in a test world, apart from your own data |
| `swift test --filter "SearchTests\.Name"` | One test class |

A build of your own is signed ad hoc: passkeys and iCloud sync need Apple's provisioning and stay off.

## Tests

- Unit tests are in `Tests/SearchTests`. The whole suite takes about fifteen minutes; run the classes near what you changed, and say which in the pull request.
- Scripts in `Tests/*.py` drive a hidden copy of the app through `./bench`: nothing appears on screen and your own data is not touched. Build first, then `python3 Tests/<name>.py`.
- A few tests are known to fail or to depend on the order they run in; they are listed in [issue 98](https://github.com/petterblaasmo/lun/issues/98). A pull request need not fix them, and should not add to them.

## Pull requests

- One change per pull request, on a branch of its own, from `main`.
- Small commits, in the form `feat:`, `fix:`, `refactor:`, `docs:`, `test:` or `chore:`, saying what changed and why.
- If something visible changes, add a picture, before and after, light and dark.
- Say how you checked it. "Not tried by hand" is a fine thing to say when it is true.

## How the code wants to be written

- Colours, sizes, corners, shadows and motion come from `Sources/Search/Design.swift`: `Palette`, `Metrics`, `Radius`, `Elevation` (`.elevated`), `Motion`. No animation is written outside `Motion`, no shadow outside the elevations, and tests hold both.
- A button gives under a press (`Gives`) and answers the pointer (`.hovers`). Text is 12 points or more.
- A setting has to earn its place. Settings is 74 rows; a new behaviour is first a decision, and a switch only if people really differ. Switches that were retired are in `RetiredSettings.swift`.
- Comments say why, not what.

## Licence

By contributing you agree that your contribution is under the [MIT licence](LICENSE), as the rest of Lun is.
