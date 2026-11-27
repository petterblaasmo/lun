# lunbrowser.com

The landing page for Lun. Static files, no build step and nothing to install.

| File | What it is |
|---|---|
| `index.html` | The whole page: markup, styles and script inline |
| `images/` | Screenshots of Lun, copied from `docs/images/`. `hero-light.png` is the picture shown when the site is shared |
| `favicon.svg` | The small Lun icon |

## The idea

Warm paper, flat fjord scenes, and Lun's own interface drawn in HTML, so every picture of the browser on the page is live.

- **The bar at the bottom** is the only navigation. It marks the section you are in and how far through it you are, shrinks to an address pill (`lunbrowser.com/features`) while you scroll down, and comes back when you scroll up or point at it. The search button, or ⌘K, opens it into a list of sections you can filter, with the light and dark switch. In the features section it grows a pair of arrows that step through the features.
- **The hero window** works: a cursor clicks through its tabs, and so can the visitor.
- **Features** are a column of tabs beside one page, the way Lun is laid out. Each tab plays its own small demo.
- **Make it yours** is a small Settings card that drives a window: where the tabs go, the space colour, light or dark, pins.
- **Everything** is the long list with a field that filters it.

Every moving part stops for visitors who ask for reduced motion, and the page reads in full without it.

## Putting it online

Serve this folder from any static host and point `lunbrowser.com` at it.

## With each release

The page states a few facts by hand. Update them when they change:

- **Version, size and requirements**: at the top right, under the hero buttons, in the three facts under Private, in Questions, under Open source and in the closing card.
- **Latest releases** and **Not yet**: under Open source, shortened from `CHANGELOG.md` and the README.
- **The long list**: under Everything. The number beside the filter field counts the rows by itself.
- **Screenshots**: copy `docs/images/*.png` over `site/images/` when they are retaken.

The Download buttons need no change: they link to `releases/latest/download/Lun.dmg`, which always serves the newest release.

## Editing

Colours and motion are the tokens at the top of the `<style>` block, light and dark. The drawn windows use the app's palette.
