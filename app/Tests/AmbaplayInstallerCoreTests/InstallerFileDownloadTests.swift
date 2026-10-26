import Foundation
import Network
import Testing
@testable import AmbaplayInstallerCore

@Suite("Installer file download")
struct InstallerFileDownloadTests {
    /// Serves `body` over HTTP on localhost. The first request gets half the body and the
    /// connection drops; later ones honour `Range: bytes=N-`.
    final class DroppingServer: @unchecked Sendable {
        let body: Data
        let listener: NWListener
        let lock = NSLock()
        var requests: [String] = []

        init(body: Data) throws {
            self.body = body
            listener = try NWListener(using: .tcp, on: .any)
            listener.newConnectionHandler = { [self] connection in
                connection.start(queue: .global())
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                    self.answer(String(decoding: data ?? Data(), as: UTF8.self), on: connection)
                }
            }
        }

        func start() async throws -> Int {
            let ready = AsyncStream<UInt16> { continuation in
                listener.stateUpdateHandler = { [listener] state in
                    if case .ready = state { continuation.yield(listener.port?.rawValue ?? 0); continuation.finish() }
                }
            }
            listener.start(queue: .global())
            for await port in ready { return Int(port) }
            throw URLError(.cannotConnectToHost)
        }

        private func answer(_ request: String, on connection: NWConnection) {
            let first = lock.withLock { requests.append(request); return requests.count == 1 }
            let range = request.split(separator: "\r\n")
                .first { $0.lowercased().hasPrefix("range: bytes=") }
                .flatMap { Int($0.dropFirst("range: bytes=".count).split(separator: "-").first ?? "") }
            let from = range ?? 0
            var head = range == nil ? "HTTP/1.1 200 OK\r\n" : "HTTP/1.1 206 Partial Content\r\n"
            if range != nil { head += "Content-Range: bytes \(from)-\(body.count - 1)/\(body.count)\r\n" }
            head += "Content-Length: \(body.count - from)\r\nAccept-Ranges: bytes\r\nETag: \"fixed\"\r\n"
            head += "Last-Modified: Wed, 21 Oct 2026 07:28:00 GMT\r\nConnection: close\r\n\r\n"
            let rest = body[from...]
            let sent = first ? rest.prefix(rest.count / 2) : rest
            connection.send(content: Data(head.utf8) + sent, completion: .contentProcessed { _ in
                if first {
                    // Give the client time to write the first half before the connection drops.
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { connection.cancel() }
                } else {
                    connection.cancel()
                }
            })
        }
    }

    final class Seen: @unchecked Sendable {
        let lock = NSLock()
        var values: [Int64] = []
    }

    @Test("A dropped download resumes from where it stopped")
    func resumes() async throws {
        let body = Data((0..<4_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let server = try DroppingServer(body: body)
        defer { server.listener.cancel() }
        let port = try await server.start()
        let request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/Ambaplay-Installer.zip")!)
        let seen = Seen()
        let (file, response) = try await InstallerFileDownload.run(request, total: Int64(body.count)) { value in
            seen.lock.withLock { seen.values.append(value.received) }
        }
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try Data(contentsOf: file) == body)
        #expect([200, 206].contains((response as? HTTPURLResponse)?.statusCode))
        let requests = server.lock.withLock { server.requests }
        #expect(requests.count == 2)
        #expect(requests.last?.lowercased().contains("range: bytes=") == true)
        // The progress bar carries on from the resumed offset instead of starting over.
        let values = seen.lock.withLock { seen.values }
        #expect(values.last == Int64(body.count))
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test("A paused download sends nothing until it is resumed")
    func pauses() async throws {
        let body = Data((0..<1_000_000).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        let server = try DroppingServer(body: body)
        defer { server.listener.cancel() }
        let port = try await server.start()
        let request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/Ambaplay-Installer.zip")!)
        let control = InstallerDownloadControl()
        control.pause()
        let download = Task { try await InstallerFileDownload.run(request, total: Int64(body.count), control: control) { _ in } }
        try await Task.sleep(for: .seconds(1))
        #expect(server.lock.withLock { server.requests.isEmpty })
        control.resume()
        let (file, _) = try await download.value
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try Data(contentsOf: file) == body)
        #expect(!control.isPaused)
    }

    @Test("Only failures a release swap can cause are retried")
    func releaseSwap() {
        #expect(InstallerError.signatureMismatch.mayBeReleaseSwap)
        #expect(InstallerError.invalidRelease.mayBeReleaseSwap)
        #expect(!InstallerError.networkFailure("x").mayBeReleaseSwap)
    }

    @Test("curl's progress meter reads as bytes, total and speed")
    func curlMeter() throws {
        let meter = try #require(InstallerDownloadProgress(curlMeter: "45 4200k   45 1890k    0     0  2105k      0  0:00:01  0:00:00  0:00:01 1.5M"))
        #expect(meter.received == 1890 * 1024 && meter.total == 4200 * 1024 && meter.speed == 1.5 * 1_048_576)
        #expect(InstallerDownloadProgress(curlMeter: "0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0")?.total == nil)
        #expect(InstallerDownloadProgress(curlMeter: "% Total    % Received % Xferd  Average Speed   Time    Time     Time  Current") == nil)
        #expect(InstallerDownloadProgress(curlMeter: "Dload  Upload   Total   Spent    Left  Speed") == nil)
    }
}
