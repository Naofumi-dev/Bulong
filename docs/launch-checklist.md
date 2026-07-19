# Bulong launch-day checklist

Ordered so nothing user-facing goes live before the thing it depends on is
tested. Work top to bottom. **GATE** = do not proceed until it passes.

## Two invariants that break everything if wrong

1. **The app's bundled PUBLIC key must match the server's PRIVATE key.** If they
   differ, *every* purchased key fails to activate. Verified explicitly in
   Phase 1 and again in Phase 4.
2. **The DMG must be notarized + stapled before its download link is public.**
   Otherwise first launch shows an "unidentified developer" block and most
   people bounce.

Keep the site in `dl-soon` (its current, honest state) until Phase 5. That alone
means a half-finished step is never visible to a buyer.

---

## Phase 0 — Prerequisites (start days ahead; these have lead time)

- [ ] **Apple Developer Program** active, "Developer ID Application" cert in the
      login keychain. → `security find-identity -v -p codesigning` lists it.
      (Enrollment can take 24–48h.)
- [ ] **Lemon Squeezy** store created and approved for payouts.
- [ ] **Resend** account with **bulong.app** domain verified (DNS records
      propagated — can take hours).
- [ ] **bulong.app** attached to the Vercel `bulong` project. → it already
      serves the landing page over HTTPS.
- [ ] Decide **where the DMG is hosted** (it's a free download — the trial is the
      paywall, not the download):
      - Recommended: **GitHub Releases** on a public repo (versioned, free, good
        for future auto-update). URL like
        `https://github.com/<you>/bulong/releases/download/v1.0.0/Bulong.dmg`.
      - Simplest: drop `Bulong.dmg` in `site/` → served at
        `https://bulong.app/Bulong.dmg` (don't commit the 25 MB binary to git;
        upload it as a Vercel deploy asset or use Vercel Blob).

## Phase 1 — Keys & the shippable build (offline, careful)

- [ ] Generate the **production keypair**, offline:
      `swift script/sign_license.swift --genkey`
      → store PRIVATE in a password manager; it never leaves your control.
- [ ] Put the **PUBLIC** key in the app: replace `bundledPublicKeyB64` in
      `LocalTalk/Services/Licensing/LicenseVerifier.swift` (currently the **test** key
      `o68OJn5G…` — a launch blocker).
      → **VERIFY:** `grep bundledPublicKeyB64 LocalTalk/Services/Licensing/LicenseVerifier.swift`
      shows YOUR key, not `o68OJn5G…`.
- [ ] Build, sign (Developer ID), notarize, staple, package:
      `TEAM_ID=XXXXXXXXXX script/release.sh`
      `script/sign_and_notarize.sh`
      `script/make_dmg.sh`
      → **VERIFY:** `spctl -a -vvv build/export/Bulong.app` says
      `source=Notarized Developer ID`, and `xcrun stapler validate` passes on
      both the app and the DMG.
- [ ] 🔒 **GATE — the shipped build accepts a server-signed key.** Sign a key
      with the PRODUCTION PRIVATE key and activate it in the notarized build:
      ```sh
      export LICENSE_PRIVATE_KEY_B64=<prod private>
      node script/issue_license.mjs --name "You" --email you@you.com --order PROOF-1
      ```
      Install the notarized app, paste the key in Settings → Advanced → License →
      Activate. It must flip to "Licensed to You." If it doesn't, the public key
      in the build ≠ the private key you'll deploy — stop and fix.

## Phase 2 — Backend (webhook + delivery)

- [ ] Create the Resend **API key**.
- [ ] Deploy the site so the function is live: `vercel deploy --prod` (or push).
      → **VERIFY:** `curl -s -o /dev/null -w "%{http_code}" https://bulong.app/api/webhooks/lemonsqueezy`
      returns **405** (GET rejected = the function is deployed and reachable).
- [ ] In **Lemon Squeezy**: create the **$29 one-time** Bulong product; add a
      **webhook** → URL `https://bulong.app/api/webhooks/lemonsqueezy`, event
      **`order_created`**; copy the **signing secret** and the product's
      **checkout URL**.
- [ ] Set Vercel **env vars** (Production) and redeploy:
      `LICENSE_PRIVATE_KEY_B64`, `LEMONSQUEEZY_WEBHOOK_SECRET`, `RESEND_API_KEY`,
      (optional) `LICENSE_FROM_EMAIL="Bulong <hello@bulong.app>"`.
- [ ] Upload the notarized **DMG** to the chosen host; note its public URL.

## Phase 3 — Wire the site (still `dl-soon`, not yet public-live)

- [ ] In `site/download.html`: set the `<!-- BUY-URL -->` links to the LS
      checkout URL, and the `<!-- DMG-URL -->` links + `<!-- DMG-META -->`
      version/size to the real DMG. **Leave `<body class="dl-soon">` for now.**
- [ ] Deploy the site.

## Phase 4 — End-to-end test (Lemon Squeezy TEST mode)

- [ ] 🔒 **GATE — purchase → email → activate.** With LS in **test mode**, buy
      Bulong with a test card. → the license email arrives (check Resend logs if
      not), and its key activates in the **notarized** build.
- [ ] 🔒 **GATE — clean download & first run.** Download the DMG from its public
      URL on a Mac (ideally a different user account / machine): it opens with
      **no Gatekeeper block**, mic + Accessibility grants work, and a dictation
      types into TextEdit. (Real users on a notarized build don't hit the
      duplicate-registration issue from dev — that was local-only.)
- [ ] **Trial check:** a fresh install (no license) shows the **14-day trial**
      and dictation works during it.
- [ ] Check Vercel function logs: the test purchase logged `ok:true`; no 401
      (secret mismatch) or 500 (sign/email failure).

## Phase 5 — Go live

- [ ] Flip `site/download.html` `<body class="dl-soon">` → `dl-live`; deploy.
      → **VERIFY:** the download + Buy buttons show; the "get notified" CTAs are
      gone.
- [ ] Switch **Lemon Squeezy to live mode**.
- [ ] Optional real-money smoke test: buy once for real, confirm the key
      activates, refund yourself.
- [ ] Announce — you have the notify-me captures from the `mailto:` CTAs.

## If something goes wrong (fast rollback)

- **Bad build already downloadable:** flip the site back to `dl-soon` and
  deploy — that hides the download instantly. Fix, re-notarize, re-test.
- **Webhook not delivering keys:** issue keys by hand from the LS order details
  while you debug — no buyer is stuck:
  ```sh
  export LICENSE_PRIVATE_KEY_B64=<prod private>
  node script/issue_license.mjs --name "<buyer>" --email "<buyer email>" \
    --order "<LS identifier>" --issued "<order created_at, whole seconds>"
  ```
  (Deterministic: this reproduces the exact key the buyer would have received.)
- **Keys not activating for anyone:** public key in the shipped build ≠ server
  private key. Emergency — pull the download (`dl-soon`), rebuild with the
  correct public key, re-notarize.
- **Private key compromised:** rotate it, but note every key already sold stops
  working — you'd re-issue to existing buyers. Guard it accordingly.

## First 24 hours — watch

- Vercel function logs: 401 = webhook secret wrong; 500 = sign/email failure.
- Resend dashboard: deliveries, bounces, spam complaints.
- Support inbox: "my key won't activate" is the canary for a key mismatch —
  treat as an incident.

## Reference

- Licensing internals & setup: `docs/licensing-delivery.md`
- Interop guard (run anytime): `script/test_license_interop.sh`
- Signing/notarizing: `script/release.sh`, `script/sign_and_notarize.sh`, `script/make_dmg.sh`
- Dev permission repair (dev machines only): `script/fix_permissions.sh`
