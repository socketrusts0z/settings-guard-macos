import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

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
                case .authorized:
                    authorizedView
                case .unavailable:
                    unavailableView
                }
            }
            .padding(30)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: model.phase == .authorized ? "gearshape.fill" : "lock.shield.fill")
                .font(.system(size: 38))
                .foregroundStyle(model.phase == .authorized ? Color.orange : Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text("Settings Guard")
                    .font(.largeTitle.bold())
                Text("Require an intentionally inconvenient password to open System Settings")
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

            GroupBox("Open System Settings") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Enter the guard password to permit System Settings for five minutes.")
                        .foregroundStyle(.secondary)

                    SecureField("Settings Guard password", text: $model.guardPassword)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.authorizeAndOpenSettings() }

                    if let date = model.daemonStatus?.nextPasswordAttempt,
                       !model.canAttemptPassword {
                        Text("Next attempt after \(date.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Button("Authorize and open System Settings") {
                        model.authorizeAndOpenSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.guardPassword.isEmpty || !model.canAttemptPassword || model.isBusy)
                }
                .padding(8)
            }

            limitations
        }
    }

    private var authorizedView: some View {
        VStack(alignment: .leading, spacing: 18) {
            statusBox

            GroupBox("Temporary access") {
                VStack(alignment: .leading, spacing: 14) {
                    Text(model.authorizationSummary)
                        .font(.title3.bold())

                    HStack {
                        Button("Open System Settings") { model.openSystemSettings() }
                            .buttonStyle(.borderedProminent)
                        Button("End access now") { model.lockNow() }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(8)
            }

            limitations
        }
    }

    private var statusBox: some View {
        GroupBox("Privileged guard daemon") {
            HStack {
                Label(
                    model.phase == .authorized ? "Temporary access permitted" : "System Settings is guarded",
                    systemImage: model.phase == .authorized ? "clock.fill" : "checkmark.shield.fill"
                )
                Spacer()
                Button("Refresh") { model.refreshStatus() }
                    .disabled(model.isBusy)
            }
            .padding(8)
        }
    }

    private var limitations: some View {
        GroupBox("What this protects") {
            VStack(alignment: .leading, spacing: 8) {
                Text("The daemon closes System Settings when access has not been authorized. The window may appear briefly before it closes.")
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
