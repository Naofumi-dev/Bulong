# Bulong marketing site

Static landing page + privacy page for **bulong.app**. Hand-written HTML/CSS/JS —
no framework, no build step. The mint-on-ink brand mirrors the app.

```
site/
  index.html      landing (long scroll)
  privacy.html    privacy page
  styles.css      Bulong tokens (:root) + all section styles
  main.js         mobile-nav toggle only (progressive enhancement)
  robots.txt      allow all + sitemap
  sitemap.xml     the two page URLs
  assets/         icon.png, og.png, and the app render crops
```

## Preview locally

```sh
python3 -m http.server 8000 --directory site
# then open http://localhost:8000/index.html
```

No server-side anything — any static file server works.

## Changing the price

The price string lives in **exactly three** `data-price` spans in `index.html`
(hero, pricing card, final CTA). To change $29, update **all three**:

```sh
grep -n 'data-price' site/index.html   # shows the 3 lines to edit
```

There is no other source of the price — it is not generated from CSS.

## Placeholder links to wire later

These are intentional placeholders for this phase (distribution/licensing land
in later sub-projects). Search and replace when the real endpoints exist:

| Placeholder | Where | Wire to |
|---|---|---|
| `#download` | nav, hero, pricing, final CTA (all "Download" CTAs) | the notarized DMG URL. Currently `#download` also serves as the final-CTA section id, so the buttons smooth-scroll there until the real URL is set. |
| checkout | the "Download for macOS" buttons (same anchors) | the Lemon Squeezy checkout URL, if buy and download are split |
| `hello@bulong.app` | footer Contact, privacy page Contact | the real support/privacy inbox |

## Regenerating the OG image

`assets/og.png` (1200×630) is a committed static asset rendered once by a
CoreGraphics script (mirrors `script/render_icon.swift`):

```sh
swift script/render_og.swift   # run from the repo root; writes site/assets/og.png
```

## Deploy

Upload the **contents of `site/`** to Hostinger's `public_html` for bulong.app
(or use the Hostinger hosting tools with your authorization). Then point the
domain — DNS/purchase is not automated here; do that step yourself.

## Notes

- All theme values are CSS custom properties in `:root` (`styles.css`) — a
  colour or price change is one place.
- Every comparison-table and feature claim is true of the shipping app today
  (on-device Parakeet + Whisper, any-app paste, push-to-talk/toggle, custom
  hotkey, local searchable history, 25+ languages incl. Filipino, translate to
  English, clipboard preservation). No custom vocabulary, no cloud AI, no tiers.
- The hero HUD is a CSS/HTML recreation (crisp + animatable); its orb/waveform
  animation stops under `prefers-reduced-motion: reduce`.
- The two-page nav/footer chrome is duplicated markup by design. A third page
  should motivate a shared include.
