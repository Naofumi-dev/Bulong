# License delivery — purchase → signed key → activation

How a Lemon Squeezy purchase becomes a working Bulong license. The app verifies
keys **offline** with a bundled Ed25519 public key; the matching private key
lives only on the server and signs a key for each paid order.

```
Buyer pays (Lemon Squeezy)
      │  order_created webhook (HMAC-signed)
      ▼
Vercel function  site/api/webhooks/lemonsqueezy.mjs
      │  1. verify HMAC   2. sign Ed25519 token   3. email it (Resend)
      ▼
Buyer's inbox  →  paste key in Bulong → Settings → Advanced → License → Activate
      │
      ▼
App verifies the signature against the bundled PUBLIC key — no network, no account.
```

**Proven working:** the Node signer produces tokens the app's CryptoKit
`LicenseVerifier` accepts (`script/test_license_interop.sh`), including Lemon
Squeezy's microsecond timestamps normalized to the whole-second ISO8601 the
Swift decoder requires.

## Files

| File | Role |
|------|------|
| `site/api/webhooks/lemonsqueezy.mjs` | Webhook endpoint: verify → sign → email |
| `site/api/_lib/license.mjs` | Ed25519 signer (matches the app verifier) |
| `site/api/_lib/email.mjs` | Resend delivery (swap for Postmark/SES/SMTP) |
| `script/issue_license.mjs` | Manually issue/resend a key (support, comps) |
| `script/sign_license.swift` | `--genkey`, and a Swift-side signer |
| `script/test_license_interop.sh` | Regression guard for the cross-language contract |

## Setup (in order)

### 1. Generate the production keypair — once, offline

```sh
swift script/sign_license.swift --genkey
# PRIVATE(base64): <keep secret — server only, never commit, never ship>
# PUBLIC(base64):  <goes into the app>
```

Store the PRIVATE key in a password manager. If it leaks, anyone can mint free
licenses; rotating it invalidates every key already sold.

### 2. Put the PUBLIC key in the app

In `LocalTalk/Services/LicenseVerifier.swift`, replace `bundledPublicKeyB64`
with your PUBLIC key (it currently holds the committed **test** key — shipping
that is a launch blocker). Then rebuild, sign, and notarize
(`script/release.sh` → `script/sign_and_notarize.sh`).

### 3. Resend (transactional email)

1. Create a [Resend](https://resend.com) account; add and verify the
   **bulong.app** domain (DNS records).
2. Create an API key.
3. Send from a verified address, e.g. `Bulong <hello@bulong.app>`.

(Prefer Postmark/SES/your own SMTP? Rewrite the single `fetch` in
`site/api/_lib/email.mjs`; nothing else changes.)

### 4. Lemon Squeezy

1. Create the store and a **$29 one-time** product for Bulong.
2. Store → Settings → **Webhooks** → add
   `https://bulong.app/api/webhooks/lemonsqueezy`, subscribe to **`order_created`**.
3. Copy the webhook **signing secret**.
4. Copy the product's **checkout URL** (Share → checkout link).

### 5. Vercel environment variables

Project **bulong** → Settings → Environment Variables (Production):

| Name | Value |
|------|-------|
| `LICENSE_PRIVATE_KEY_B64` | the PRIVATE key from step 1 |
| `LEMONSQUEEZY_WEBHOOK_SECRET` | the signing secret from step 4 |
| `RESEND_API_KEY` | the Resend API key from step 3 |
| `LICENSE_FROM_EMAIL` | `Bulong <hello@bulong.app>` (optional) |

Redeploy so the function picks them up. `vercel deploy --prod` (or push to the
connected branch).

### 6. Wire the Buy button

In `site/download.html`, set the `<!-- BUY-URL -->` links to the Lemon Squeezy
checkout URL from step 4, then flip `<body class="dl-soon">` → `dl-live` once
the notarized DMG is up (`<!-- DMG-URL -->`).

### 7. Test before announcing

- `script/test_license_interop.sh` — Node-signed key verifies in CryptoKit.
- Lemon Squeezy **test mode**: make a test purchase → confirm the email arrives
  and the key activates in a real build (whose `bundledPublicKeyB64` matches the
  server's private key).
- Dry-run a key without buying:
  ```sh
  export LICENSE_PRIVATE_KEY_B64=...
  node script/issue_license.mjs --name "Test" --email you@you.com --order TEST-1
  ```

## Support: resend a lost key

Keys are **deterministic** — the same order reproduces the identical key, so no
database is needed. From the Lemon Squeezy order, read the buyer name, email,
`identifier`, and `created_at`, then:

```sh
export LICENSE_PRIVATE_KEY_B64=...
node script/issue_license.mjs --name "Jo Cruz" --email jo@x.com \
  --order LS-a1b2c3d4 --issued 2026-07-19T15:30:00Z
```

Passing the original `--issued` (whole seconds) regenerates the exact key the
buyer first received.

## Security notes

- **Private key never touches the app or the repo** — server env only. The app
  ships the public key, which can only *verify*.
- The webhook **rejects any request without a valid HMAC** (timing-safe), so
  nobody can POST a fake "order" to mint a key.
- The endpoint issues a key only for `order_created` with `status: paid`; every
  other event is acknowledged (200) and ignored.
- Delivery is idempotent: a Lemon Squeezy retry re-signs the *same* token and
  re-sends it — never a second, different key.
- Keys are unbound to hardware (one purchase = one key, works on the buyer's
  Mac). If you later want per-seat limits, add an activation count in a KV store;
  the token format doesn't need to change.
