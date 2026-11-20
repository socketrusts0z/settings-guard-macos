import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var appSearch = ""
    @State private var qrSheet: QRSheet?
    @State private var qrRemovalPassword = ""

    private enum QRSheet: String, Identifiable {
        case setup, unlock
        var id: String { rawValue }
    }
    @State private var scheduleEnabled = true
    @State private var scheduleStart = Calendar.current.date(from: DateComponents(hour: 22)) ?? Date()
    @State private var scheduleEnd = Calendar.current.date(from: DateComponents(hour: 6)) ?? Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                messages

                switch model.phase {
                case .loading:
                    ProgressView("Connecting to Settings Guard…")
                case .setup:
                    setupView
                case .guarded:
                    guardedView
                case .unguarded:
                    unguardedView
                case .unavailable:
                    unavailableView
                }
            }
            .padding(30)
        }
        .sheet(item: $qrSheet) { sheet in
            switch sheet {
            case .setup: QRSetupView(model: model)
            case .unlock: QRScannerView { model.unlockWithQR($0) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: model.phase == .unguarded ? "gearshape.fill" : "lock.shield.fill")
                .font(.system(size: 38))
                .foregroundStyle(model.phase == .unguarded ? Color.orange : Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text("FrictionBlocker")
                    .font(.largeTitle.bold())
                Text("Guard System Settings and close selected apps during Lockdown")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var messages: some View {
        if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
        if let notice = model.noticeMessage {
            Label(notice, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    private var setupView: some View {
        GroupBox("Create the Settings Guard password") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Store this password somewhere deliberately inconvenient. It is shown only during setup and cannot be reset from the app.")

                Text(model.generatedPassword)
                    .font(.system(.title2, design: .monospaced).bold())
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                Button("Generate a different password") { model.generatePassword() }

                SecureField("Type the generated password to confirm", text: $model.setupConfirmation)
                    .textFieldStyle(.roundedBorder)

                Text("Minimum length: \(PasswordPolicy.minimumLength) characters. Generated passwords contain \(PasswordPolicy.generatedLength).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("I stored it — activate Settings Guard") { model.finishSetup() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.setupConfirmation.isEmpty || model.isBusy)
            }
            .padding(8)
        }
    }

    private var guardedView: some View {
        VStack(alignment: .leading, spacing: 18) {
            statusBox
            scheduleBox
            qrBox
            lockdownList

            GroupBox("Disable FrictionBlocker") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Enter the guard password to disable protection and its schedule, then edit the schedule or Lockdown list. Re-enable the schedule when you are ready.")
                        .foregroundStyle(.secondary)

                    SecureField("Settings Guard password", text: $model.guardPassword)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.disableGuard() }

                    if let date = model.daemonStatus?.nextPasswordAttempt,
                       !model.canAttemptPassword {
                        Text("Next attempt after \(date.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Toggle(
                        "Enable FrictionBlocker",
                        isOn: Binding(
                            get: { true },
                            set: { enabled in
                                if !enabled { model.disableGuard() }
                            }
                        )
                    )
                    .toggleStyle(.switch)
                    .disabled(model.guardPassword.isEmpty || !model.canAttemptPassword || model.isBusy)
                }
                .padding(8)
            }

            limitations
        }
    }

    private var unguardedView: some View {
        VStack(alignment: .leading, spacing: 18) {
            statusBox
            scheduleBox
            qrBox
            lockdownList

            GroupBox("Protection disabled") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("FrictionBlocker is off")
                        .font(.title3.bold())

                    Text("System Settings and apps in the Lockdown list are accessible. If the daily schedule is enabled, protection will start automatically at its next start time. Turning protection on manually disables the schedule.")
                        .foregroundStyle(.secondary)

                    Toggle(
                        "Enable FrictionBlocker",
                        isOn: Binding(
                            get: { false },
                            set: { enabled in
                                if enabled { model.enableGuard() }
                            }
                        )
                    )
                    .toggleStyle(.switch)
                    .disabled(model.isBusy)

                    Button("Open System Settings") { model.openSystemSettings() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(8)
            }

            limitations
        }
    }

    private var qrBox: some View {
        GroupBox("QR or barcode unlock") {
            VStack(alignment: .leading, spacing: 12) {
                if let configured = model.daemonStatus?.qrConfigured {
                    Text(configured ? "Code unlocking is enabled" : "No unlock code set up")
                        .font(.headline)
                    Text("Scan your chosen QR code or barcode to disable protection exactly like your password. Protection and its schedule stay off until you enable them again.")
                        .foregroundStyle(.secondary)
                    if configured, model.phase == .guarded {
                        Button("Scan to Unlock…") { qrSheet = .unlock }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isBusy || !model.canAttemptPassword)
                    }
                    if model.phase == .unguarded {
                        Button(configured ? "Replace Code…" : "Set Up Code…") { qrSheet = .setup }
                            .disabled(model.isBusy || !model.canAttemptPassword)
                        if configured {
                            SecureField("Current password to remove code unlocking", text: $qrRemovalPassword)
                                .textFieldStyle(.roundedBorder)
                            Button("Remove Code Unlocking") {
                                let password = qrRemovalPassword
                                qrRemovalPassword = ""
                                model.configureQR(nil, password: password)
                            }
                            .disabled(qrRemovalPassword.isEmpty || model.isBusy || !model.canAttemptPassword)
                        }
                    } else {
                        Text("Unlock first to set up or replace your code.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Install the updated app and daemon to use code unlocking.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }

    private var scheduleBox: some View {
        GroupBox("Daily schedule") {
            VStack(alignment: .leading, spacing: 12) {
                if let schedule = model.daemonStatus?.schedule {
                    Text(schedule.enabled ? "Schedule enabled · \(timeLabel(schedule.startMinute))–\(timeLabel(schedule.endMinute))" : "Schedule disabled")
                        .font(.headline)
                } else {
                    Text("Update the installed daemon to use scheduling.")
                }
                Text("Uses your Mac’s local time every day, including overnight. Runs even when this app is closed; checks the current time again after sleep or restart.")
                    .foregroundStyle(.secondary)
                if model.phase == .unguarded, model.daemonStatus?.schedule != nil {
                    Toggle("Enable daily schedule", isOn: $scheduleEnabled)
                    HStack {
                        DatePicker("Start", selection: $scheduleStart, displayedComponents: .hourAndMinute)
                        DatePicker("End", selection: $scheduleEnd, displayedComponents: .hourAndMinute)
                    }
                    Button("Save Schedule") {
                        let calendar = Calendar.current
                        let start = calendar.component(.hour, from: scheduleStart) * 60 + calendar.component(.minute, from: scheduleStart)
                        let end = calendar.component(.hour, from: scheduleEnd) * 60 + calendar.component(.minute, from: scheduleEnd)
                        model.saveSchedule(GuardSchedule(enabled: scheduleEnabled, startMinute: start, endMinute: end))
                    }
                    .disabled(model.isBusy || sameScheduleTimes)
                } else if model.phase == .guarded {
                    Text("Disable protection with your password to edit the schedule. This also disables the schedule until you enable it again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
        .onAppear { loadScheduleDraft() }
        .onChange(of: model.phase) { _, _ in loadScheduleDraft() }
    }

    private var sameScheduleTimes: Bool {
        Calendar.current.dateComponents([.hour, .minute], from: scheduleStart)
            == Calendar.current.dateComponents([.hour, .minute], from: scheduleEnd)
    }

    private func timeLabel(_ minute: Int) -> String {
        (Calendar.current.date(from: DateComponents(hour: minute / 60, minute: minute % 60)) ?? Date())
            .formatted(date: .omitted, time: .shortened)
    }

    private func loadScheduleDraft() {
        guard let schedule = model.daemonStatus?.schedule else { return }
        scheduleEnabled = schedule.enabled
        scheduleStart = Calendar.current.date(from: DateComponents(hour: schedule.startMinute / 60, minute: schedule.startMinute % 60)) ?? Date()
        scheduleEnd = Calendar.current.date(from: DateComponents(hour: schedule.endMinute / 60, minute: schedule.endMinute % 60)) ?? Date()
    }

    private var statusBox: some View {
        GroupBox("Privileged guard daemon") {
            HStack {
                Label(
                    model.phase == .unguarded ? "FrictionBlocker is disabled" : "FrictionBlocker is active",
                    systemImage: model.phase == .unguarded ? "lock.open.fill" : "checkmark.shield.fill"
                )
                Spacer()
                Button("Refresh") { model.refreshStatus() }
                    .disabled(model.isBusy)
            }
            .padding(8)
        }
    }

    private var lockdownList: some View {
        GroupBox("Lockdown apps") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose which apps close shortly after they open while FrictionBlocker is active.")
                    .foregroundStyle(.secondary)

                let selectedApps = model.daemonStatus?.blockedApps ?? []
                Text("\(selectedApps.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.phase == .unguarded {
                    TextField("Search installed apps", text: $appSearch)
                        .textFieldStyle(.roundedBorder)

                    let knownPaths = Set(model.availableApps.map(\.bundlePath))
                    let allApps = (model.availableApps + selectedApps.filter { !knownPaths.contains($0.bundlePath) })
                        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    let matchingApps = allApps.filter {
                        appSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(appSearch)
                    }

                    if matchingApps.isEmpty {
                        Text(appSearch.isEmpty ? "No apps found" : "No matching apps")
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(matchingApps) { app in
                                    Toggle(isOn: Binding(
                                        get: { selectedApps.contains(where: { $0.id == app.id }) },
                                        set: { model.setBlockedApp(app, enabled: $0) }
                                    )) {
                                        HStack(spacing: 8) {
                                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath))
                                                .resizable()
                                                .frame(width: 20, height: 20)
                                            Text(app.name)
                                        }
                                    }
                                    .disabled(model.isBusy)
                                    .help(app.bundlePath)
                                }
                            }
                        }
                        .frame(height: min(CGFloat(matchingApps.count) * 34, 240))
                    }

                    HStack {
                        Button("Add Apps…") { model.chooseBlockedApps() }
                        Button("Refresh List") { model.refreshAvailableApps() }
                    }
                    .disabled(model.isBusy)
                } else {
                    if selectedApps.isEmpty {
                        Text("No apps selected")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(selectedApps) { app in
                            Label(app.name, systemImage: "app.fill")
                        }
                    }
                    Text("Disable FrictionBlocker to change this list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }

    private var limitations: some View {
        GroupBox("What this protects") {
            VStack(alignment: .leading, spacing: 8) {
                Text("The daemon closes System Settings and selected Lockdown apps while protection is active. A window may appear briefly before it closes.")
                Text("This is a friction mechanism, not an administrator security boundary. Terminal commands, sudo, Recovery mode, or uninstalling the daemon can bypass it.")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(8)
        }
    }

    private var unavailableView: some View {
        GroupBox("Privileged daemon unavailable") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Build and install the guard once from Terminal. This uses sudo but requires no Apple developer account.")
                Text("cd \"/path/to/FrictionBlocker\"\n./Scripts/build.sh\nsudo ./Scripts/install.sh\nopen /Applications/FrictionBlocker.app")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                Button("Retry") { model.refreshStatus() }
            }
            .padding(8)
        }
    }
}
