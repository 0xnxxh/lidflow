import Foundation
import CryptoKit
// Independently verify the archive with only the public key shipped to users.
let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: CommandLine.arguments[1])!)
let signature = Data(base64Encoded: CommandLine.arguments[2])!
let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
guard key.isValidSignature(signature, for: archive) else {
    fputs("Invalid Sparkle Ed25519 signature\n", stderr); exit(1)
}
print("Sparkle Ed25519 signature verified against shipped public key")
