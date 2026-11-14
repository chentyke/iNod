import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct WebsitePreferencesView: View {
    let userID: Int
    @Environment(AccountSession.self) private var account
    @State private var holiday = false
    @State private var style = ""
    @State private var loaded = false
    @State private var cssLoaded = false
    @State private var busy = false
    @State private var error: String?
    @State private var preferenceMessage: String?
    @State private var cssMessage: String?
    var body: some View {
        Form {
            Section {
                Toggle("官网节日装饰",isOn:$holiday)
                Button("保存节日设置") { Task { await save(style:false) } }.disabled(!loaded || busy)
                if let preferenceMessage { Text(preferenceMessage).font(.caption).foregroundStyle(.secondary) }
            }
            if account.user?.canCustomizeStyle == true {
                Section {
                    TextEditor(text:$style).font(.system(.callout,design:.monospaced)).frame(minHeight:240).autocorrectionDisabled().textInputAutocapitalization(.never).accessibilityLabel("官网自定义 CSS")
                    Button("保存 CSS") { Task { await save(style:true) } }.disabled(!cssLoaded || busy)
                    if let cssMessage { Text(cssMessage).font(.caption).foregroundStyle(.secondary) }
                } header: { Text("官网自定义 CSS") } footer: { Text("这里修改的是官网的网页外观。App 的显示模式在上一页设置。") }
            }
            if let error { Section { Text(error).foregroundStyle(.red); Button("重试") { Task { await load() } } } }
        }.disabled(busy).seekCanvas().listSectionSpacing(20).navigationTitle("官网显示设置").navigationBarTitleDisplayMode(.inline).toolbar(.hidden,for:.tabBar)
        .task { await load() }
    }
    private func load() async {
        guard !busy else { return }; busy = true; defer { busy = false }; error = nil
        do {
            holiday = try await account.website.festiveStyle(userID: userID); loaded = true
            if account.user?.canCustomizeStyle == true {
                style = try await account.website.websiteStyle(userID: userID); cssLoaded = true
            }
        } catch { self.error = error.localizedDescription }
    }
    private func save(style isStyle: Bool) async {
        guard !busy else { return }; busy = true; defer { busy = false }; error = nil
        do {
            if isStyle {
                let _: ReactionResponse = try await account.website.perform(.saveWebsiteStyle(style), userID: userID); cssMessage = "CSS 已保存到 NodeSeek。"
            } else {
                let _: ReactionResponse = try await account.website.perform(.saveFestiveStyle(holiday), userID: userID); preferenceMessage = "节日设置已保存到 NodeSeek。"
            }
        } catch { self.error = error.localizedDescription }
    }
}
