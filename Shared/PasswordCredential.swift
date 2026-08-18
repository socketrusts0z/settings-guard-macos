import CryptoKit
import Foundation
import Security

enum PasswordPolicy {
    static let minimumLength = 20
    static let generatedLength = 24
    static let productionIterations = 120_000

    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*+-=")

    static func validate(_ password: String) -> Bool {
        password.count >= minimumLength
    }

    static func generate(length: Int = generatedLength) throws -> String {
        precondition(length >= minimumLength)
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw PasswordCredentialError.randomGenerationFailed(status)
        }
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }
}

enum PasswordCredentialError: LocalizedError {
    case passwordTooShort
    case randomGenerationFailed(OSStatus)
    case invalidRecord

    var errorDescription: String? {
        switch self {
        case .passwordTooShort:
            "The unlock password must contain at least \(PasswordPolicy.minimumLength) characters."
        case .randomGenerationFailed(let status):
            "Secure password generation failed (\(status))."
        case .invalidRecord:
            "The stored password record is invalid."
        }
    }
}

struct PasswordCredential: Codable, Equatable, Sendable {
    let salt: Data
    let verifier: Data
    let iterations: Int

    static func create(
        password: String,
        iterations: Int = PasswordPolicy.productionIterations
    ) throws -> PasswordCredential {
        guard PasswordPolicy.validate(password) else {
            throw PasswordCredentialError.passwordTooShort
        }
        var salt = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt)
        guard status == errSecSuccess else {
            throw PasswordCredentialError.randomGenerationFailed(status)
        }
        let key = PBKDF2.derive(
            password: Data(password.utf8),
            salt: Data(salt),
            iterations: iterations,
            outputByteCount: 32
        )
        return PasswordCredential(salt: Data(salt), verifier: key, iterations: iterations)
    }

    func verifies(_ password: String) -> Bool {
        guard PasswordPolicy.validate(password), iterations > 0, verifier.count == 32 else {
            return false
        }
        let candidate = PBKDF2.derive(
            password: Data(password.utf8),
            salt: salt,
            iterations: iterations,
            outputByteCount: verifier.count
        )
        return candidate.constantTimeEquals(verifier)
    }
}

private enum PBKDF2 {
    static func derive(
        password: Data,
        salt: Data,
        iterations: Int,
        outputByteCount: Int
    ) -> Data {
        precondition(iterations > 0)
        precondition(outputByteCount > 0)

        let key = SymmetricKey(data: password)
        let digestLength = SHA256.Digest.byteCount
        let blockCount = Int(ceil(Double(outputByteCount) / Double(digestLength)))
        var output = Data()
        output.reserveCapacity(blockCount * digestLength)

        for blockIndex in 1...blockCount {
            var blockSalt = salt
            var index = UInt32(blockIndex).bigEndian
            withUnsafeBytes(of: &index) { blockSalt.append(contentsOf: $0) }

            var u = Data(HMAC<SHA256>.authenticationCode(for: blockSalt, using: key))
            var result = u

            if iterations > 1 {
                for _ in 2...iterations {
                    u = Data(HMAC<SHA256>.authenticationCode(for: u, using: key))
                    result.xorInPlace(with: u)
                }
            }
            output.append(result)
        }

        return output.prefix(outputByteCount)
    }
}

private extension Data {
    mutating func xorInPlace(with other: Data) {
        let byteCount = Swift.min(count, other.count)
        withUnsafeMutableBytes { lhsBytes in
            other.withUnsafeBytes { rhsBytes in
                guard let lhs = lhsBytes.bindMemory(to: UInt8.self).baseAddress,
                      let rhs = rhsBytes.bindMemory(to: UInt8.self).baseAddress else { return }
                for index in 0..<byteCount {
                    lhs[index] ^= rhs[index]
                }
            }
        }
    }

    func constantTimeEquals(_ other: Data) -> Bool {
        guard count == other.count else { return false }
        var difference: UInt8 = 0
        for (lhs, rhs) in zip(self, other) {
            difference |= lhs ^ rhs
        }
        return difference == 0
    }
}
