import Darwin
import Foundation

guard geteuid() == 0 else {
    FileHandle.standardError.write(Data("frictionblockerd must run as root.\n".utf8))
    exit(EXIT_FAILURE)
}

umask(0o077)

do {
    let service = try DaemonService()
    try service.start()
    dispatchMain()
} catch {
    FileHandle.standardError.write(Data("frictionblockerd: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
