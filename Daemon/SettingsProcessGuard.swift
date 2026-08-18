import Darwin
import Foundation

final class SettingsProcessGuard {
    private static let protectedExecutablePaths: Set<String> = [
        "/System/Applications/System Settings.app/Contents/MacOS/System Settings",
        "/Applications/System Preferences.app/Contents/MacOS/System Preferences"
    ]

    func runningProcessIDs() -> [pid_t] {
        let estimatedCount = max(proc_listallpids(nil, 0), 128)
        var processIDs = [pid_t](repeating: 0, count: Int(estimatedCount) + 32)
        let count = processIDs.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [] }

        return processIDs.prefix(min(Int(count), processIDs.count)).filter { processID in
            guard processID > 0 else { return false }
            // libproc defines PROC_PIDPATHINFO_MAXSIZE as 4 * MAXPATHLEN,
            // but that C macro is not imported into Swift.
            var pathBuffer = [CChar](repeating: 0, count: 4096)
            let pathLength = proc_pidpath(
                processID,
                &pathBuffer,
                UInt32(pathBuffer.count)
            )
            guard pathLength > 0 else { return false }
            return Self.protectedExecutablePaths.contains(String(cString: pathBuffer))
        }
    }

    func isSystemSettingsRunning() -> Bool {
        !runningProcessIDs().isEmpty
    }

    @discardableResult
    func terminateSystemSettings() -> Int {
        var terminated = 0
        for processID in runningProcessIDs() where kill(processID, SIGKILL) == 0 {
            terminated += 1
        }
        return terminated
    }
}
