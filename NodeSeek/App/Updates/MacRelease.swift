#if targetEnvironment(macCatalyst)
import Foundation

struct MacRelease: Decodable {
    private static let repository = URL(string: "https://github.com/chentyke/iNod")!
    private static let latest = URL(string: "https://api.github.com/repos/chentyke/iNod/releases/latest")!

    let tagName: String
    let draft: Bool
    let prerelease: Bool
    private let assets: [Asset]

    var version: String { String(tagName.dropFirst()) }
    var page: URL { Self.repository.appending(path: "releases/tag/\(tagName)") }

    var package: URL? {
        let name = "iNod-\(tagName)-mac-update.zip"
        guard hasAsset(name), hasAsset(name + ".ed25519") else {
            return nil
        }
        return Self.repository.appending(path: "releases/download/\(tagName)/\(name)")
    }

    static func newer(than installed: String) async throws -> Self? {
        var request = URLRequest(url: latest, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release = try decoder.decode(Self.self, from: data)
        guard !release.draft, !release.prerelease, release.tagName.hasPrefix("v"),
              let latest = versionParts(release.version), let current = versionParts(installed),
              current.lexicographicallyPrecedes(latest) else { return nil }
        return release.hasAsset("iNod-\(release.tagName)-mac.dmg") || release.package != nil ? release : nil
    }

    private func hasAsset(_ name: String) -> Bool {
        assets.contains { $0.name == name && $0.state == "uploaded" }
    }

    private static func versionParts(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 3, numbers.allSatisfy({ $0 >= 0 }),
              numbers.map({ String($0) }).joined(separator: ".") == version else { return nil }
        return numbers
    }

    private struct Asset: Decodable {
        let name: String
        let state: String
    }
}
#endif
