import Foundation

enum DaemonConstants {
    static let label = "com.anantchowdhary.frictionblocker.daemon"
    static let socketPath = "/var/run/com.anantchowdhary.frictionblocker.sock"
    static let stateDirectory = "/Library/Application Support/FrictionBlocker"
    static let statePath = stateDirectory + "/daemon-state.json"
    static let systemSettingsPath = "/System/Applications/System Settings.app"
}

enum DaemonCommand: String, Codable, Sendable {
    case status
    case initialize
    case setGuardEnabled
    case setBlockedApps
    case setSchedule
    case configureQR
    case unlockWithQR
}

struct BlockedApp: Codable, Equatable, Sendable, Identifiable {
    var name: String
    var bundlePath: String
    var executablePath: String

    var id: String { bundlePath }
}

struct DaemonRequest: Codable, Sendable {
    let command: DaemonCommand
    var password: String?
    var guardEnabled: Bool?
    var blockedApps: [BlockedApp]?
    var schedule: GuardSchedule?
    var qrToken: String?

    init(
        command: DaemonCommand,
        password: String? = nil,
        guardEnabled: Bool? = nil,
        blockedApps: [BlockedApp]? = nil,
        schedule: GuardSchedule? = nil,
        qrToken: String? = nil
    ) {
        self.command = command
        self.password = password
        self.guardEnabled = guardEnabled
        self.blockedApps = blockedApps
        self.schedule = schedule
        self.qrToken = qrToken
    }
}

struct DaemonStatus: Codable, Equatable, Sendable {
    var initialized: Bool
    var guardActive: Bool
    var nextPasswordAttempt: Date?
    var systemSettingsRunning: Bool
    var blockedApps: [BlockedApp]
    var schedule: GuardSchedule? = nil
    var qrConfigured: Bool? = nil
}

struct DaemonResponse: Codable, Sendable {
    let success: Bool
    let message: String
    let status: DaemonStatus?
}

/// Daily wall-clock schedule in the Mac's current local time zone.
struct GuardSchedule: Codable, Equatable, Sendable {
    var enabled: Bool
    var startMinute: Int
    var endMinute: Int

    static let nightly = GuardSchedule(enabled: true, startMinute: 22 * 60, endMinute: 6 * 60)

    var isValid: Bool {
        (0..<1440).contains(startMinute) && (0..<1440).contains(endMinute)
            && startMinute != endMinute
    }

    func contains(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard isValid else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if startMinute < endMinute {
            return minute >= startMinute && minute < endMinute
        }
        return minute >= startMinute || minute < endMinute
    }
}
