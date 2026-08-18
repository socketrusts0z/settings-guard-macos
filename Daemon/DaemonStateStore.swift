import Darwin
import Foundation

struct PersistentDaemonState: Codable, Equatable, Sendable {
    var credential: PasswordCredential?
    var authorizedUntil: Date?
    var failedUnlockAttempts: Int
    var nextUnlockAttempt: Date?

    static let initial = PersistentDaemonState(
        credential: nil,
        authorizedUntil: nil,
        failedUnlockAttempts: 0,
        nextUnlockAttempt: nil
    )

    private enum CodingKeys: String, CodingKey {
        case credential
        case authorizedUntil
        case failedUnlockAttempts
        case nextUnlockAttempt
    }

    init(
        credential: PasswordCredential?,
        authorizedUntil: Date?,
        failedUnlockAttempts: Int,
        nextUnlockAttempt: Date?
    ) {
        self.credential = credential
        self.authorizedUntil = authorizedUntil
        self.failedUnlockAttempts = failedUnlockAttempts
        self.nextUnlockAttempt = nextUnlockAttempt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        credential = try container.decodeIfPresent(PasswordCredential.self, forKey: .credential)
        authorizedUntil = try container.decodeIfPresent(Date.self, forKey: .authorizedUntil)
        failedUnlockAttempts = try container.decodeIfPresent(Int.self, forKey: .failedUnlockAttempts) ?? 0
        nextUnlockAttempt = try container.decodeIfPresent(Date.self, forKey: .nextUnlockAttempt)
    }
}

final class DaemonStateStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL = URL(fileURLWithPath: DaemonConstants.statePath)) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() throws -> PersistentDaemonState {
        do {
            return try decoder.decode(PersistentDaemonState.self, from: Data(contentsOf: fileURL))
        } catch CocoaError.fileReadNoSuchFile {
            return .initial
        }
    }

    func save(_ state: PersistentDaemonState) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try encoder.encode(state).write(to: fileURL, options: .atomic)
        guard chmod(fileURL.path, 0o600) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
