#!/bin/bash
# Guards the cross-language license contract: a token signed by the Node signer
# (site/api/_lib/license.mjs, used by the purchase webhook) MUST verify with the
# app's CryptoKit LicenseVerifier. If this breaks, buyers can't activate.
#
# Run: script/test_license_interop.sh
set -euo pipefail
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1) Fresh keypair (as the production one is generated).
KP="$(swift script/sign_license.swift --genkey)"
PRIV="$(echo "$KP" | awk -F': +' '/PRIVATE/{print $2}')"
PUB="$(echo "$KP" | awk -F': +' '/PUBLIC/{print $2}')"

# 2) Node signs a token through the SAME lib the webhook uses.
TOKEN="$(LICENSE_PRIVATE_KEY_B64="$PRIV" node script/issue_license.mjs \
  --name 'Jo Cruz' --email 'jo@example.com' --order 'INTEROP-1')"

# 3) A Swift verifier mirroring LicenseVerifier must accept it and decode cleanly.
cat > "$TMP/verify.swift" <<'SWIFT'
import Foundation
import CryptoKit
func b64urlDecode(_ s: String) -> Data? {
    var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while t.count % 4 != 0 { t += "=" }
    return Data(base64Encoded: t)
}
struct License: Codable { var name: String; var email: String; var order: String; var issued: Date }
let pub = try! Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: CommandLine.arguments[1])!)
let parts = CommandLine.arguments[2].split(separator: ".", omittingEmptySubsequences: false)
guard parts.count == 2, let payload = b64urlDecode(String(parts[0])), let sig = b64urlDecode(String(parts[1])),
      !payload.isEmpty, !sig.isEmpty else { print("MALFORMED"); exit(1) }
guard pub.isValidSignature(sig, for: payload) else { print("BAD_SIGNATURE"); exit(2) }
let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
guard let lic = try? dec.decode(License.self, from: payload) else { print("UNREADABLE_PAYLOAD"); exit(3) }
print("OK \(lic.order)")
SWIFT

RESULT="$(swift "$TMP/verify.swift" "$PUB" "$TOKEN")"
if [ "$RESULT" = "OK INTEROP-1" ]; then
  echo "PASS — Node-signed license verifies in CryptoKit ($RESULT)"
else
  echo "FAIL — verifier said: $RESULT"; exit 1
fi
