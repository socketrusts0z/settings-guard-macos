import Darwin
import Foundation

struct PersistentDaemonState: Codable, Equatable, Sendable {
    var credential: PasswordCredential?
    var guardEnabled: Bool
    var failedUnlockAttempts: Int
    var nextUnlockAttempt: Date?
    var blockedApps: [BlockedApp]
    var schedule: GuardSchedule
    var qrCredential: PasswordCredential?

    static let initial = PersistentDaemonState(
        credential: nil,
        guardEnabled: false,
        failedUnlockAttempts: 0,
        nextUnlockAttempt: nil,
        blockedApps: []
    )

    func protectionActive(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        credential != nil && (schedule.enabled ? schedule.contains(date, calendar: calendar) : guardEnabled)
    }

    enum UnlockProof {
        case password(String?)
        case qr(String?)
    }

    mutating func verifyUnlock(_ proof: UnlockProof, at now: Date = Date()) throws {
        guard let credential else { throw UnlockError.notConfigured }
        if let nextUnlockAttempt, now < nextUnlockAttempt {
            throw UnlockError.cooldown(nextUnlockAttempt)
        }
        let valid: Bool
        switch proof {
        case .password(let value):
            valid = value.map { credential.verifies($0) } ?? false
        case .qr(let value):
            guard let qrCredential else { throw UnlockError.qrNotConfigured }
            valid = value.map { BarcodeUnlockPayload.isValid($0) && qrCredential.verifies(BarcodeUnlockPayload.credentialInput(for: $0)) } ?? false
        }
        guard valid else {
            failedUnlockAttempts = min(failedUnlockAttempts + 1, 20)
            nextUnlockAttempt = now.addingTimeInterval(min(pow(2, Double(failedUnlockAttempts)), 300))
            throw UnlockError.incorrect
        }
        failedUnlockAttempts = 0
        nextUnlockAttempt = nil
    }

    mutating func disableProtection(using proof: UnlockProof, at now: Date = Date()) throws {
        try verifyUnlock(proof, at: now)
        schedule.enabled = false
        guardEnabled = false
    }

    mutating func configureQR(token: String?, password: String?, at now: Date = Date()) throws {
        if let token, !BarcodeUnlockPayload.isValid(token) { throw UnlockError.invalidQR }
        try verifyUnlock(.password(password), at: now)
        qrCredential = try token.map { try PasswordCredential.create(password: BarcodeUnlockPayload.credentialInput(for: $0)) }
    }

    private enum CodingKeys: String, CodingKey {
        case credential
        case guardEnabled
        case failedUnlockAttempts
        case nextUnlockAttempt
        case blockedApps
        case schedule
        case qrCredential
    }

    init(
        credential: PasswordCredential?,
        guardEnabled: Bool,
        failedUnlockAttempts: Int,
        nextUnlockAttempt: Date?,
        blockedApps: [BlockedApp] = [],
        schedule: GuardSchedule = .nightly,
        qrCredential: PasswordCredential? = nil
    ) {
        self.credential = credential
        self.guardEnabled = guardEnabled
        self.failedUnlockAttempts = failedUnlockAttempts
        self.nextUnlockAttempt = nextUnlockAttempt
        self.blockedApps = blockedApps
        self.schedule = schedule
        self.qrCredential = qrCredential
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        credential = try container.decodeIfPresent(PasswordCredential.self, forKey: .credential)
        // Older releases stored a temporary `authorizedUntil` value. On upgrade,
        // return to the safer guarded state instead of preserving temporary access.
        guardEnabled = try container.decodeIfPresent(Bool.self, forKey: .guardEnabled)
            ?? (credential != nil)
        failedUnlockAttempts = try container.decodeIfPresent(Int.self, forKey: .failedUnlockAttempts) ?? 0
        nextUnlockAttempt = try container.decodeIfPresent(Date.self, forKey: .nextUnlockAttempt)
        blockedApps = try container.decodeIfPresent([BlockedApp].self, forKey: .blockedApps) ?? []
        schedule = try container.decodeIfPresent(GuardSchedule.self, forKey: .schedule) ?? .nightly
        qrCredential = try container.decodeIfPresent(PasswordCredential.self, forKey: .qrCredential)
        guard schedule.isValid else {
            throw DecodingError.dataCorruptedError(forKey: .schedule, in: container,
                                                   debugDescription: "Invalid daily guard schedule")
        }
    }
}

enum UnlockError: LocalizedError {
    case notConfigured, qrNotConfigured, invalidQR, incorrect
    case cooldown(Date)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Configure a guard password first."
        case .qrNotConfigured: return "Set up a QR code or barcode before scanning to unlock."
        case .invalidQR: return "Choose a readable, non-empty QR code or barcode."
        case .incorrect: return "Incorrect password or unlock code."
        case .cooldown(let date):
            return "Wait until \(date.formatted(date: .omitted, time: .standard)) before trying again."
        }
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
