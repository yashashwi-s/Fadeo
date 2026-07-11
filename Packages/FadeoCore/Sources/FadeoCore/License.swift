import Foundation
import CryptoKit

/// What a valid license key decodes to. Deliberately minimal: nothing here identifies a
/// person unless they choose to put an email in `note` (optional, purely informational,
/// never required for verification).
public struct LicensePayload: Codable, Sendable, Equatable {
    public var id: String
    public var issuedAt: Date
    public var note: String?
    /// Set only on free-giveaway keys: if this key is never activated (entered into the
    /// app) before this date, `LicenseManager.activate` refuses it. Once activated, the
    /// license is permanent — this deadline is never re-checked on later launches, only
    /// at the moment of first activation. `nil` for every paid key (no such deadline).
    public var mustActivateBy: Date?

    public init(id: String = UUID().uuidString, issuedAt: Date = Date(), note: String? = nil,
                mustActivateBy: Date? = nil) {
        self.id = id
        self.issuedAt = issuedAt
        self.note = note
        self.mustActivateBy = mustActivateBy
    }
}

/// Offline Ed25519 license verification, no network call, ever (PLAN.md §13). A license
/// key is `FADEO1.<payload-base64url>.<signature-base64url>`. The public key below is
/// safe to ship; only the matching private key (kept outside this repo, see
/// scripts/generate-license.swift) can produce a signature this verifies.
public enum License {
    private static let publicKeyHex = "a7cdd0193c82d6806a6a9cf171cd23af75d11eb65135289a7deaff35b8173e1b"
    private static let prefix = "FADEO1"

    /// Returns the decoded payload if `key` is a well-formed, validly-signed license,
    /// nil for anything else (malformed, tampered, wrong key). Pure and deterministic;
    /// safe to call as often as needed with no cost beyond the computation itself.
    public static func verify(_ key: String) -> LicensePayload? {
        let parts = key.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard parts.count == 3, parts[0] == prefix else { return nil }
        guard let payloadData = Data(base64URLEncoded: String(parts[1])),
              let signatureData = Data(base64URLEncoded: String(parts[2])),
              let keyData = Data(hexEncoded: publicKeyHex),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else { return nil }
        guard publicKey.isValidSignature(signatureData, for: payloadData) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LicensePayload.self, from: payloadData)
    }

    /// Signs a payload given a raw private key (hex). Only used by the offline key
    /// generator script; never shipped in the app (the app only ever verifies).
    public static func sign(_ payload: LicensePayload, privateKeyHex: String) throws -> String {
        guard let keyData = Data(hexEncoded: privateKeyHex) else {
            throw NSError(domain: "License", code: 1, userInfo: [NSLocalizedDescriptionKey: "bad private key hex"])
        }
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payloadData = try encoder.encode(payload)
        let signature = try privateKey.signature(for: payloadData)
        return "\(prefix).\(payloadData.base64URLEncodedString()).\(signature.base64URLEncodedString())"
    }
}

// MARK: - Base64URL / hex helpers (small, self-contained, no extra dependency)

extension Data {
    init?(base64URLEncoded string: String) {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        self.init(base64Encoded: s)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(hexEncoded hex: String) {
        let chars = Array(hex)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let b = UInt8(String(chars[i...i+1]), radix: 16) else { return nil }
            bytes.append(b)
            i += 2
        }
        self.init(bytes)
    }
}
