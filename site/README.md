# lunbrowser.com

The landing page for Lun. One static file, no build step and nothing to install.

| File | What it is |
|---|---|
| `index.html` | The whole page: markup, styles and script inline |
| `favicon.svg` | The small Lun icon |

## Putting it online

Serve this folder from any static host and point `lunbrowser.com` at it.

## With each release

The page states a few facts by hand. Update them when they change:

- **Version and size**: the pill above the headline, the line under the hero buttons, the "8 MB" in the hero and in the Fast and light section, and the footer card.
- **Latest releases**: the rows under Open source, shortened from `CHANGELOG.md`.
- **Requirements**: "Apple silicon" and "macOS 14 or later", in the hero, the questions and the footer.

The Download buttons need no change: they link to `releases/latest/download/Lun.dmg`, which always serves the newest release.

## Editing

Colours, type and motion are the tokens at the top of the `<style>` block, light and dark. The browser windows on the page are drawn in HTML and CSS, so they stay sharp at any size.
