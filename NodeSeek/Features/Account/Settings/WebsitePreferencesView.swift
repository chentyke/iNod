import NodeSeekCore
import NodeSeekClient
import SwiftUI

private struct WebsitePreferencesSnapshot: Decodable, Equatable {
    var holiday: Bool
    var style: String
    var canCustomizeStyle: Bool
}

struct WebsitePreferencesView: View {
    let userID: Int
    @Environment(AccountSession.self) private var account
    @State private var snapshot: WebsitePreferencesSnapshot?
    @State private var holiday = false
    @State private var style = ""
    @State private var failure: LoadFailure?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var savedMessage: String?

    private var canCustomizeStyle: Bool {
        snapshot?.canCustomizeStyle ?? (account.user?.canCustomizeStyle == true)
    }

    private var hasHolidayChange: Bool {
        guard let snapshot else { return false }
        return holiday != snapshot.holiday
    }

    private var hasStyleChange: Bool {
        guard let snapshot, snapshot.canCustomizeStyle else { return false }
        return style != snapshot.style
    }

    private var hasChanges: Bool {
        hasHolidayChange || hasStyleChange
    }

    var body: some View {
        AccountDataView(
            value: snapshot,
            error: failure,
            isBusy: isLoading || isSaving,
            retry: { await load() }
        ) { data in
            List {
                if let savedMessage, !hasChanges {
                    Section {
                        SettingsFeedbackRow(message: savedMessage, isSuccess: true)
                            .listRowBackground(Color.seekCard)
                    }
                }

                Section {
                    Toggle(isOn: $holiday) {
                        SettingsRowContent(
                            title: "官网节日装饰",
                            subtitle: "节日期间在 NodeSeek 网页端展示主题装饰",
                            symbol: "sparkles",
                            tint: holiday ? .seekGreen : .seekInk
                        )
                    }
                    .tint(Color.seekGreen)
                    .accessibilityIdentifier("website-festive-toggle")
                    .settingsRowStyle(alignSeparator: false)
                } header: {
                    SeekSectionTitle(title: "网页偏好")
                } footer: {
                    Text("这里修改的是浏览器中 NodeSeek 官网的外观；iNod 客户端的浅色与深色模式在上一页设置。")
                }

                if data.canCustomizeStyle {
                    Section {
                        ZStack(alignment: .topLeading) {
                            if style.isEmpty {
                                Text("/* 输入作用于 NodeSeek 官网页面的 CSS */")
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $style)
                                .font(.system(.callout, design: .monospaced))
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 220)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .accessibilityLabel("官网自定义 CSS")
                                .accessibilityIdentifier("website-css-editor")
                        }
                        .listRowBackground(Color.seekCard)

                        if hasStyleChange {
                            Button("还原未保存的 CSS") {
                                style = data.style
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.seekCard)
                            .accessibilityIdentifier("website-css-reset-button")
                        }
                    } header: {
                        SeekSectionTitle(
                            title: "官网自定义 CSS",
                            detail: style.isEmpty ? nil : "\(style.count.formatted()) 字符"
                        )
                    } footer: {
                        Text("仅在浏览器打开 NodeSeek 官网时生效，不影响客户端原生阅读排版。")
                    }
                }
            }
            .seekGroupedList()
            .contentMargins(.top, 12, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
            .disabled(isSaving)
        }
        .navigationTitle("官网显示设置")
        .interactiveDismissDisabled(isSaving)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "保存中…" : "保存") {
                    Task { await saveChanges() }
                }
                .fontWeight(.semibold)
                .disabled(snapshot == nil || isLoading || isSaving || !hasChanges)
                .accessibilityIdentifier("website-preferences-save-button")
            }
        }
        .onChange(of: holiday) {
            if hasChanges { savedMessage = nil }
        }
        .onChange(of: style) {
            if hasChanges { savedMessage = nil }
        }
        .task {
            if snapshot == nil {
                await load()
            }
        }
        .refreshable { await load() }
    }

    private func load() async {
        guard !isLoading, !isSaving else { return }
        isLoading = true
        failure = nil
        defer { isLoading = false }
        do {
            let allowsCSS = account.user?.canCustomizeStyle == true
            let loadedHoliday = try await account.website.festiveStyle(userID: userID)
            let loadedStyle = allowsCSS ? try await account.website.websiteStyle(userID: userID) : ""
            try Task.checkCancellation()
            let fresh = WebsitePreferencesSnapshot(
                holiday: loadedHoliday,
                style: loadedStyle,
                canCustomizeStyle: allowsCSS
            )
            let hadUnsavedChanges = hasChanges
            snapshot = fresh
            if !hadUnsavedChanges {
                holiday = loadedHoliday
                style = loadedStyle
            }
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled {
                failure = LoadFailure(error)
            }
        }
    }

    private func saveChanges() async {
        guard !isLoading, !isSaving, var current = snapshot, hasChanges else { return }
        isSaving = true
        failure = nil
        defer { isSaving = false }
        let changedHoliday = holiday != current.holiday
        let changedStyle = current.canCustomizeStyle && style != current.style
        do {
            if changedHoliday {
                let _: ReactionResponse = try await account.website.perform(
                    .saveFestiveStyle(holiday),
                    userID: userID
                )
                current.holiday = holiday
                snapshot = current
            }
            if changedStyle {
                let _: ReactionResponse = try await account.website.perform(
                    .saveWebsiteStyle(style),
                    userID: userID
                )
                current.style = style
                snapshot = current
            }
            savedMessage = changedHoliday && changedStyle
                ? "官网节日装饰与自定义 CSS 已保存。"
                : (changedStyle ? "自定义 CSS 已保存到 NodeSeek。" : "节日设置已保存到 NodeSeek。")
        } catch {
            failure = LoadFailure(error)
        }
    }
}
