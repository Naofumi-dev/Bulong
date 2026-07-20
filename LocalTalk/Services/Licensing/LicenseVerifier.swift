import Foundation
import CryptoKit

struct LicenseVerifier {
    private let publicKey: Curve25519.Signing.PublicKey

    init(publicKey: Curve25519.Signing.PublicKey) {
        self.publicKey = publicKey
    }

    /// The bundled PRODUCTION public key. Safe to commit — it can only VERIFY.
    /// The matching private key was generated once via
    /// `sign_license.swift --genkey`, is held offline, and lives only in the
    /// license webhook's `LICENSE_PRIVATE_KEY_B64` env var. Never ship or commit it.
    /// Rotating this invalidates every license already sold.
    static let bundledPublicKeyB64 = "Kr4SZY0rx8k9VXIxHGhOM2jN93Pj95d/hNEtQ0O0PAo="

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
