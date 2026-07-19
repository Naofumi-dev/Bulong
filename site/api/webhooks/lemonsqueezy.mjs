// Lemon Squeezy purchase webhook → signed license key, emailed to the buyer.
//
//   Endpoint:  POST https://bulong.app/api/webhooks/lemonsqueezy
//   Set this URL in Lemon Squeezy → Settings → Webhooks, subscribe to
//   "order_created", and copy the signing secret into env.
//
// Required environment variables (Vercel → Project → Settings → Environment):
//   LICENSE_PRIVATE_KEY_B64        Ed25519 seed (base64) from sign_license.swift --genkey. SECRET.
//   LEMONSQUEEZY_WEBHOOK_SECRET    the webhook signing secret from the LS dashboard. SECRET.
//   RESEND_API_KEY                 Resend API key for sending the email. SECRET.
//   LICENSE_FROM_EMAIL             optional, e.g. "Bulong <hello@bulong.app>" (verified domain).
//
// The private key lives ONLY here (server env) — the app ships just the public
// key. Uses the Web Request/Response signature so the raw body is available
// verbatim for HMAC verification.
import crypto from 'node:crypto';
import { signLicense } from '../_lib/license.mjs';
import { sendLicenseEmail } from '../_lib/email.mjs';

export default async function handler(request) {
  if (request.method !== 'POST') return json({ error: 'method not allowed' }, 405);

  const secret = process.env.LEMONSQUEEZY_WEBHOOK_SECRET;
  const privB64 = process.env.LICENSE_PRIVATE_KEY_B64;
  const resendKey = process.env.RESEND_API_KEY;
  const from = process.env.LICENSE_FROM_EMAIL || 'Bulong <hello@bulong.app>';
  if (!secret || !privB64 || !resendKey) return json({ error: 'server not configured' }, 500);

  // Raw bytes exactly as sent — required for the HMAC to match.
  const raw = Buffer.from(await request.arrayBuffer());

  // 1) Authenticate the webhook (HMAC-SHA256, timing-safe). Reject anything else.
  const expected = crypto.createHmac('sha256', secret).update(raw).digest('hex');
  const provided = request.headers.get('x-signature') || '';
  if (!timingSafeEqualHex(expected, provided)) return json({ error: 'bad signature' }, 401);

  let event;
  try { event = JSON.parse(raw.toString('utf8')); } catch { return json({ error: 'bad json' }, 400); }

  // 2) Only issue for a completed, paid order. ACK everything else with 200 so
  //    Lemon Squeezy doesn't retry events we intentionally ignore.
  const eventName = event?.meta?.event_name;
  if (eventName !== 'order_created') return json({ ignored: eventName || 'unknown' }, 200);

  const attr = event?.data?.attributes || {};
  if (attr.status && attr.status !== 'paid') return json({ ignored: `status:${attr.status}` }, 200);

  const buyerEmail = attr.user_email;
  if (!buyerEmail) return json({ ignored: 'no email' }, 200);
  const buyerName = attr.user_name || 'Bulong user';
  const orderRef = attr.identifier || `LS-${attr.order_number ?? event?.data?.id ?? 'unknown'}`;
  // Deterministic issued → re-running this exact order reproduces the same key,
  // so a Lemon Squeezy retry (or a manual resend) never mints a second key.
  const issued = attr.created_at;

  let token;
  try {
    token = signLicense({ privB64, name: buyerName, email: buyerEmail, order: orderRef, issued });
  } catch (e) {
    // A signing failure is a config/key problem — 500 so it's visible in logs.
    return json({ error: 'sign failed', detail: String(e).slice(0, 200) }, 500);
  }

  try {
    await sendLicenseEmail({ apiKey: resendKey, from, to: buyerEmail, name: buyerName, licenseKey: token, orderRef });
  } catch (e) {
    // Signing worked but email didn't → 500 so LS retries. The token is
    // deterministic, so the retry re-sends the identical key (no duplicates).
    return json({ error: 'email failed', detail: String(e).slice(0, 200) }, 500);
  }

  return json({ ok: true, order: orderRef }, 200);
}

function json(obj, status) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

function timingSafeEqualHex(a, b) {
  let ab, bb;
  try { ab = Buffer.from(a, 'hex'); bb = Buffer.from(b, 'hex'); } catch { return false; }
  return ab.length > 0 && ab.length === bb.length && crypto.timingSafeEqual(ab, bb);
}
