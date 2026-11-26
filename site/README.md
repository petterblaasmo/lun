# lunbrowser.com

The landing page for Lun. One static file, no build step and nothing to install.

| File | What it is |
|---|---|
| `index.html` | The whole page: markup, styles and script inline |
| `favicon.svg` | The small Lun icon |

## Putting it online

Serve this folder from any static host and point `lunbrowser.com` at it.

## Before it goes live

- **Download.** Every Download button links to `https://github.com/petterblaasmo/lun/releases/latest`. Publish a release there first, or change the links (search for `data-download`).
- **Repository links.** The page links to the repository, its changelog, licence and README. They only work for visitors if the repository is public.
- **Latest changes.** The three rows under Open source are copied from `CHANGELOG.md` by hand. Update them when it changes.

## Editing

Colours, type and motion are the tokens at the top of the `<style>` block, light and dark. The browser windows on the page are drawn in HTML and CSS, so they stay sharp at any size.
