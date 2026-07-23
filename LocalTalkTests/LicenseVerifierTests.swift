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
        // Empty-half and part-count boundaries must reject as malformed, NOT badSignature.
        XCTAssertEqual(verifier().verify("a."), .failure(.malformed))
        XCTAssertEqual(verifier().verify(".b"), .failure(.malformed))
        XCTAssertEqual(verifier().verify("a.b.c"), .failure(.malformed))     // exactly 3 parts
    }

    func testWhitespaceInPastedTokenIsTolerated() {
        // Plain-text email clients hard-wrap the ~250-char key at ~78 columns;
        // base64url never contains whitespace, so stripping it is always safe.
        // A paying customer's wrapped paste MUST activate.
        let token = LicenseFixtures.validToken
        // Surrounding whitespace (sloppy select-all copy).
        guard case .success = verifier().verify(" \(token) \n") else {
            return XCTFail("surrounding whitespace must be tolerated")
        }
        // Hard-wrapped: a newline every 60 chars, like a text/plain mail body.
        var wrapped = ""
        for (i, ch) in token.enumerated() {
            if i > 0 && i % 60 == 0 { wrapped.append("\n") }
            wrapped.append(ch)
        }
        guard case .success(let lic) = verifier().verify(wrapped) else {
            return XCTFail("hard-wrapped token must verify")
        }
        XCTAssertEqual(lic.name, LicenseFixtures.validName)
    }

    func testUnreadablePayloadRejected() {
        // A payload the test key legitimately signs but that is NOT a License:
        // the signature verifies, yet JSON decoding into License must fail.
        let priv = try! Curve25519.Signing.PrivateKey(
            rawRepresentation: Data(base64Encoded: LicenseFixtures.testPrivateKeyB64)!)
        func b64url(_ d: Data) -> String {
            d.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        func token(payload: Data) -> String {
            let sig = try! priv.signature(for: payload)
            return "\(b64url(payload)).\(b64url(sig))"
        }
        // (a) Valid JSON that isn't a License.
        let notALicense = try! JSONSerialization.data(withJSONObject: ["foo": "bar"], options: [])
        XCTAssertEqual(verifier().verify(token(payload: notALicense)), .failure(.unreadablePayload))
        // (b) Non-JSON bytes.
        XCTAssertEqual(verifier().verify(token(payload: Data("hello".utf8))), .failure(.unreadablePayload))
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
