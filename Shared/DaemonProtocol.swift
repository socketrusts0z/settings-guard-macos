import Foundation

enum DaemonConstants {
    static let label = "com.anantchowdhary.frictionblocker.daemon"
    static let socketPath = "/var/run/com.anantchowdhary.frictionblocker.sock"
    static let stateDirectory = "/Library/Application Support/FrictionBlocker"
    static let statePath = stateDirectory + "/daemon-state.json"
    static let systemSettingsPath = "/System/Applications/System Settings.app"
    static let defaultAuthorizationSeconds: TimeInterval = 5 * 60
    static let maximumAuthorizationSeconds: TimeInterval = 30 * 60
}

enum DaemonCommand: String, Codable, Sendable {
    case status
    case initialize
    case authorizeSettings
    case lockSettings
}

struct DaemonRequest: Codable, Sendable {
    let command: DaemonCommand
    var password: String?
    var durationSeconds: TimeInterval?

    init(
        command: DaemonCommand,
        password: String? = nil,
        durationSeconds: TimeInterval? = nil
    ) {
        self.command = command
        self.password = password
        self.durationSeconds = durationSeconds
    }
}

struct DaemonStatus: Codable, Equatable, Sendable {
    var initialized: Bool
    var guardActive: Bool
    var authorizedUntil: Date?
    var nextPasswordAttempt: Date?
    var systemSettingsRunning: Bool
}

struct DaemonResponse: Codable, Sendable {
    let success: Bool
    let message: String
    let status: DaemonStatus?
}
