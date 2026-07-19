// Delivers the license key by email via Resend's REST API (no SDK dependency —
// global fetch only). Swap the fetch call if you prefer Postmark/SES/SMTP; the
// webhook handler only needs `sendLicenseEmail` to resolve or throw.
const ACTIVATE_STEPS =
  'To activate: open Bulong → Settings → Advanced → License, paste the key below, and click Activate.';

export async function sendLicenseEmail({ apiKey, from, to, name, licenseKey, orderRef }) {
  const greeting = name ? `Hi ${name},` : 'Hi,';
  const subject = 'Your Bulong license key';

  const text = [
    greeting,
    '',
    'Salamat for buying Bulong! Here is your license key:',
    '',
    licenseKey,
    '',
    ACTIVATE_STEPS,
    '',
    'The key works offline and is tied to your purchase, not to any account.',
    'Keep this email — replying to it reaches a human if you need help.',
    '',
    `Order: ${orderRef}`,
    '— Bulong',
  ].join('\n');

  const html = `
    <div style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;max-width:520px;margin:0 auto;color:#0b1210">
      <p>${greeting}</p>
      <p>Salamat for buying <strong>Bulong</strong>! Here is your license key:</p>
      <pre style="background:#0b1210;color:#b0f9e2;padding:14px 16px;border-radius:10px;
                  font-family:ui-monospace,SF Mono,Menlo,monospace;font-size:13px;
                  white-space:pre-wrap;word-break:break-all">${escapeHtml(licenseKey)}</pre>
      <p>${ACTIVATE_STEPS}</p>
      <p style="color:#4a5551;font-size:14px">The key works offline and is tied to your purchase,
         not to any account. Keep this email — replying to it reaches a human if you need help.</p>
      <p style="color:#8a9490;font-size:12px">Order: ${escapeHtml(orderRef)} · — Bulong</p>
    </div>`;

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from, to, subject, text, html }),
  });
  if (!res.ok) {
    throw new Error(`resend ${res.status}: ${(await res.text()).slice(0, 300)}`);
  }
  return res.json();
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
