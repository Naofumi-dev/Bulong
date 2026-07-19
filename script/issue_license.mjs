// Manually issue (or re-issue) a Bulong license key — for support requests,
// comps, or testing. Uses the SAME signer as the purchase webhook, so keys are
// identical to what buyers receive.
//
//   export LICENSE_PRIVATE_KEY_B64=...            # the offline production seed
//   node script/issue_license.mjs --name "Jo Cruz" --email jo@x.com --order COMP-1
//   node script/issue_license.mjs ... --issued 2026-07-19T10:00:00Z   # reproduce an exact key
//
// Prints the token to stdout. To also email it, pipe into your own tooling or
// extend with sendLicenseEmail from site/api/_lib/email.mjs.
import { signLicense } from '../site/api/_lib/license.mjs';

function arg(name) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : undefined;
}

const privB64 = process.env.LICENSE_PRIVATE_KEY_B64;
const name = arg('name');
const email = arg('email');
const order = arg('order');
const issued = arg('issued'); // optional; omit for "now"

if (!privB64) {
  process.stderr.write('set LICENSE_PRIVATE_KEY_B64 (the offline production seed)\n');
  process.exit(1);
}
if (!name || !email || !order) {
  process.stderr.write('usage: --name <name> --email <email> --order <ref> [--issued <iso8601>]\n');
  process.exit(1);
}

process.stdout.write(signLicense({ privB64, name, email, order, issued }) + '\n');
