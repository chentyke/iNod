import AppKit
import CryptoKit
import Darwin
import Foundation

private enum UpdateError: Error {
    case invalidArguments, invalidSignature, invalidApp, installInProgress, quitFailed, replacementFailed, launchFailed
    case commandFailed(String, Int32)
}

private func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw UpdateError.commandFailed(executable, process.terminationStatus)
    }
}

private func publicKey(in app: URL) throws -> Data {
    try Data(contentsOf: app.appending(path: "Contents/Resources/MacUpdatePublicKey"))
}

private func version(of app: Bundle) -> String? {
    app.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
}

private func prepare(app: URL, folder: URL, expectedVersion: String) throws {
    let archive = folder.appending(path: "update.zip")
    let signatureFile = folder.appending(path: "signature")
    let package = try Data(contentsOf: archive, options: .mappedIfSafe)
    let signature = try Data(contentsOf: signatureFile)
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey(in: app))
    guard key.isValidSignature(signature, for: package) else { throw UpdateError.invalidSignature }

    try run("/usr/bin/ditto", ["-x", "-k", archive.path, folder.path])
    let candidate = folder.appending(path: "iNod.app")
    try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", candidate.path])
    guard let installed = Bundle(url: app), let update = Bundle(url: candidate),
          let identifier = installed.bundleIdentifier, update.bundleIdentifier == identifier,
          let installedVersion = version(of: installed), version(of: update) == expectedVersion,
          expectedVersion.compare(installedVersion, options: .numeric) == .orderedDescending,
          try publicKey(in: candidate) == key.rawRepresentation else { throw UpdateError.invalidApp }
    try FileManager.default.removeItem(at: archive)
    try FileManager.default.removeItem(at: signatureFile)
}

@MainActor private func install(app: URL, folder: URL, pid: pid_t) throws {
    let parent = app.deletingLastPathComponent()
    let lock = open(parent.path, O_RDONLY | O_DIRECTORY)
    guard lock >= 0 else { throw UpdateError.replacementFailed }
    defer { close(lock) }
    guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw UpdateError.installInProgress }

    let preparedApp = folder.appending(path: "iNod.app")
    guard let installed = Bundle(url: app).flatMap(version(of:)),
          let update = Bundle(url: preparedApp).flatMap(version(of:)),
          update.compare(installed, options: .numeric) == .orderedDescending else { throw UpdateError.invalidApp }
    guard let runningApp = NSRunningApplication(processIdentifier: pid),
          runningApp.bundleURL?.resolvingSymlinksInPath() == app.resolvingSymlinksInPath() else {
        throw UpdateError.quitFailed
    }

    // The system may remove the download folder when iNod quits.
    let files = FileManager.default
    let swapFolder = parent.appending(path: ".iNod-update-\(UUID().uuidString)", directoryHint: .isDirectory)
    try files.createDirectory(at: swapFolder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    var keepBackup = false
    defer { if !keepBackup { try? files.removeItem(at: swapFolder) } }
    let candidate = swapFolder.appending(path: "iNod.app")
    try files.moveItem(at: preparedApp, to: candidate)
    try? files.removeItem(at: folder)
    guard runningApp.terminate() else { throw UpdateError.quitFailed }

    let deadline = ContinuousClock.now + .seconds(20)
    while kill(pid, 0) == 0 || errno == EPERM {
        guard ContinuousClock.now < deadline else { throw UpdateError.quitFailed }
        Thread.sleep(forTimeInterval: 0.1)
    }

    // Both bundles are on the same volume. Swap them so the original stays available for rollback.
    guard renamex_np(candidate.path, app.path, UInt32(RENAME_SWAP)) == 0 else {
        try run("/usr/bin/open", ["-n", app.path, "--args", "--mac-update-failed"])
        throw UpdateError.replacementFailed
    }
    do {
        try run("/usr/bin/open", ["-n", app.path])
    } catch {
        guard renamex_np(candidate.path, app.path, UInt32(RENAME_SWAP)) == 0 else {
            keepBackup = true
            throw error
        }
        try run("/usr/bin/open", ["-n", app.path, "--args", "--mac-update-failed"])
        throw UpdateError.launchFailed
    }
}

do {
    let args = CommandLine.arguments
    guard args.count == 5 else { throw UpdateError.invalidArguments }
    let app = URL(fileURLWithPath: args[2], isDirectory: true)
    let folder = URL(fileURLWithPath: args[3], isDirectory: true)
    switch args[1] {
    case "prepare": try prepare(app: app, folder: folder, expectedVersion: args[4])
    case "install":
        guard let pid = pid_t(args[4]), pid > 0 else { throw UpdateError.invalidArguments }
        try install(app: app, folder: folder, pid: pid)
    default: throw UpdateError.invalidArguments
    }
} catch {
    FileHandle.standardError.write(Data("iNod update: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
