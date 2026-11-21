#if DEBUG
import Foundation

/// UI tests either supply recorded website responses or launch the app offline.
public enum UITestNetwork {
    private static let recordedResponses: [String: Data]? = {
        if let json = ProcessInfo.processInfo.environment["NODESEEK_UI_TEST_WEBSITE"] {
            do { return try JSONDecoder().decode(AccountSession.UITestWebsite.self, from: Data(json.utf8)).responses }
            catch { preconditionFailure("Invalid UI test website fixture: \(error)") }
        }
        return ProcessInfo.processInfo.arguments.contains("--ui-test-offline") ? [:] : nil
    }()

    public static var isActive: Bool { recordedResponses != nil }

    /// Test image servers listen on numeric loopback addresses. All other media must come from the fixture.
    static func media(for url: URL, responses: [String: Data]? = recordedResponses) throws -> Data? {
        guard let responses else { return nil }
        if let data = responses[url.absoluteString] { return data }
        if url.scheme == "http", url.host() == "127.0.0.1" { return nil }
        throw URLError(.resourceUnavailable)
    }
}
#endif
