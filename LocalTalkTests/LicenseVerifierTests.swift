import XCTest
import CryptoKit
@testable import Bulong

final class LicenseVerifierTests: XCTestCase {
    private func verifier() -> LicenseVerifier {
        let pub = try! Curve25519.Signing.PublicKey(
            rawRepresentation: Data(base64Encoded: LicenseFixtures.testPublicKeyB64)!)
        return LicenseVerifier(publicKey: pub)
    }

    func testValidTokenVerifies() {
        let result = verifier().verify(LicenseFixtures.validToken)
        guard case .success(let lic) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(lic.name, LicenseFixtures.validName)
        XCTAssertEqual(lic.order, "TEST-0001")
    }

    func testMalformedTokenRejected() {
        XCTAssertEqual(verifier().verify("not-a-token"), .failure(.malformed))
        XCTAssertEqual(verifier().verify("only.one.dot.too.many"), .failure(.malformed))
        XCTAssertEqual(verifier().verify(""), .failure(.malformed))
    }

    func testTamperedPayloadRejected() {
        // Flip a character in the payload half — signature must fail.
        var parts = LicenseFixtures.validToken.split(separator: ".").map(String.init)
        let first = parts[0]
        let flipped = String(first.dropLast()) + (first.hasSuffix("A") ? "B" : "A")
        parts[0] = flipped
        XCTAssertEqual(verifier().verify(parts.joined(separator: ".")), .failure(.badSignature))
    }

    func testWrongKeyRejected() {
        // A token signed by a different private key must not verify against our public key.
        let otherPriv = Curve25519.Signing.PrivateKey()
        let payload = try! JSONSerialization.data(
            withJSONObject: ["name":"X","email":"x@x","order":"O","issued":"2026-01-01T00:00:00Z"],
            options: [.sortedKeys])
        let sig = try! otherPriv.signature(for: payload)
        func b64url(_ d: Data) -> String {
            d.base64EncodedString().replacingOccurrences(of:"+",with:"-")
                .replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
        }
        XCTAssertEqual(verifier().verify("\(b64url(payload)).\(b64url(sig))"), .failure(.badSignature))
    }
}
