// update_key.swift — makes and uses the Ed25519 key that signs Bismillah updates.
//
//   update_key keygen <private-key-file>        create a new key (refuses to overwrite); prints the public key
//   update_key pubkey <private-key-file>        print the public key (base64)
//   update_key sign   <private-key-file> <file> print a base64 signature of <file>
//
// The app embeds the public key and only installs an update whose zip carries a valid signature,
// so a hijacked GitHub account or release page alone can't push code to your users.
// The private key stays on your machine (never commit it). Lose it and existing installs can no
// longer update by themselves; keep a backup.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func loadKey(_ path: String) -> Curve25519.Signing.PrivateKey {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8),
          let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    else { fail("Can't read a signing key from \(path)") }
    return key
}

let args = CommandLine.arguments
guard args.count >= 3 else { fail("usage: update_key keygen|pubkey|sign <private-key-file> [file]") }

switch args[1] {
case "keygen":
    let path = (args[2] as NSString).expandingTildeInPath
    if FileManager.default.fileExists(atPath: path) { fail("\(path) already exists; not overwriting it") }
    let key = Curve25519.Signing.PrivateKey()
    try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                             withIntermediateDirectories: true,
                                             attributes: [.posixPermissions: 0o700])
    let created = FileManager.default.createFile(atPath: path,
                                                 contents: Data((key.rawRepresentation.base64EncodedString() + "\n").utf8),
                                                 attributes: [.posixPermissions: 0o600])
    if !created { fail("Couldn't write \(path)") }
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "pubkey":
    print(loadKey((args[2] as NSString).expandingTildeInPath).publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard args.count >= 4, let data = FileManager.default.contents(atPath: args[3]) else { fail("usage: update_key sign <private-key-file> <file>") }
    let signature = try loadKey((args[2] as NSString).expandingTildeInPath).signature(for: data)
    print(signature.base64EncodedString())
default:
    fail("unknown command \(args[1])")
}
