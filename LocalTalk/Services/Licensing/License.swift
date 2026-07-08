import Foundation

struct License: Codable, Equatable {
    var name: String
    var email: String
    var order: String
    var issued: Date
}

enum LicenseError: Error, Equatable {
    case malformed          // not a two-part base64url token
    case badSignature       // signature does not verify against the key
    case unreadablePayload  // signature ok but JSON won't decode
}

enum LicenseState: Equatable {
    case trial(daysLeft: Int)
    case trialExpired
    case licensed(License)
}
