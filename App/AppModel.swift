import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case setup
        case guarded
        case unguarded
        case unavailable
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var daemonStatus: DaemonStatus?
    @Published private(set) var generatedPassword = ""
    @Published var setupConfirmation = ""
    @Published var guardPassword = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var noticeMessage: String?
    @Published private(set) var isBusy = false
    @Published private(set) var now = Date()

    private let client = DaemonClient()
    private var clockTimer: Timer?

    init() {
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        refreshStatus()
    }

    var canAttemptPassword: Bool {
        guard let date = daemonStatus?.nextPasswordAttempt else { return true }
        return now >= date
    }

    func refreshStatus() {
        perform(DaemonRequest(command: .status), successNotice: nil)
    }

    func generatePassword() {
        clearMessages()
        do {
            generatedPassword = try PasswordPolicy.generate()
            setupConfirmation = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finishSetup() {
        clearMessages()
        guard setupConfirmation == generatedPassword else {
            errorMessage = "The confirmation does not match the generated password."
            return
        }
        let password = generatedPassword
        perform(
            DaemonRequest(command: .initialize, password: password),
            successNotice: "System Settings Guard is active."
        )
        generatedPassword = ""
        setupConfirmation = ""
    }

    func disableGuardAndOpenSettings() {
        guard canAttemptPassword else {
            errorMessage = "Wait for the failed-attempt cooldown before trying again."
            return
        }
        let password = guardPassword
        guardPassword = ""
        perform(
            DaemonRequest(
                command: .setGuardEnabled,
                password: password,
                guardEnabled: false
            ),
            successNotice: "Settings Guard is disabled until you turn it back on."
        ) { [weak self] in
            self?.openSystemSettings()
        }
    }

    func openSystemSettings() {
        NSWorkspace.shared.open(URL(fileURLWithPath: DaemonConstants.systemSettingsPath))
    }

    func enableGuard() {
        perform(
            DaemonRequest(command: .setGuardEnabled, guardEnabled: true),
            successNotice: "System Settings Guard is active."
        )
    }

    private func tick() {
        now = Date()
    }

    private func perform(
        _ request: DaemonRequest,
        successNotice: String?,
        onSuccess: (() -> Void)? = nil
    ) {
        clearMessages()
        isBusy = true
        Task {
            do {
                let response = try await Task.detached { [client] in
                    try client.send(request)
                }.value
                isBusy = false
                if response.success {
                    if let successNotice { noticeMessage = successNotice }
                    onSuccess?()
                } else {
                    errorMessage = response.message
                }
                if let status = response.status { apply(status) }
            } catch {
                isBusy = false
                phase = .unavailable
                errorMessage = error.localizedDescription
            }
        }
    }

    private func apply(_ status: DaemonStatus) {
        daemonStatus = status
        now = Date()

        if !status.initialized {
            phase = .setup
            if generatedPassword.isEmpty { generatePassword() }
        } else if status.guardActive {
            phase = .guarded
        } else {
            phase = .unguarded
        }
    }

    private func clearMessages() {
        errorMessage = nil
        noticeMessage = nil
    }
}
