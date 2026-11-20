#if targetEnvironment(macCatalyst)
import Darwin
import Foundation
import Observation

@MainActor @Observable
final class MacUpdater {
    enum Prompt {
        case available(MacRelease)
        case ready(String)
        case current
        case checkFailed
        case downloadFailed
        case installFailed

        var title: String {
            switch self {
            case .available(let release): "iNod \(release.version) 可更新"
            case .ready(let version): "iNod \(version) 已下载"
            case .current: "已是最新版本"
            case .checkFailed: "未能检查更新"
            case .downloadFailed: "未能准备更新"
            case .installFailed: "未能安装更新"
            }
        }
    }

    private static let interval: TimeInterval = 24 * 60 * 60
    private static let lastCheckKey = "macUpdateLastAutomaticCheck"
    private let app = Bundle.main.bundleURL
    private let installer = Bundle.main.bundleURL.appending(path: "Contents/Helpers/iNodUpdateInstaller")
    private var staging: URL?
    private(set) var busy = false
    var prompt: Prompt?

    init() {
        if ProcessInfo.processInfo.arguments.contains("--mac-update-failed") {
            prompt = .installFailed
        }
    }

    func checkWhileActive() async {
        #if !DEBUG
        while !Task.isCancelled {
            let lastCheck = UserDefaults.standard.double(forKey: Self.lastCheckKey)
            let elapsed = Date.now.timeIntervalSince1970 - lastCheck
            let delay = elapsed >= 0 && elapsed < Self.interval ? Self.interval - elapsed : 0
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            await check(manual: false)
            // Try again soon if another update action was already in progress.
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
        }
        #endif
    }

    func check(manual: Bool) async {
        guard !busy, prompt == nil,
              let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return }
        busy = true
        defer {
            busy = false
            if !Task.isCancelled {
                UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: Self.lastCheckKey)
            }
        }
        let update: MacRelease?
        do {
            update = try await MacRelease.newer(than: installed)
            try Task.checkCancellation()
        } catch {
            if manual && !Task.isCancelled { prompt = .checkFailed }
            return
        }

        guard let update else {
            if manual { prompt = .current }
            return
        }
        guard let package = update.package, FileManager.default.isExecutableFile(atPath: installer.path),
              FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) else {
            prompt = .available(update)
            return
        }

        do {
            let folder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                     appropriateFor: app, create: true)
            staging = folder
            let (signature, response) = try await URLSession.shared.data(from: package.appendingPathExtension("ed25519"))
            try Self.checkResponse(response)
            let (file, downloadResponse) = try await URLSession.shared.download(from: package)
            defer { try? FileManager.default.removeItem(at: file) }
            try Self.checkResponse(downloadResponse)
            try signature.write(to: folder.appending(path: "signature"))
            try FileManager.default.moveItem(at: file, to: folder.appending(path: "update.zip"))
            try await Self.run(installer, arguments: ["prepare", app.path, folder.path, update.version])
            try Task.checkCancellation()
            prompt = .ready(update.version)
        } catch {
            discard()
            if manual && !Task.isCancelled { prompt = .downloadFailed }
        }
    }

    func install() async {
        guard !busy, let staging else { return }
        busy = true
        defer { busy = false }
        do {
            try await Self.run(installer, arguments: ["install", app.path, staging.path, String(getpid())])
        } catch {
            discard()
            prompt = .installFailed
        }
    }

    func discard() {
        if let staging { try? FileManager.default.removeItem(at: staging) }
        staging = nil
    }

    private static func checkResponse(_ response: URLResponse) throws {
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    }

    @concurrent private static func run(_ executable: URL, arguments: [String]) async throws {
        var argv = ([executable.path] + arguments).map { strdup($0) }
        defer { argv.forEach { free($0) } }
        argv.append(nil)
        var pid: pid_t = 0
        let spawnError = posix_spawn(&pid, executable.path, nil, nil, &argv, environ)
        guard spawnError == 0 else { throw POSIXError(POSIXErrorCode(rawValue: spawnError) ?? .EIO) }
        var status: Int32 = 0
        var result: pid_t
        repeat { result = waitpid(pid, &status, 0) } while result == -1 && errno == EINTR
        guard result == pid, status == 0 else { throw POSIXError(.EIO) }
    }
}
#endif
