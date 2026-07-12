#!/usr/bin/env swift
// Signs a release zip with Sparkle's EdDSA scheme and prints an appcast.xml to stdout.
// Standalone (no Sparkle/FadeoCore dependency) so CI doesn't need a built app just to
// run this. Mirrors generate-license.swift's "read the private key from the environment
// only" rule -- it never ends up in shell history or `ps`.
//
// Usage:
//   SPARKLE_PRIVATE_KEY=<hex> swift scripts/sign-appcast.swift \
//     <zipPath> <version e.g. 0.3.0> <build e.g. 4> <enclosureURL> > appcast.xml

import CryptoKit
import Foundation

let args = CommandLine.arguments
guard args.count == 5 else {
    FileHandle.standardError.write(Data("usage: sign-appcast.swift <zipPath> <version> <build> <enclosureURL>\n".utf8))
    exit(1)
}
let zipPath = args[1]
let version = args[2]
let build = args[3]
let enclosureURL = args[4]

guard let privateKeyHex = ProcessInfo.processInfo.environment["SPARKLE_PRIVATE_KEY"], !privateKeyHex.isEmpty else {
    FileHandle.standardError.write(Data("error: set SPARKLE_PRIVATE_KEY (hex-encoded Curve25519 signing key)\n".utf8))
    exit(1)
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
}

guard let keyData = Data(hexEncoded: privateKeyHex),
      let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData) else {
    FileHandle.standardError.write(Data("error: SPARKLE_PRIVATE_KEY is not a valid hex-encoded Curve25519 key\n".utf8))
    exit(1)
}

guard let fileData = FileManager.default.contents(atPath: zipPath) else {
    FileHandle.standardError.write(Data("error: could not read \(zipPath)\n".utf8))
    exit(1)
}

guard let signature = try? privateKey.signature(for: fileData) else {
    FileHandle.standardError.write(Data("error: signing failed\n".utf8))
    exit(1)
}

let signatureBase64 = signature.base64EncodedString()
let length = fileData.count
let pubDate = { () -> String in
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
    f.timeZone = TimeZone(identifier: "UTC")
    return f.string(from: Date())
}()

func xmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

print("""
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Fadeo</title>
    <item>
      <title>Version \(xmlEscape(version))</title>
      <pubDate>\(pubDate)</pubDate>
      <sparkle:version>\(xmlEscape(build))</sparkle:version>
      <sparkle:shortVersionString>\(xmlEscape(version))</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure url="\(xmlEscape(enclosureURL))" sparkle:edSignature="\(signatureBase64)" length="\(length)" type="application/octet-stream" />
    </item>
  </channel>
</rss>
""")
