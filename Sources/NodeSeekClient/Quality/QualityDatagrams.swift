import Darwin
import Foundation

struct QualitySocketAddress {
    private let storage: sockaddr_storage

    init(_ storage: sockaddr_storage) { self.storage = storage }

    var host: String? { name(flags: NI_NUMERICHOST, service: false) }
    var port: UInt16? { name(flags: NI_NUMERICSERV, service: true).flatMap(UInt16.init) }

    func withAddress<T>(_ operation: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        withUnsafePointer(to: storage) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                operation($0, socklen_t(storage.ss_len))
            }
        }
    }

    static func resolve(_ host: String, port: UInt16 = 0, family: Int32) throws -> Self {
        var hints = addrinfo()
        hints.ai_family = family
        hints.ai_socktype = SOCK_DGRAM
        var addresses: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &addresses) == 0, let addresses else {
            throw QualityIssue.hostUnreachable
        }
        defer { freeaddrinfo(addresses) }
        var address = sockaddr_storage()
        let length = Int(addresses.pointee.ai_addrlen)
        guard let bytes = addresses.pointee.ai_addr, length <= MemoryLayout<sockaddr_storage>.size else {
            throw QualityIssue.invalidResponse
        }
        withUnsafeMutableBytes(of: &address) {
            $0.copyMemory(from: UnsafeRawBufferPointer(start: bytes, count: length))
        }
        return Self(address)
    }

    private func name(flags: Int32, service: Bool) -> String? {
        var buffer = [UInt8](repeating: 0, count: service ? 8 : Int(NI_MAXHOST))
        let count = socklen_t(buffer.count)
        let status = withAddress { address, length in
            buffer.withUnsafeMutableBytes { bytes in
                let output = bytes.baseAddress?.assumingMemoryBound(to: CChar.self)
                return service ? getnameinfo(address, length, nil, 0, output, count, flags) :
                    getnameinfo(address, length, output, count, nil, 0, flags)
            }
        }
        guard status == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }
}

struct QualityDatagrams {
    static func background<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
        let task = Task.detached(operation: work)
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    static func send(_ bytes: [UInt8], to target: QualitySocketAddress, socket: Int32) throws {
        try Task.checkCancellation()
        let sent = target.withAddress { address, length in
            bytes.withUnsafeBytes { sendto(socket, $0.baseAddress, $0.count, 0, address, length) }
        }
        guard sent == bytes.count else { throw QualityIssue.transportError(Int(errno)) }
    }

    static func receive<T>(
        on socket: Int32, until deadline: ContinuousClock.Instant,
        match: ([UInt8], QualitySocketAddress) -> T?
    ) throws -> T {
        var descriptor = pollfd(fd: socket, events: Int16(POLLIN), revents: 0)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            let ready = poll(&descriptor, 1, 100)
            if ready < 0 && errno == EINTR { continue }
            guard ready >= 0 else { throw QualityIssue.transportError(Int(errno)) }
            guard ready > 0 else { continue }
            var peer = sockaddr_storage()
            var length = socklen_t(MemoryLayout.size(ofValue: peer))
            var buffer = [UInt8](repeating: 0, count: 2048)
            let received = withUnsafeMutablePointer(to: &peer) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    buffer.withUnsafeMutableBytes { recvfrom(socket, $0.baseAddress, $0.count, MSG_DONTWAIT, address, &length) }
                }
            }
            if received < 0 && (errno == EINTR || errno == EAGAIN) { continue }
            guard received >= 0 else { throw QualityIssue.transportError(Int(errno)) }
            if let value = match(Array(buffer.prefix(received)), QualitySocketAddress(peer)) { return value }
        }
        throw QualityIssue.timedOut
    }
}
