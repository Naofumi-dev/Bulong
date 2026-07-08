import Foundation
import CryptoKit

struct LicenseVerifier {
    private let publicKey: Curve25519.Signing.PublicKey

    init(publicKey: Curve25519.Signing.PublicKey) {
        self.publicKey = publicKey
    }

    /// The bundled PRODUCTION public key. REPLACE the base64 below with the
    /// production key before shipping (the matching private key is generated
    /// once via `sign_license.swift --genkey` and kept offline, never committed).
    /// Until then this equals the committed test key — a launch blocker if unswapped.
    static let bundledPublicKeyB64 = "o68OJn5GMgqyDX44U3U7lWcvOBA3dIRKRHJnNeAvxc0="

    static func bundled() -> LicenseVerifier {
        let data = Data(base64Encoded: bundledPublicKeyB64)!
        let key = try! Curve25519.Signing.PublicKey(rawRepresentation: data)
        return LicenseVerifier(publicKey: key)
    }

    func verify(_ token: String) -> Result<License, LicenseError> {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let payload = Self.b64urlDecode(String(parts[0])),
              let sig = Self.b64urlDecode(String(parts[1])),
              !payload.isEmpty, !sig.isEmpty else {
            return .failure(.malformed)
        }
        guard publicKey.isValidSignature(sig, for: payload) else {
            return .failure(.badSignature)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let license = try? decoder.decode(License.self, from: payload) else {
            return .failure(.unreadablePayload)
        }
        return .success(license)
    }

    private static func b64urlDecode(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }
}
