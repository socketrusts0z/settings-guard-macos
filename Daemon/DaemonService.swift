import Darwin
import Foundation

final class DaemonService {
    private let queue = DispatchQueue(label: DaemonConstants.label)
    private let stateStore: DaemonStateStore
    private let settingsGuard: SettingsProcessGuard
    private var state: PersistentDaemonState
    private var listener: Int32 = -1
    private var socketSource: DispatchSourceRead?
    private var guardTimer: DispatchSourceTimer?

    init(
        stateStore: DaemonStateStore = DaemonStateStore(),
        settingsGuard: SettingsProcessGuard = SettingsProcessGuard()
    ) throws {
        self.stateStore = stateStore
        self.settingsGuard = settingsGuard
        state = try stateStore.load()
    }

    deinit {
        if listener >= 0 { Darwin.close(listener) }
        unlink(DaemonConstants.socketPath)
    }

    func start() throws {
        try stateStore.save(state)
        if isGuardActive {
            settingsGuard.terminateProtectedProcesses(blockedApps: state.blockedApps)
        }
        try startSocket()
        startGuardTimer()
    }

    private var isGuardActive: Bool {
        state.protectionActive(at: Date())
    }

    private func startSocket() throws {
        unlink(DaemonConstants.socketPath)
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw currentPOSIXError() }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let pathBytes = Array(DaemonConstants.socketPath.utf8) + [0]
        let copied = withUnsafeMutableBytes(of: &address.sun_path) { buffer -> Bool in
            guard pathBytes.count <= buffer.count else { return false }
            buffer.copyBytes(from: pathBytes)
            return true
        }
        guard copied else { throw POSIXError(.ENAMETOOLONG) }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { throw currentPOSIXError() }
        guard let adminGroup = getgrnam("admin") else { throw POSIXError(.ENOENT) }
        guard chown(DaemonConstants.socketPath, 0, adminGroup.pointee.gr_gid) == 0 else {
            throw currentPOSIXError()
        }
        guard chmod(DaemonConstants.socketPath, 0o660) == 0 else { throw currentPOSIXError() }
        guard listen(listener, 16) == 0 else { throw currentPOSIXError() }

        let flags = fcntl(listener, F_GETFL, 0)
        _ = fcntl(listener, F_SETFL, flags | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPendingConnections() }
        source.setCancelHandler { [listener] in Darwin.close(listener) }
        source.resume()
        socketSource = source
    }

    private func startGuardTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(250), leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if isGuardActive {
                settingsGuard.terminateProtectedProcesses(blockedApps: state.blockedApps)
            }
        }
        timer.resume()
        guardTimer = timer
    }

    private func acceptPendingConnections() {
        while true {
            let client = accept(listener, nil, nil)
            if client < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                return
            }
            let clientFlags = fcntl(client, F_GETFL, 0)
            _ = fcntl(client, F_SETFL, clientFlags & ~O_NONBLOCK)
            handle(client: client)
            Darwin.close(client)
        }
    }

    private func handle(client: Int32) {
        var timeout = timeval(tv_sec: 20, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let response: DaemonResponse
        do {
            let requestData = try readRequest(from: client)
            let request = try JSONDecoder().decode(DaemonRequest.self, from: requestData)
            response = process(request)
        } catch {
            response = DaemonResponse(success: false, message: error.localizedDescription, status: status())
        }

        if var data = try? JSONEncoder().encode(response) {
            data.append(0x0A)
            writeAll(data, to: client)
        }
    }

    private func process(_ request: DaemonRequest) -> DaemonResponse {
        do {
            switch request.command {
            case .status:
                break

            case .initialize:
                guard state.credential == nil else {
                    return failure("The guard password is already configured.")
                }
                guard let password = request.password else {
                    return failure("A guard password is required.")
                }
                state.credential = try PasswordCredential.create(password: password)
                state.guardEnabled = true
                state.failedUnlockAttempts = 0
                state.nextUnlockAttempt = nil
                try stateStore.save(state)
                if isGuardActive {
                    settingsGuard.terminateProtectedProcesses(blockedApps: state.blockedApps)
                }

            case .setGuardEnabled:
                guard state.credential != nil else {
                    return failure("Configure a guard password first.")
                }
                guard let guardEnabled = request.guardEnabled else {
                    return failure("The requested guard state is missing.")
                }

                if guardEnabled {
                    state.schedule.enabled = false
                    state.guardEnabled = true
                    try stateStore.save(state)
                    settingsGuard.terminateProtectedProcesses(blockedApps: state.blockedApps)
                    break
                }

                try persistAuthentication {
                    try $0.disableProtection(using: .password(request.password))
                }

            case .unlockWithQR:
                try persistAuthentication {
                    try $0.disableProtection(using: .qr(request.qrToken))
                }

            case .configureQR:
                try persistAuthentication {
                    try $0.configureQR(token: request.qrToken, password: request.password)
                }

            case .setSchedule:
                guard state.credential != nil else {
                    return failure("Configure a guard password first.")
                }
                guard !isGuardActive else {
                    return failure("Disable FrictionBlocker with your password before editing the schedule.")
                }
                guard let schedule = request.schedule, schedule.isValid else {
                    return failure("Choose different start and end times within a day.")
                }
                // Disabling a schedule leaves protection off until enabled manually.
                state.guardEnabled = false
                state.schedule = schedule
                try stateStore.save(state)
                if isGuardActive {
                    settingsGuard.terminateProtectedProcesses(blockedApps: state.blockedApps)
                }

            case .setBlockedApps:
                guard state.credential != nil else {
                    return failure("Configure a guard password first.")
                }
                guard !isGuardActive else {
                    return failure("Disable FrictionBlocker before changing the Lockdown app list.")
                }
                guard let requestedApps = request.blockedApps, requestedApps.count <= 100 else {
                    return failure("Choose no more than 100 apps.")
                }
                var validatedApps: [BlockedApp] = []
                var seenPaths = Set<String>()
                for requestedApp in requestedApps {
                    guard let app = validatedBlockedApp(at: requestedApp.bundlePath) else {
                        return failure("One of the selected apps is no longer available or is not a valid macOS app.")
                    }
                    if seenPaths.insert(app.bundlePath).inserted {
                        validatedApps.append(app)
                    }
                }
                state.blockedApps = validatedApps
                try stateStore.save(state)
            }

            return DaemonResponse(success: true, message: "OK", status: status())
        } catch {
            return failure(error.localizedDescription)
        }
    }

    /// Persist failed-attempt cooldowns as well as successful credential changes.
    private func persistAuthentication(_ action: (inout PersistentDaemonState) throws -> Void) throws {
        do {
            try action(&state)
        } catch {
            try stateStore.save(state)
            throw error
        }
        try stateStore.save(state)
    }

    private func status() -> DaemonStatus {
        DaemonStatus(
            initialized: state.credential != nil,
            guardActive: isGuardActive,
            nextPasswordAttempt: state.nextUnlockAttempt,
            systemSettingsRunning: settingsGuard.isSystemSettingsRunning(),
            blockedApps: state.blockedApps,
            schedule: state.schedule,
            qrConfigured: state.qrCredential != nil
        )
    }

    private func validatedBlockedApp(at path: String) -> BlockedApp? {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        guard url.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: url),
              let executableURL = bundle.executableURL?.resolvingSymlinksInPath().standardizedFileURL,
              executableURL.path.hasPrefix(url.path + "/Contents/MacOS/"),
              FileManager.default.isExecutableFile(atPath: executableURL.path),
              url.path != "/Applications/FrictionBlocker.app",
              url.path != DaemonConstants.systemSettingsPath
        else { return nil }

        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return BlockedApp(name: name, bundlePath: url.path, executablePath: executableURL.path)
    }

    private func failure(_ message: String) -> DaemonResponse {
        DaemonResponse(success: false, message: message, status: status())
    }

    private func readRequest(from client: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count < 128 * 1024 {
            let count = Darwin.read(client, &buffer, buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
                if data.last == 0x0A {
                    data.removeLast()
                    return data
                }
            } else if count == 0 {
                break
            } else if errno != EINTR {
                throw currentPOSIXError()
            }
        }
        guard !data.isEmpty else { throw POSIXError(.EBADMSG) }
        return data
    }

    private func writeAll(_ data: Data, to client: Int32) {
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(client, base.advanced(by: offset), buffer.count - offset)
                if count > 0 { offset += count }
                else if count < 0, errno == EINTR { continue }
                else { return }
            }
        }
    }

    private func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
