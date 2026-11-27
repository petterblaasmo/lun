# lunbrowser.com

The landing page for Lun. Static files, no build step and nothing to install.

| File | What it is |
|---|---|
| `index.html` | The whole page: markup, styles and script inline |
| `images/` | Screenshots of Lun, light and dark, copied from `docs/images/` |
| `favicon.svg` | The small Lun icon |

## The idea

The site is laid out as Lun is: a column of tabs beside one page card. The tabs are the page's sections, and the controls in the page restyle the site itself: move the tabs left, right, to the top or to icons, give the space a colour, switch light and dark, and split the page in two. A visitor's choices are kept in their browser.

## Putting it online

Serve this folder from any static host and point `lunbrowser.com` at it.

## With each release

The page states a few facts by hand. Update them when they change:

- **Version, size and requirements**: under the hero buttons, in the three facts, in Questions, under Open source and in the closing block.
- **Latest releases** and **Not yet**: under Open source, shortened from `CHANGELOG.md` and the README.
- **Screenshots**: copy `docs/images/*.png` over `site/images/` when they are retaken.

The Download buttons need no change: they link to `releases/latest/download/Lun.dmg`, which always serves the newest release.

## Editing

Colours and motion are the tokens at the top of the `<style>` block, light and dark, and match the app's palette.
