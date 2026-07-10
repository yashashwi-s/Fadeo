#!/usr/bin/env swift
// Offline license key generator. Mirrors FadeoCore/License.swift's format exactly
// (prefix "FADEO1", payload/signature both base64url) but stays a standalone script —
// deliberately not linked against FadeoCore — so minting a key never needs Xcode or a
// built app, just this file and the private key.
//
// Usage:
//   FADEO_LICENSE_PRIVATE_KEY=<hex> swift scripts/generate-license.swift ["a note"]
//
// The private key is read only from the environment, never from an argument (arguments
// end up in shell history and `ps`). It is intentionally not checked into this repo;
// see ~/.fadeo-secrets/license-signing-key.txt.

import CryptoKit
import Foundation

guard let privateKeyHex = ProcessInfo.processInfo.environment["FADEO_LICENSE_PRIVATE_KEY"], !privateKeyHex.isEmpty else {
    FileHandle.standardError.write(Data("error: set FADEO_LICENSE_PRIVATE_KEY (hex-encoded Curve25519 signing key)\n".utf8))
    exit(1)
}

let note = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil

struct LicensePayload: Codable {
    var id: String
    var issuedAt: Date
    var note: String?
}

extension Data {
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
        self = Data(bytes)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

guard let keyData = Data(hexEncoded: privateKeyHex),
      let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData) else {
    FileHandle.standardError.write(Data("error: FADEO_LICENSE_PRIVATE_KEY is not a valid hex-encoded Curve25519 key\n".utf8))
    exit(1)
}

let payload = LicensePayload(id: UUID().uuidString, issuedAt: Date(), note: note)

let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
let payloadData: Data
do {
    payloadData = try encoder.encode(payload)
} catch {
    FileHandle.standardError.write(Data("error: failed to encode payload: \(error)\n".utf8))
    exit(1)
}

guard let signature = try? privateKey.signature(for: payloadData) else {
    FileHandle.standardError.write(Data("error: signing failed\n".utf8))
    exit(1)
}

let key = "FADEO1.\(payloadData.base64URLEncodedString()).\(signature.base64URLEncodedString())"
print(key)
FileHandle.standardError.write(Data("issued: \(payload.id)\(note.map { " (\($0))" } ?? "")\n".utf8))
