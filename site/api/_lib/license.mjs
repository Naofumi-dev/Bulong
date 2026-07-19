// Ed25519 license-token signer — produces exactly what the app's Swift
// LicenseVerifier (CryptoKit) accepts. Verified interoperable with CryptoKit:
//   token = base64url(payloadJSON) + "." + base64url(ed25519 signature)
//   payload = {name, email, order, issued}, issued = ISO8601 WHOLE seconds.
//
// Zero dependencies (Node built-in crypto only). Files under api/_lib are not
// routed by Vercel (leading underscore), so this stays a private helper.
import crypto from 'node:crypto';

const b64url = (buf) =>
  Buffer.from(buf).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

// CryptoKit's Curve25519 private key is a raw 32-byte seed; Node wants PKCS8
// DER, so wrap the seed with the fixed Ed25519 PKCS8 prefix (RFC 8410).
function keyFromSeed(seedB64) {
  const seed = Buffer.from(seedB64, 'base64');
  if (seed.length !== 32) {
    throw new Error(`LICENSE_PRIVATE_KEY_B64 must be a 32-byte Ed25519 seed, got ${seed.length} bytes`);
  }
  const der = Buffer.concat([Buffer.from('302e020100300506032b657004220420', 'hex'), seed]);
  return crypto.createPrivateKey({ key: der, format: 'der', type: 'pkcs8' });
}

// Swift's JSONDecoder.iso8601 (ISO8601DateFormatter) REJECTS fractional seconds.
// JS toISOString() and Lemon Squeezy timestamps include them — normalize to
// whole seconds or the app will fail to decode the payload.
export function isoSeconds(input) {
  const d = input ? new Date(input) : new Date();
  if (Number.isNaN(d.getTime())) throw new Error(`invalid issued date: ${input}`);
  return d.toISOString().replace(/\.\d+Z$/, 'Z');
}

// Deterministic: same (name,email,order,issued) → byte-identical token. Feed a
// fixed `issued` (the order's created_at) and you can re-issue a lost key with
// no database — it reproduces exactly.
export function signLicense({ privB64, name, email, order, issued }) {
  if (!privB64) throw new Error('missing signing key (LICENSE_PRIVATE_KEY_B64)');
  const payload = {
    email: String(email),
    issued: isoSeconds(issued),
    name: String(name),
    order: String(order),
  };
  const json = JSON.stringify(payload, Object.keys(payload).sort());
  const bytes = Buffer.from(json, 'utf8');
  const sig = crypto.sign(null, bytes, keyFromSeed(privB64));
  return `${b64url(bytes)}.${b64url(sig)}`;
}
