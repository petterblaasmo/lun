# lunbrowser.com

The landing page for Lun. Static files, no build step and nothing to install.

| File | What it is |
|---|---|
| `index.html` | The whole page: markup, styles and script inline |
| `images/` | Screenshots of Lun, light and dark, copied from `docs/images/` |
| `favicon.svg` | The small Lun icon |

## The idea

Lun is Norwegian for warm and sheltered, so the page is a cold night with one warm place in it.

- **Outside.** A night sky behind everything: falling snow, mountains that shift as you scroll and move the pointer, and northern lights that come up as the page goes on. The pointer carries a lantern that warms the snow near it.
- **The window.** One drawn Lun window stays on screen while the page scrolls past it, and changes with each part: a cursor works its tabs, a new tab card types a search, the page splits in two, the spaces change colour, and the tabs move left, top, to icons and right. A visitor can click the tabs, the spaces and the layouts themselves.
- **The rest.** Tiles a visitor can operate: flip the ad blocker, drag the floating video between corners, peek at a link, wake a sleeping tab, press a key, show a password with Touch ID.
- **Inside.** The page ends on warm paper: real screenshots, questions, the open source notes and the download.

Every moving part stops for visitors who ask for reduced motion, and the page reads in full without it.

## Putting it online

Serve this folder from any static host and point `lunbrowser.com` at it.

## With each release

The page states a few facts by hand. Update them when they change:

- **Version, size and requirements**: under the hero buttons, in "Quiet by nature", in the questions, in the open source note and in the closing block.
- **Latest releases** and **Not yet**: in the closing section, shortened from `CHANGELOG.md` and the README.
- **Screenshots**: copy `docs/images/*.png` over `site/images/` when they are retaken. The page shows the light ones.

The Download buttons need no change: they link to `releases/latest/download/Lun.dmg`, which always serves the newest release.

## Editing

Colours and motion are the tokens at the top of the `<style>` block. The drawn window uses the app's palette; the night around it is the site's own.
