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
}

struct DaemonRequest: Codable, Sendable {
    let command: DaemonCommand
    var password: String?
    var guardEnabled: Bool?

    init(
        command: DaemonCommand,
        password: String? = nil,
        guardEnabled: Bool? = nil
    ) {
        self.command = command
        self.password = password
        self.guardEnabled = guardEnabled
    }
}

struct DaemonStatus: Codable, Equatable, Sendable {
    var initialized: Bool
    var guardActive: Bool
    var nextPasswordAttempt: Date?
    var systemSettingsRunning: Bool
}

struct DaemonResponse: Codable, Sendable {
    let success: Bool
    let message: String
    let status: DaemonStatus?
}
