import CryptoKit
import Foundation

enum SigningError: Error {
    case invalidArguments, missingPrivateKey
}

let arguments = CommandLine.arguments.dropFirst()
switch (arguments.first, arguments.count) {
case ("generate-key", 1):
    print(Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString())
case ("public-key", 1), ("sign", 3):
    guard let encoded = ProcessInfo.processInfo.environment["MAC_UPDATE_PRIVATE_KEY"],
          let data = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        throw SigningError.missingPrivateKey
    }
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    if arguments.first == "public-key" {
        FileHandle.standardOutput.write(key.publicKey.rawRepresentation)
    } else {
        let archive = URL(fileURLWithPath: CommandLine.arguments[2])
        let signature = URL(fileURLWithPath: CommandLine.arguments[3])
        try key.signature(for: Data(contentsOf: archive, options: .mappedIfSafe)).write(to: signature)
    }
default: throw SigningError.invalidArguments
}
