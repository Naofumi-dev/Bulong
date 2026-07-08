import Foundation
import CryptoKit

// Usage:
//   swift script/sign_license.swift --genkey
//   swift script/sign_license.swift --priv <base64-privkey> --name "Jo" --email "jo@x.com" --order "TEST-1"
func arg(_ n: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: n), i + 1 < a.count else { return nil }
    return a[i + 1]
}
func b64url(_ d: Data) -> String {
    d.base64EncodedString().replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

if CommandLine.arguments.contains("--genkey") {
    let key = Curve25519.Signing.PrivateKey()
    print("PRIVATE(base64): \(key.rawRepresentation.base64EncodedString())")
    print("PUBLIC(base64):  \(key.publicKey.rawRepresentation.base64EncodedString())")
    exit(0)
}

guard let privB64 = arg("--priv"),
      let priv = Data(base64Encoded: privB64),
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: priv),
      let name = arg("--name"), let email = arg("--email"), let order = arg("--order") else {
    FileHandle.standardError.write(Data("need --priv --name --email --order (or --genkey)\n".utf8)); exit(1)
}
let iso = ISO8601DateFormatter()
let payload: [String: String] = ["name": name, "email": email, "order": order, "issued": iso.string(from: Date())]
let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
let sig = try key.signature(for: payloadData)
print("\(b64url(payloadData)).\(b64url(sig))")
