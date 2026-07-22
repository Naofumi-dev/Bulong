// Lead capture → GHL and/or a notification email.
//
//   Endpoint:  POST https://bulong.app/api/lead
//   Body:      JSON {email, lang?, page?, website?}   (website = honeypot)
//
// Delivery channels, by env (Vercel → Project → Settings → Environment):
//   GHL_LEAD_WEBHOOK_URL   optional — a GoHighLevel inbound-webhook URL; the
//                          lead is POSTed there as JSON for your automations.
//   RESEND_API_KEY         optional — emails each lead to LEAD_NOTIFY_TO.
//   LEAD_NOTIFY_TO         optional, default hello@bulong.app.
//   LICENSE_FROM_EMAIL     optional sender, default "Bulong <hello@bulong.app>".
// With NEITHER configured the endpoint returns 503 and the site's form falls
// back to a mailto link — no lead is silently dropped.
//
// Same (req, res) Node-runtime signature + manual body read as the license
// webhook (NODEJS_HELPERS=0 is set project-wide, so req.body never exists).

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

export default async function handler(req, res) {
  const json = (obj, status) => {
    res.statusCode = status;
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify(obj));
  };
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405);

  const raw = await readRawBody(req);
  if (!raw || raw.length === 0 || raw.length > 10_000) return json({ error: 'bad body' }, 400);

  let body;
  try { body = JSON.parse(raw.toString('utf8')); } catch { return json({ error: 'bad json' }, 400); }

  // Honeypot filled → a bot. Pretend success so it stops probing.
  if (body.website) return json({ ok: true }, 200);

  const email = String(body.email || '').trim().slice(0, 200);
  if (!EMAIL_RE.test(email)) return json({ error: 'invalid email' }, 400);
  const lang = String(body.lang || '').slice(0, 60);
  const page = String(body.page || '').slice(0, 120);

  const ghlUrl = process.env.GHL_LEAD_WEBHOOK_URL;
  const resendKey = process.env.RESEND_API_KEY;
  if (!ghlUrl && !resendKey) return json({ error: 'not configured' }, 503);

  const lead = { email, lang, page, source: 'bulong.app', ts: new Date().toISOString() };
  const delivered = [];
  const failures = [];

  if (ghlUrl) {
    try {
      const r = await fetch(ghlUrl, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(lead),
      });
      if (!r.ok) throw new Error(`ghl ${r.status}`);
      delivered.push('ghl');
    } catch (e) { failures.push(String(e).slice(0, 120)); }
  }

  if (resendKey) {
    try {
      const to = process.env.LEAD_NOTIFY_TO || 'hello@bulong.app';
      const from = process.env.LICENSE_FROM_EMAIL || 'Bulong <hello@bulong.app>';
      const r = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { Authorization: `Bearer ${resendKey}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          from, to,
          subject: `New Bulong lead: ${email}`,
          text: `Email: ${email}\nDictates in: ${lang || '—'}\nPage: ${page || '—'}\nWhen: ${lead.ts}`,
        }),
      });
      if (!r.ok) throw new Error(`resend ${r.status}`);
      delivered.push('email');
    } catch (e) { failures.push(String(e).slice(0, 120)); }
  }

  // Success if ANY channel took it; all-channels-failed is a real 502 so the
  // form shows its mailto fallback instead of losing the lead.
  if (delivered.length === 0) return json({ error: 'delivery failed', detail: failures }, 502);
  return json({ ok: true, via: delivered }, 200);
}

async function readRawBody(req) {
  if (Buffer.isBuffer(req.rawBody)) return req.rawBody;
  if (Buffer.isBuffer(req.body)) return req.body;
  if (typeof req.body === 'string') return Buffer.from(req.body, 'utf8');
  const chunks = [];
  for await (const chunk of req) chunks.push(Buffer.from(chunk));
  return Buffer.concat(chunks);
}
