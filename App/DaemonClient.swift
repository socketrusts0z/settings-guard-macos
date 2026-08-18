import Darwin
import Foundation

enum DaemonClientError: LocalizedError {
    case unavailable(Int32)
    case socketPathTooLong
    case communicationFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "The privileged blocker daemon is not installed or is not running."
        case .socketPathTooLong:
            "The blocker daemon socket path is too long."
        case .communicationFailed(let message):
            "Could not communicate with the blocker daemon: \(message)"
        case .invalidResponse:
            "The blocker daemon returned an invalid response."
        }
    }
}

struct DaemonClient: Sendable {
    func send(_ request: DaemonRequest) throws -> DaemonResponse {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw DaemonClientError.unavailable(errno)
        }
        defer { Darwin.close(descriptor) }

        var timeout = timeval(tv_sec: 15, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let pathBytes = Array(DaemonConstants.socketPath.utf8) + [0]

        let copied = withUnsafeMutableBytes(of: &address.sun_path) { buffer -> Bool in
            guard pathBytes.count <= buffer.count else { return false }
            buffer.copyBytes(from: pathBytes)
            return true
        }
        guard copied else { throw DaemonClientError.socketPathTooLong }

        let connectionResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectionResult == 0 else {
            throw DaemonClientError.unavailable(errno)
        }

        var requestData = try JSONEncoder().encode(request)
        requestData.append(0x0A)
        try writeAll(requestData, to: descriptor)

        var responseData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while responseData.count < 128 * 1024 {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                responseData.append(buffer, count: count)
                if responseData.last == 0x0A { break }
            } else if count == 0 {
                break
            } else if errno != EINTR {
                throw DaemonClientError.communicationFailed(String(cString: strerror(errno)))
            }
        }

        guard !responseData.isEmpty else { throw DaemonClientError.invalidResponse }
        if responseData.last == 0x0A { responseData.removeLast() }
        return try JSONDecoder().decode(DaemonResponse.self, from: responseData)
    }

    private func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(descriptor, base.advanced(by: offset), rawBuffer.count - offset)
                if written > 0 {
                    offset += written
                } else if written < 0, errno == EINTR {
                    continue
                } else {
                    throw DaemonClientError.communicationFailed(String(cString: strerror(errno)))
                }
            }
        }
    }
}
