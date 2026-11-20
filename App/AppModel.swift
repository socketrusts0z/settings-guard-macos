import AppKit
import Foundation
import UniformTypeIdentifiers

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
    @Published private(set) var availableApps: [BlockedApp] = []
    @Published private(set) var generatedPassword = ""
    @Published var setupConfirmation = ""
    @Published var guardPassword = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var noticeMessage: String?
    @Published private(set) var isBusy = false
    @Published private(set) var now = Date()

    private let client = DaemonClient()
    private var clockTimer: Timer?
    private var refreshingSchedule = false

    init() {
        refreshAvailableApps()
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
            successNotice: "Daily protection is scheduled for 10 p.m.–6 a.m."
        )
        generatedPassword = ""
        setupConfirmation = ""
    }

    func disableGuard() {
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
            successNotice: "Protection and its daily schedule are disabled. Enable the schedule to resume automatic protection."
        )
    }

    func unlockWithQR(_ token: String) {
        guard canAttemptPassword, !isBusy else { return }
        perform(DaemonRequest(command: .unlockWithQR, qrToken: token),
                successNotice: "Protection and its daily schedule are disabled. Enable the schedule to resume automatic protection.")
    }

    func configureQR(_ token: String?, password: String, onSuccess: (() -> Void)? = nil) {
        guard canAttemptPassword, !isBusy else { return }
        perform(DaemonRequest(command: .configureQR, password: password, qrToken: token),
                successNotice: token == nil ? "Code unlocking removed." : "Code unlocking enabled. Scan the same QR code or barcode to unlock.",
                onSuccess: onSuccess)
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

    func chooseBlockedApps() {
        guard phase == .unguarded else { return }
        let panel = NSOpenPanel()
        panel.message = "Choose apps to close while FrictionBlocker is enabled"
        panel.prompt = "Add Apps"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        guard panel.runModal() == .OK else { return }

        var apps = daemonStatus?.blockedApps ?? []
        for url in panel.urls {
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard !apps.contains(where: { $0.bundlePath == path }) else { continue }
            apps.append(BlockedApp(name: url.deletingPathExtension().lastPathComponent,
                                   bundlePath: path, executablePath: ""))
        }
        refreshAvailableApps()
        saveBlockedApps(apps)
    }

    func refreshAvailableApps() {
        let fileManager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        var directories = roots.map { ($0, 0) }
        var found: [BlockedApp] = []
        var seen = Set<String>()

        while !directories.isEmpty {
            let (directory, depth) = directories.removeFirst()
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            ) else { continue }

            for item in contents {
                let resolved = item.resolvingSymlinksInPath().standardizedFileURL
                if resolved.pathExtension.lowercased() == "app" {
                    guard let bundle = Bundle(url: resolved),
                          let executable = bundle.executableURL,
                          bundle.bundleIdentifier != Bundle.main.bundleIdentifier,
                          resolved.path != DaemonConstants.systemSettingsPath,
                          seen.insert(resolved.path).inserted
                    else { continue }
                    let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                        ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                        ?? resolved.deletingPathExtension().lastPathComponent
                    found.append(BlockedApp(name: name, bundlePath: resolved.path,
                                            executablePath: executable.path))
                } else if depth < 1, (try? resolved.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    directories.append((resolved, depth + 1))
                }
            }
        }
        availableApps = found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func setBlockedApp(_ app: BlockedApp, enabled: Bool) {
        guard phase == .unguarded else { return }
        var apps = daemonStatus?.blockedApps ?? []
        if enabled {
            guard !apps.contains(where: { $0.id == app.id }) else { return }
            apps.append(app)
        } else {
            apps.removeAll { $0.id == app.id }
        }
        saveBlockedApps(apps)
    }

    private func saveBlockedApps(_ apps: [BlockedApp]) {
        perform(DaemonRequest(command: .setBlockedApps, blockedApps: apps),
                successNotice: "Lockdown app list updated.")
    }

    func saveSchedule(_ schedule: GuardSchedule) {
        perform(DaemonRequest(command: .setSchedule, schedule: schedule),
                successNotice: schedule.enabled ? "Daily schedule saved." : "Daily schedule disabled.")
    }

    private func tick() {
        now = Date()
        guard !isBusy, !refreshingSchedule else { return }
        refreshingSchedule = true
        Task {
            defer { refreshingSchedule = false }
            if let response = try? await Task.detached(operation: { [client] in
                try client.send(DaemonRequest(command: .status))
            }).value, !isBusy, let status = response.status {
                apply(status)
            }
        }
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
