import Foundation
@testable import Bulong

// TEST key pair + vectors ONLY. The production key is generated at launch and never committed.
enum LicenseFixtures {
    static let testPublicKeyB64 = "o68OJn5GMgqyDX44U3U7lWcvOBA3dIRKRHJnNeAvxc0="
    static let testPrivateKeyB64 = "nHxEGJ/kr9/G2QcXIsS2rXRVPP6emXo2/8BhX3Ir+hw="   // used to mint tokens in-test
    static let validToken = "eyJlbWFpbCI6InRlc3RAYnVsb25nLmFwcCIsImlzc3VlZCI6IjIwMjYtMDctMDhUMDU6NTQ6NDhaIiwibmFtZSI6IlRlc3QgVXNlciIsIm9yZGVyIjoiVEVTVC0wMDAxIn0.8o8vm6fT579VxbRlBZWWD4cgf5U6FtNo6Ls0s0x8g319DvkIjPo0qSAjgmTT9vYrCIPeKyaPE6JSALENNIZrCw"            // for Test User / test@bulong.app / TEST-0001
    static let validName = "Test User"
}
