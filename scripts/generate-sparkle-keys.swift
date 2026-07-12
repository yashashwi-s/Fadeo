#!/usr/bin/env swift
// One-time Sparkle EdDSA keypair generator. Prints both halves; the private key must be
// saved to ~/.fadeo-secrets/sparkle-signing-key.txt (matching the license key's
// convention, see generate-license.swift) and NEVER committed. The public key goes into
// project.yml's SUPublicEDKey Info.plist setting -- that half is safe to ship.
//
// This is Sparkle's own EdDSA (Ed25519) scheme, unrelated to Apple code signing/Developer
// ID: it's how Sparkle verifies an update package hasn't been tampered with in transit,
// nothing more. Reuses the same raw-hex-seed convention as the license signing key so
// both secrets are handled identically on this machine.

import CryptoKit
import Foundation

let key = Curve25519.Signing.PrivateKey()
let privateHex = key.rawRepresentation.map { String(format: "%02x", $0) }.joined()
let publicBase64 = key.publicKey.rawRepresentation.base64EncodedString()

print("Private key (hex -- save to ~/.fadeo-secrets/sparkle-signing-key.txt, never commit):")
print(privateHex)
print("")
print("Public key (base64 -- paste into project.yml's SUPublicEDKey):")
print(publicBase64)
