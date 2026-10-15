// Exports one code-signing identity (certificate and private key) from a
// keychain to a password-protected .p12 file. Unlike `security export`, which
// exports every identity in the keychain, this exports only the named one.
// Usage: swift scripts/export-signing-identity.swift <name> <output.p12> <password>
import Foundation
import Security

let arguments = CommandLine.arguments
guard arguments.count >= 4 else {
    FileHandle.standardError.write("Usage: export-signing-identity.swift <name> <output.p12> <password>\n".data(using: .utf8)!)
    exit(2)
}
let name = arguments[1]
let output = URL(fileURLWithPath: arguments[2])
let password = arguments[3]

let query: [String: Any] = [
    kSecClass as String: kSecClassIdentity,
    kSecMatchLimit as String: kSecMatchLimitAll,
    kSecReturnRef as String: true,
]

var result: CFTypeRef?
guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let identities = result as? [SecIdentity]
else {
    FileHandle.standardError.write("No signing identities found.\n".data(using: .utf8)!)
    exit(1)
}

let matches = identities.filter { identity in
    var certificate: SecCertificate?
    SecIdentityCopyCertificate(identity, &certificate)
    return certificate.flatMap { SecCertificateCopySubjectSummary($0) as String? } == name
}
guard matches.count == 1, let identity = matches.first else {
    FileHandle.standardError.write("Expected one identity named \"\(name)\", found \(matches.count).\n".data(using: .utf8)!)
    exit(1)
}

var parameters = SecItemImportExportKeyParameters()
parameters.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
parameters.passphrase = Unmanaged.passUnretained(password as CFString)

var data: CFData?
let status = SecItemExport(identity, .formatPKCS12, [], &parameters, &data)
guard status == errSecSuccess, let data else {
    FileHandle.standardError.write("Export failed (\(status)).\n".data(using: .utf8)!)
    exit(1)
}
FileManager.default.createFile(atPath: output.path, contents: data as Data, attributes: [.posixPermissions: 0o600])
print("Exported \"\(name)\" to \(output.path)")
