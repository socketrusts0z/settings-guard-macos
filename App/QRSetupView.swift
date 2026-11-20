import SwiftUI

struct QRSetupView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var token: String?
    @State private var password = ""
    @State private var scanning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose your unlock code").font(.title2.bold())
            Text("Use an existing QR code or barcode—on a book, a product, a card, or anywhere you want to walk to unlock your Mac.")
            Text("Show one code to the camera, then enter your current guard password to use it for unlocking.")
                .foregroundStyle(.secondary)
            Button(token == nil ? "Scan a QR Code or Barcode…" : "Scan a Different Code…") {
                scanning = true
            }
            .disabled(model.isBusy)
            if token != nil {
                Label("Code captured", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Scanning this same code will disable protection exactly like your password. Replacing a code invalidates the old one. Your password remains available as a fallback.")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField("Current guard password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            if !model.canAttemptPassword, let next = model.daemonStatus?.nextPasswordAttempt {
                Text("Try again after \(next.formatted(date: .omitted, time: .standard)).")
                    .foregroundStyle(.orange)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Use This Code") {
                    guard let token else { return }
                    let currentPassword = password
                    password = ""
                    model.configureQR(token, password: currentPassword) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(token == nil || password.isEmpty || model.isBusy || !model.canAttemptPassword)
            }
        }
        .padding(24)
        .frame(width: 540)
        .sheet(isPresented: $scanning) {
            QRScannerView { scanned in
                token = scanned
                password = ""
            }
        }
    }
}
