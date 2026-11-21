import Foundation
import NodeSeekCore
import Security
import SwiftUI

/// Asks the YouTube Data API which rule one video publishes for one country.
struct YouTubeRegionView: View {
    let checker: any StreamingChecking
    @State private var videoID: String
    @State private var country: String
    @State private var apiKey = ""
    @State private var hasSavedKey = false
    @State private var keyError: String?
    @State private var result: YouTubeRegionCheck?
    @State private var checking: Task<Void, Never>?
    @FocusState private var editing: Field?
    private enum Field { case video, country, key }
    private let prefilledCountry: Bool

    init(checker: any StreamingChecking, countryCode: String?) {
        self.checker = checker
        _videoID = State(initialValue: checker.youTubeSampleVideoID)
        _country = State(initialValue: countryCode?.uppercased() ?? "")
        prefilledCountry = countryCode != nil
    }

    private var canCheck: Bool {
        YouTubeRegionCheck.isValidVideoID(videoID) && YouTubeRegionCheck.isValidCountryCode(country) && !apiKey.isEmpty && checking == nil
    }

    var body: some View {
        List {
            Section {
                LabeledContent("视频编号") {
                    TextField("11 位编号", text: $videoID)
                        .font(.body.monospaced()).multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($editing, equals: .video).accessibilityIdentifier("region.video")
                }
                LabeledContent("国家代码") {
                    TextField("例如 US", text: $country)
                        .font(.body.monospaced()).multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .onChange(of: country) { _, value in if value.count > 2 { country = String(value.prefix(2)) } }
                        .focused($editing, equals: .country).accessibilityIdentifier("region.country")
                }
            } footer: {
                Text(prefilledCountry ? "国家代码取自网络检测的出口归属，可以改成其他国家。默认视频是 YouTube 的公开样片。"
                                      : "两位字母的国家代码。默认视频是 YouTube 的公开样片。")
            }
            Section {
                SecureField("YouTube Data API 密钥", text: $apiKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($editing, equals: .key).accessibilityIdentifier("region.key")
                if hasSavedKey {
                    Button("移除已保存的密钥", role: .destructive) { removeKey() }
                }
            } footer: {
                Text(keyError ?? "密钥只保存在本机钥匙串，查询时随请求头发给 Google。")
            }
            Section {
                Button { check() } label: {
                    HStack {
                        Text("查询规则")
                        Spacer()
                        if checking != nil { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(!canCheck)
                .accessibilityIdentifier("region.check")
            }
            if let result {
                Section {
                    QualityRow(title: "\(result.countryCode) 的规则",
                               subtitle: "\(result.videoID)，查询于 \(result.queriedAt.formatted(date: .omitted, time: .shortened))",
                               status: result.result.status) {
                        if let rule = result.result.value {
                            HStack(spacing: 6) { QualityDot(tint: rule.tint); Text(rule.title).foregroundStyle(.secondary) }
                        }
                    }
                    .accessibilityIdentifier("region.result")
                } footer: {
                    Text(note(result))
                }
            }
        }
        .seekGroupedList()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("YouTube 地区规则").navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadKey)
        .onDisappear { checking?.cancel() }
    }

    private func note(_ result: YouTubeRegionCheck) -> String {
        switch result.result.value {
        case .noPublishedRule: "这部视频没有发布地区规则。规则只说明 YouTube 的设置，不代表当前网络所在的国家。"
        case .undetermined: "没有找到这部视频，或者规则的格式无法判断。"
        default: "规则只说明 YouTube 对该国家的设置，不代表当前网络所在的国家。"
        }
    }

    private func loadKey() {
        do {
            apiKey = try YouTubeAPIKeyStore.read()
            hasSavedKey = !apiKey.isEmpty
        } catch { keyError = "无法读取已保存的密钥。" }
    }

    private func removeKey() {
        do {
            try YouTubeAPIKeyStore.save("")
            apiKey = ""; hasSavedKey = false; keyError = nil
        } catch { keyError = "无法移除密钥，请重试。" }
    }

    private func check() {
        let key = apiKey, id = videoID, code = country.uppercased()
        // The answer appears below the form; the keyboard would cover it.
        editing = nil
        do {
            try YouTubeAPIKeyStore.save(key)
            hasSavedKey = true; keyError = nil
        } catch { keyError = "无法保存密钥，本次查询仍会使用它。" }
        checking = Task {
            let check = await checker.checkYouTubeRegion(videoID: id, countryCode: code, apiKey: key)
            if !Task.isCancelled { result = check }
            checking = nil
        }
    }
}

/// The reader's YouTube Data API key. Kept in the Keychain on this device only; offline UI tests keep it in memory.
enum YouTubeAPIKeyStore {
    private static let service = "NodeSeek.Quality.YouTubeAPIKey"
    @MainActor private static var memory: String?
    private static var inMemory: Bool { QualityServices.usesSamples }

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "default"]
    }

    @MainActor static func read() throws -> String {
        if inMemory { return memory ?? "" }
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = value as? Data, let key = String(data: data, encoding: .utf8) else { throw KeyError() }
        return key
    }

    /// An empty key removes the saved one.
    @MainActor static func save(_ key: String) throws {
        if inMemory { memory = key.isEmpty ? nil : key; return }
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyError() }
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8),
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw KeyError() }
        } else if status != errSecSuccess { throw KeyError() }
    }

    struct KeyError: Error {}
}
