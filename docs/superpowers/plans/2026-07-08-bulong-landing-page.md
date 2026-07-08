# Bulong Landing Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the static bulong.app marketing site (landing + privacy page) per `docs/superpowers/specs/2026-07-08-bulong-landing-page-design.md`.

**Architecture:** One self-contained static site under `site/` — hand-written semantic HTML, one shared `styles.css` (Bulong tokens as CSS custom properties), one tiny `main.js` (mobile-nav toggle + smooth scroll). No framework, no build step. The mint-on-ink brand mirrors the app; the hero HUD is a CSS/HTML recreation. Download/checkout are single-source placeholders wired later.

**Tech Stack:** HTML5, CSS (custom properties, fl/grid, `@media`), vanilla JS, system font stack (no web fonts). CoreGraphics/Swift for the one-off OG image. Verified with a local static server + Claude Preview screenshots and a better-design `get-review-rules` pass.

**Ground rules (every task):**
- All theme values are CSS custom properties in `:root` (Task 1). No hardcoded hex in section markup — reference `var(--…)`.
- Copy is the exact shipping copy from the spec's "Landing page — sections and copy" and "Privacy page" sections. No lorem, no "TODO".
- Every image has `alt` (`alt=""` if decorative). Every icon-only control has `aria-label`. One `<h1>` per page, ordered headings.
- Motion via CSS transitions; any looping/entrance animation is wrapped in `@media (prefers-reduced-motion: no-preference)` OR disabled under `reduce`.
- The single price string lives in one place (a `data-price` span / one CSS-content var); changing $29 is one edit.
- Preview command (referenced as PREVIEW below): run a background static server from the repo root — `python3 -m http.server 8000 --directory site` — then screenshot `http://localhost:8000/index.html` (and `/privacy.html`) via the Claude Preview MCP or `mcp__Claude_Preview__preview_screenshot`.

---

## File structure

```
site/
  index.html          landing (long scroll)
  privacy.html        deep privacy page
  styles.css          tokens + reset + primitives + all section styles
  main.js             mobile-nav toggle + smooth scroll (progressive enhancement)
  README.md           preview, deploy, and where the placeholders live
  assets/
    icon.png          copied app icon (favicon + nav logo)
    og.png            1200x630 social image (generated once)
    history.png, popover.png, settings.png, hud.png   app render crops
script/render_og.swift  one-off CoreGraphics script that writes site/assets/og.png
.claude/launch.json     static-server config so Claude Preview can screenshot the site
```

`site/` is committed to the app repo (same repo, separate folder). The `.build/`, `dist/` app-ignore rules don't touch it. Do NOT run `git add -A` (repo root has untracked `weave_test_recording_*.mp3`); add explicit paths.

---

### Task 1: Scaffold + design-token stylesheet + preview harness

**Files:**
- Create: `site/index.html` (skeleton), `site/styles.css`, `site/main.js`, `site/assets/` (copied images), `.claude/launch.json`

- [ ] **Step 1: Create the directory and copy assets**

```bash
cd /Users/armageddonvivas/Documents/Codex/2026-07-05/hey-codex-i-want-to-create/outputs/LocalTalk
mkdir -p site/assets
cp LocalTalk/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png site/assets/icon.png
R="/private/tmp/claude-501/-Users-armageddonvivas-Documents-Codex-2026-07-05-hey-codex-i-want-to-create-outputs-LocalTalk/1402cec9-52ca-47a5-a266-990e8d4a1a44/scratchpad/renders2"
cp "$R/history_with_entries.png" site/assets/history.png
cp "$R/popover_idle.png"        site/assets/popover.png
cp "$R/settings_full_page.png"  site/assets/settings.png
cp "$R/hud_recording.png"       site/assets/hud.png
```
(If `$R` renders are gone, regenerate via the app's offscreen render harness pattern, or substitute the equivalents from `renders/`. Report if missing.)

- [ ] **Step 2: Write `site/styles.css`** — tokens, reset, and primitives (complete):

```css
:root {
  --ink0:#07090B; --ink1:#101214; --ink2:#16181A;
  --mint:#2BDEB1; --mint-text:#B0F9E2; --mint-dim:rgba(43,222,177,.42);
  --hairline:rgba(255,255,255,.08); --hairline-strong:rgba(255,255,255,.12);
  --text:#F0F2F2; --text-2:rgba(255,255,255,.62); --text-3:rgba(255,255,255,.40);
  --coral:#FF7670;
  --radius-card:12px; --radius-ctrl:8px; --pill:999px;
  --maxw:1080px; --gutter:24px;
  --font-sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
  --font-mono:ui-monospace,"SF Mono",Menlo,Monaco,"Cascadia Code",monospace;
}
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
html{-webkit-font-smoothing:antialiased;-moz-osx-font-smoothing:grayscale;scroll-behavior:smooth}
@media (prefers-reduced-motion:reduce){html{scroll-behavior:auto}}
body{background:var(--ink0);color:var(--text);font-family:var(--font-sans);font-size:16px;line-height:1.6;text-rendering:optimizeLegibility}
img{max-width:100%;display:block;outline:1px solid var(--hairline);outline-offset:-1px;border-radius:var(--radius-card)}
a{color:inherit;text-decoration:none}
h1,h2,h3{font-weight:500;letter-spacing:-.4px;line-height:1.15;text-wrap:balance}
h1{font-size:clamp(32px,5vw,46px)} h2{font-size:clamp(24px,3.4vw,32px)} h3{font-size:18px}
p{text-wrap:pretty;color:var(--text-2)}
.mono{font-family:var(--font-mono)}
.mint{color:var(--mint)}
.wrap{max-width:var(--maxw);margin-inline:auto;padding-inline:var(--gutter)}
.section{padding-block:clamp(56px,9vw,104px)}
.eyebrow{font-family:var(--font-mono);font-size:12px;color:var(--text-3);text-transform:uppercase;letter-spacing:.06em}
.btn{display:inline-flex;align-items:center;gap:8px;font-size:15px;font-weight:500;padding:12px 22px;border-radius:var(--pill);border:0.5px solid transparent;transition:transform .15s ease-out,background-color .15s ease-out,box-shadow .15s ease-out;cursor:pointer}
.btn:active{transform:scale(.97)}
.btn-primary{background:var(--mint);color:#06231B}
.btn-primary:hover{box-shadow:0 8px 28px rgba(43,222,177,.28)}
.btn-ghost{border-color:var(--hairline-strong);color:var(--text)}
.btn-ghost:hover{background:var(--ink2)}
.card{background:var(--ink1);border:0.5px solid var(--hairline);border-radius:var(--radius-card)}
:focus-visible{outline:2px solid var(--mint);outline-offset:2px}
.tabular{font-variant-numeric:tabular-nums}
.skip{position:absolute;left:-999px}.skip:focus{left:12px;top:12px;background:var(--ink2);padding:8px 12px;border-radius:var(--radius-ctrl);z-index:100}
```

- [ ] **Step 3: Write `site/main.js`** (progressive enhancement only):

```js
// Mobile nav toggle
const navBtn = document.querySelector('[data-nav-toggle]');
const nav = document.querySelector('[data-nav]');
if (navBtn && nav) {
  navBtn.addEventListener('click', () => {
    const open = nav.classList.toggle('is-open');
    navBtn.setAttribute('aria-expanded', String(open));
  });
}
```

- [ ] **Step 4: Write a minimal `site/index.html` skeleton** — valid doc with head, skip link, empty `<main>`, links to styles/js. Include full `<head>` meta now (charset, viewport, title "Bulong — private, on-device dictation for macOS", description, favicon `assets/icon.png`, Open Graph + Twitter card pointing at `assets/og.png` and `https://bulong.app`). Body: `<a class="skip" href="#main">Skip to content</a>`, empty `<header>`, `<main id="main">`, `<footer>`, `<script src="main.js" defer>`.

- [ ] **Step 5: Create `.claude/launch.json`** so Claude Preview can serve/screenshot:

```json
{
  "version": "0.0.1",
  "configurations": [
    { "name": "bulong-site", "runtimeExecutable": "python3", "runtimeArgs": ["-m","http.server","8000","--directory","site"], "port": 8000 }
  ]
}
```

- [ ] **Step 6: Verify + commit**

PREVIEW → the page loads (blank but valid), no console errors, favicon resolves. `python3 -c "import html.parser,pathlib; html.parser.HTMLParser().feed(pathlib.Path('site/index.html').read_text())"` parses clean.

```bash
git add site .claude/launch.json && git commit -m "feat(site): scaffold, design tokens, preview harness"
```

---

### Task 2: Shared chrome — sticky nav + footer

**Files:** Modify `site/index.html` (`<header>`, `<footer>`), `site/styles.css` (nav/footer styles)

- [ ] **Step 1: Nav markup** in `<header>` — `<nav class="nav" data-nav aria-label="Primary">` with: a brand link (mint square glyph + `<span class="mono">bulong</span>`) to `#top`; a `<ul>` of links Features (`#features`), Privacy (`privacy.html`), Pricing (`#pricing`); a `.btn.btn-primary` "Download" (href `#download`, the placeholder anchor); and a hamburger `<button data-nav-toggle aria-expanded="false" aria-controls="nav-links" aria-label="Menu">` (inline SVG lines). Sticky, ink background, hairline bottom border.

- [ ] **Step 2: Footer markup** in `<footer>` — brand wordmark; columns/links: Download (`#download`), Privacy (`privacy.html`), Contact (`mailto:hello@bulong.app` — placeholder address, note in README); the exact attribution line "Includes NVIDIA Parakeet, © NVIDIA, CC-BY-4.0"; "© 2026 Bulong. Apple Silicon · macOS 14+." Hairline top border.

- [ ] **Step 3: Nav/footer CSS** — sticky nav (`position:sticky;top:0;z-index:50;backdrop-filter:blur(8px)` over `rgba(7,9,11,.8)`), flex layout, the mobile breakpoint at `max-width:720px` hides `.nav ul`/CTA behind `[data-nav].is-open` (full-width dropdown). Footer grid, muted text, hover states on all links.

- [ ] **Step 4: Verify + commit**

PREVIEW desktop (1280) and mobile (375, via `mcp__Claude_Preview__preview_resize` preset "mobile"): nav sticks; hamburger toggles the menu (aria-expanded flips); footer reads correctly; all links have visible hover/focus.

```bash
git add site && git commit -m "feat(site): sticky nav and footer chrome"
```

---

### Task 3: Hero section with the animated CSS HUD

**Files:** Modify `site/index.html` (hero in `<main>`), `site/styles.css`

- [ ] **Step 1: Hero markup** — `<section class="hero" id="top">` containing: badge `<p class="badge mono">` "100% on-device · nothing uploaded, ever" (mint dot + text); `<h1>Your voice never leaves your <span class="mint">Mac</span>.</h1>`; sub `<p>` (exact spec copy); a CTA row — `<a class="btn btn-primary" href="#download">` (download SVG + "Download for macOS") and `<span class="mono price">Free to try · <span data-price>$29</span> once</span>`; a small `<p class="mono req">Apple Silicon · macOS 14+</p>`; then the HUD figure (Step 2).

- [ ] **Step 2: HUD recreation** (the hero visual) — a `<figure class="hud" role="img" aria-label="Bulong dictation bar showing a live transcription">`: an `.orb` (radial-gradient circle), a text stack ("Listening" + a mono partial "…moved to Thursday"), a `.waveform` of 5 bars, and a mono `ON-DEVICE` pill. Style the shell to match the app HUD (diagonal ink gradient, `rgba(60,104,96,.6)` rim, radius 20, deep shadow).

- [ ] **Step 3: Orb + waveform animation** (reduced-motion-gated):

```css
@media (prefers-reduced-motion: no-preference){
  .hud .orb{animation:breathe 2.6s ease-in-out infinite}
  .hud .waveform i{animation:wave 1.1s ease-in-out infinite}
  .hud .waveform i:nth-child(2){animation-delay:.15s}
  .hud .waveform i:nth-child(3){animation-delay:.3s}
  .hud .waveform i:nth-child(4){animation-delay:.45s}
  .hud .waveform i:nth-child(5){animation-delay:.6s}
}
@keyframes breathe{0%,100%{box-shadow:0 0 18px rgba(43,222,177,.35);transform:scale(1)}50%{box-shadow:0 0 30px rgba(43,222,177,.6);transform:scale(1.06)}}
@keyframes wave{0%,100%{transform:scaleY(.5)}50%{transform:scaleY(1)}}
```
Bars use `transform-origin:center` and only animate `transform` (compositor-friendly). Under reduced motion the orb/waveform render static at a sensible mid state.

- [ ] **Step 4: Verify + commit**

PREVIEW: hero matches the approved mockup direction (badge, mint-accented H1, CTA + price, breathing orb + waveform). Toggle reduced motion via `mcp__Claude_Preview__preview_resize` `colorScheme`? (motion isn't in resize) — instead verify the CSS guard by reading it and confirming static fallback exists. Contrast check: mint on ink and `--text-2` grays ≥ 4.5:1 (use a checker or the review pass in Task 8).

```bash
git add site && git commit -m "feat(site): hero with animated on-device HUD"
```

---

### Task 4: Provably-private + how-it-works sections

**Files:** Modify `site/index.html`, `site/styles.css`

- [ ] **Step 1: "Provably private"** `<section class="section" id="privacy-pitch">` — eyebrow "Privacy"; `<h2>Private by architecture, not by promise.</h2>`; three `.card` columns (No cloud / No account / No telemetry) each with a heading + one-sentence body (exact spec copy); then a bordered `.callout` with the line **"Turn off your Wi-Fi and dictate. It still works. That's the whole point."** and a link `<a href="privacy.html">See exactly what's handled →</a>`.

- [ ] **Step 2: "How it works"** `<section class="section" id="how">` — `<h2>Three keys and your voice.</h2>`; three mono-numbered `.step` cards: 1 "Press your hotkey" ("⌃⌥Space, remappable"), 2 "Speak naturally", 3 "The text appears where your cursor is". Numbers in mono mint.

- [ ] **Step 3: CSS** — responsive grids (`repeat(auto-fit,minmax(220px,1fr))`), the callout style (mint-dim border, ink1 fill, radius-card, the sentence in larger text), step-number styling. Cards get hover lift (`translateY(-2px)` + hairline-strong) gated to non-touch via `@media (hover:hover)`.

- [ ] **Step 4: Verify + commit**

PREVIEW: both sections read cleanly, columns collapse to one on mobile, the callout is the visual anchor of the privacy section.

```bash
git add site && git commit -m "feat(site): provable-privacy and how-it-works sections"
```

---

### Task 5: "See it" showcase + features grid

**Files:** Modify `site/index.html`, `site/styles.css`

- [ ] **Step 1: "See it"** `<section class="section" id="see">` — `<h2>Designed to disappear.</h2>`; three framed screenshots (`site/assets/history.png`, `popover.png`, `settings.png`) each in a `.shot` figure with a subtle window frame (hairline + radius, small caption). Real `alt` describing each ("Bulong's History window listing recent transcripts", etc.). Lazy-load (`loading="lazy"`).

- [ ] **Step 2: Features grid** `<section class="section" id="features">` — `<h2>Everything you need, nothing you don't.</h2>`; a grid of feature `.card`s, each an inline-SVG icon (18–20px, `stroke:currentColor`, `aria-hidden="true"`) + title + one line. Exact list: On-device Parakeet + Whisper · Works in every app · Push-to-talk or toggle · Custom hotkey · Local, searchable history · 25+ languages incl. Filipino · Translate to English · Your clipboard is preserved. (8 items — 4×2 desktop, 2×4 tablet, 1-col mobile.)

- [ ] **Step 3: CSS** — `.shot` frame (drop shadow allowed — it's a floating product shot), grid responsiveness, feature-card icon color mint, consistent card padding/rhythm.

- [ ] **Step 4: Verify + commit**

PREVIEW: screenshots read as crisp product shots (not naked images — framed, outlined); feature grid aligns (equal card heights per row); icons render.

```bash
git add site && git commit -m "feat(site): app showcase and features grid"
```

---

### Task 6: Comparison table + pricing card + FAQ + footer CTA

**Files:** Modify `site/index.html`, `site/styles.css`

- [ ] **Step 1: Comparison** `<section class="section" id="compare">` — `<h2>Why on-device wins.</h2>`; a real `<table>` (caption, `<thead>` Bulong / Typical cloud app / Apple built-in, `<tbody>` rows exactly as spec: where audio goes, price, account required, works offline, history you can read and export). Bulong-yes cells get a mint check SVG (with an accompanying text value — never color-only). EVERY Bulong cell must be literally true of the shipping app. Horizontal-scroll wrapper on mobile (`overflow-x:auto`).

- [ ] **Step 2: Pricing** `<section class="section" id="pricing">` — `<h2>One price. No subscription, ever.</h2>`; one `.card.price-card`: big `<span class="tabular" data-price>$29</span>` + "once"; a `<ul>` of checks (one Mac · free trial · lifetime 1.0 updates · 14-day refund); a `.btn.btn-primary` "Download for macOS" (`#download`); sub-note "No account. No recurring charge.". The `data-price` here and in the hero are the only two price occurrences — document in README.

- [ ] **Step 3: FAQ** `<section class="section" id="faq">` — `<h2>Questions.</h2>`; native `<details>` items (each `<summary>` = question, body = answer) for the exact FAQ list in the spec (offline, which Macs, extra installs, download size, which apps, refunds, updates, why "Bulong"). Works with JS off; style the marker and open/close transition (max-height or grid-rows transition, reduced-motion aware).

- [ ] **Step 4: Footer CTA** — a final `<section class="section cta-final">` repeating the primary download + `data-price`? No — keep price single-sourced; use text "Download for macOS" + "$29 once" where the $29 is a third `data-price`… to keep ONE source, put the price in a CSS custom property `--price-str` used via `::after content` OR accept 2–3 `data-price` spans updated together. DECISION: use `data-price` spans (hero, pricing, final CTA) and document "update all `data-price`" in README — simpler and accessible than CSS content. Keep it to those three.

- [ ] **Step 5: Verify + commit**

PREVIEW: table is readable and scrolls on mobile; pricing card is the clear conversion anchor; FAQ expands/collapses without JS; final CTA closes the page.

```bash
git add site && git commit -m "feat(site): comparison, pricing, FAQ, final CTA"
```

---

### Task 7: Privacy page

**Files:** Create `site/privacy.html`; Modify `site/styles.css` (only if new utility needed)

- [ ] **Step 1: Build `privacy.html`** — same `<head>` pattern (title "Privacy — Bulong", its own description), same nav/footer chrome (copy the header/footer markup; acceptable duplication for a 2-page static site — note it so a future third page motivates a shared include). `<main>` with `<h1>How Bulong handles your voice.</h1>` and the spec's sections as `<section>`s with `<h2>`s: What is captured · Where transcription happens · What is stored · What leaves your Mac · How to verify it yourself · Permissions and why · Contact. Plain-language, exact spec content. A "Last updated: 8 July 2026" line and a back-to-home link.

- [ ] **Step 2: Verify + commit**

PREVIEW `/privacy.html`: chrome matches, content is specific and honest, the "verify it yourself" section is prominent, nav "Privacy" link marks current page (`aria-current="page"`).

```bash
git add site && git commit -m "feat(site): privacy page"
```

---

### Task 8: OG image, SEO meta, accessibility + design review, docs

**Files:** Create `script/render_og.swift`, `site/README.md`, `site/robots.txt`, `site/assets/og.png`; Modify both HTML heads if review finds gaps

- [ ] **Step 1: OG image script** — `script/render_og.swift`, a standalone CoreGraphics script mirroring `script/render_icon.swift`: 1200×630, ink background, the mint waveform orb motif, mono `bulong` wordmark, tagline "Your voice never leaves your Mac.", writes `site/assets/og.png`. Run `swift script/render_og.swift`; open and eyeball.

- [ ] **Step 2: SEO/meta finalize** — confirm both pages have: unique `<title>`/description, canonical `<link rel="canonical">`, OG + Twitter tags with absolute `https://bulong.app/...` URLs and `assets/og.png`, `theme-color` `#07090B`, `lang="en"`. Add `site/robots.txt` (allow all, sitemap optional) and a minimal `site/sitemap.xml` (2 URLs).

- [ ] **Step 3: Accessibility + better-design review** — load `mcp__better-design__get-review-rules` and audit BOTH pages: alt text present, icon buttons labeled, one h1 + ordered headings, focus-visible everywhere, contrast ≥ 4.5:1 (check `--text-2`/`--text-3` on ink — bump the token if any fail), the mobile nav fully keyboard-operable, `details/summary` semantics, table has caption + headers, no color-only signals. Fix every critical/serious finding. Record the before/after in the commit body.

- [ ] **Step 4: Responsive + JS-off pass** — screenshot at 375 / 768 / 1280 (`preview_resize` presets); confirm no horizontal overflow, tap targets ≥ 40px, the page is fully usable with `main.js` removed (only the mobile menu degrades to visible). Fix any overflow.

- [ ] **Step 5: `site/README.md`** — document: preview (`python3 -m http.server 8000 --directory site`), the THREE `data-price` spans to edit for a price change, the placeholder links to wire later (`#download` → notarized DMG URL; the pricing/download CTAs → Lemon Squeezy checkout URL; `hello@bulong.app` contact), and deploy (upload `site/` contents to Hostinger `public_html` for bulong.app, or via the Hostinger hosting tools with the user's authorization — do not automate DNS/purchase).

- [ ] **Step 6: Final verify + commit**

Full-page desktop + mobile screenshots of both pages saved to the session scratchpad for the design-critique gate (Task 9-equivalent handled by the coordinator). No lorem/TODO remains (`grep -rn "TODO\|lorem\|Lorem" site` → empty).

```bash
git add site script/render_og.swift && git commit -m "feat(site): OG image, SEO, accessibility pass, docs"
```

---

## Self-review notes (for the executor)

- **Spec coverage:** nav/footer (T2), hero+HUD (T3), provable-privacy + how-it-works (T4), see-it + features (T5), comparison + pricing + FAQ + final CTA (T6), privacy page (T7), OG/SEO/a11y/responsive/docs (T8). Tokens/assets/harness (T1). Every spec section maps to a task.
- **Honesty gate (brand-critical):** the comparison table and features list must claim ONLY what the shipping app does today — no custom vocabulary, no cloud AI, no tiers. T6 Step 1 and T5 Step 2 both restate this.
- **Single price source:** exactly three `data-price` spans (hero, pricing, final CTA), documented in README. Not CSS-content (accessibility).
- **Placeholders that stay placeholders this phase:** `#download`, checkout URLs, `hello@bulong.app`. Wired in the later distribution/licensing sub-projects.
- **This is genuine web** — better-design `get-review-rules` applies directly (unlike the native app); T8 runs it for real.
- **Verification is visual** (Claude Preview screenshots) not unit tests — a static marketing site has no logic to TDD; the "test" is renders + a11y review + JS-off + responsive.
- Do not touch the Swift app, `project.yml`, or the app's `Theme.swift`; the site is independent. Never `git add -A` (repo-root mp3s).
