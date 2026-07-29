# Bulong marketing site

Static marketing site for **bulong.app**. Hand-written HTML/CSS/JS — no
framework and no build step. The light-glass brand mirrors the app.

```
site/
  index.html      landing (long scroll)
  download.html   launch-list now; download/install page when body is dl-live
  privacy.html    privacy explanation
  guides/         search-focused educational and comparison pages
  styles.css      Bulong tokens (:root) + all section styles
  main.js         nav, progressive reveals, lazy demo, and lead form
  robots.txt      allow all + sitemap
  sitemap.xml     canonical public URLs
  vercel.json     canonical redirect and response headers
  assets/         product media, self-hosted font, and optimized web assets
```

## Preview locally

```sh
python3 -m http.server 8000 --directory site
# then open http://localhost:8000/
```

No server-side anything — any static file server works.

## Changing the price

The price string appears in `data-price` spans on the landing and launch pages.
To change $29, update every matching span:

```sh
grep -R -n 'data-price' site/*.html
```

There is no other source of the price — it is not generated from CSS.

## Pre-launch to live

The public site is honest about the current pre-launch state. Primary calls to
action point to `download.html#notify`. When the app is ready:

1. Change `<body class="dl-soon">` to `<body class="dl-live">`.
2. Replace each `DMG-URL` placeholder with the notarized download.
3. Replace each `BUY-URL` placeholder with the checkout.
4. Change homepage CTAs from launch notification to download.
5. Update the `SoftwareApplication` offer availability from `PreOrder` to
   `InStock`.

## Regenerating the OG image

`assets/og.png` (1200×630) is a committed static asset rendered once by a
CoreGraphics script (mirrors `script/render_icon.swift`):

```sh
swift script/render_og.swift   # run from the repo root; writes site/assets/og.png
```

## Deploy

The directory is linked to the Vercel project recorded in
`site/.vercel/project.json`. Deploy the **contents of `site/`**. Configure
`www.bulong.app` as a permanent redirect to `bulong.app` in the project domain
settings so both hosts do not serve duplicate 200 responses.

## Notes

- All theme values are CSS custom properties in `:root` (`styles.css`) — a
  colour or price change is one place.
- Every comparison-table and feature claim is true of the shipping app today
  (on-device Parakeet + Whisper, any-app paste, push-to-talk/toggle, custom
  hotkey, local searchable history, 10 languages incl. Filipino, translate to
  English, clipboard preservation). No custom vocabulary, no cloud AI, no tiers.
- The hero HUD is a CSS/HTML recreation (crisp + animatable); its orb/waveform
  animation stops under `prefers-reduced-motion: reduce`.
- Nav/footer chrome is duplicated markup because the site has no build step.
  Keep canonical links and guide navigation synchronized when adding a page.
