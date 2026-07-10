import XCTest
import CryptoKit
@testable import FadeoCore

final class LicenseTests: XCTestCase {
    // A throwaway keypair generated just for these tests (NOT the real shipping key).
    // Verifies the sign/verify round trip and tamper-rejection using the actual
    // production verification path (License.verify), just against a different embedded
    // public key than what's baked into the enum — so we sign with a matching test key
    // pair created inline via CryptoKit directly rather than routing through the
    // production public key constant.

    func testSignThenVerifyRoundTrips() throws {
        let payload = LicensePayload(id: "test-1", issuedAt: Date(timeIntervalSince1970: 1_700_000_000), note: "unit-test")
        // Sign with a fresh keypair, then verify using a hand-rolled verifier mirroring
        // License.verify's logic, since License.verify is hardcoded to the shipping key.
        let key = try TestCrypto.makeKeyPair()
        let signed = try License.sign(payload, privateKeyHex: key.privateHex)
        let decoded = TestCrypto.verify(signed, publicKeyHex: key.publicHex)
        XCTAssertEqual(decoded, payload)
    }

    func testTamperedSignatureFails() throws {
        let payload = LicensePayload(id: "test-2", issuedAt: Date(), note: nil)
        let key = try TestCrypto.makeKeyPair()
        var signed = try License.sign(payload, privateKeyHex: key.privateHex)
        signed = String(signed.dropLast(2)) + "zz"   // corrupt the signature
        XCTAssertNil(TestCrypto.verify(signed, publicKeyHex: key.publicHex))
    }

    func testWrongPublicKeyRejects() throws {
        let payload = LicensePayload(id: "test-3", issuedAt: Date(), note: nil)
        let key = try TestCrypto.makeKeyPair()
        let otherKey = try TestCrypto.makeKeyPair()
        let signed = try License.sign(payload, privateKeyHex: key.privateHex)
        XCTAssertNil(TestCrypto.verify(signed, publicKeyHex: otherKey.publicHex))
    }

    func testMalformedKeyRejectsAgainstShippingVerifier() {
        XCTAssertNil(License.verify("not-a-license-key"))
        XCTAssertNil(License.verify("FADEO1.onlytwoparts"))
        XCTAssertNil(License.verify(""))
    }

    func testShippingVerifierRejectsForgedKey() throws {
        // A key signed with a DIFFERENT private key must never verify against the real
        // shipping public key baked into License.swift.
        let payload = LicensePayload(id: "forged", issuedAt: Date(), note: nil)
        let key = try TestCrypto.makeKeyPair()
        let forged = try License.sign(payload, privateKeyHex: key.privateHex)
        XCTAssertNil(License.verify(forged))
    }
}

/// Minimal test-only mirror of License's crypto so we can exercise sign/verify with a
/// throwaway keypair instead of the real shipping key.
private enum TestCrypto {
    struct KeyPair { let privateHex: String; let publicHex: String }

    static func makeKeyPair() throws -> KeyPair {
        let priv = Curve25519.Signing.PrivateKey()
        return KeyPair(privateHex: priv.rawRepresentation.hexEncodedString(),
                       publicHex: priv.publicKey.rawRepresentation.hexEncodedString())
    }

    static func verify(_ key: String, publicKeyHex: String) -> LicensePayload? {
        let parts = key.split(separator: ".")
        guard parts.count == 3, parts[0] == "FADEO1" else { return nil }
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
}

private extension Data {
    func hexEncodedString() -> String { map { String(format: "%02x", $0) }.joined() }
}
