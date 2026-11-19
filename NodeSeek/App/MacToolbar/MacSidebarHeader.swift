#if targetEnvironment(macCatalyst)
import SwiftUI

/// The head of the Mac sidebar: New Post, then the community feed's search and category.
/// On a desktop these sit beside the tabs they serve instead of taking a row above the list.
struct MacSidebarHeader: View {
    let model: MacToolbarModel
    /// Brings the community feed forward before a control acts on it, since the sidebar shows on every tab.
    let showFeed: () -> Void

    var body: some View {
        let _ = model.revision
        VStack(spacing: 10) {
            Button {
                model.requestCompose()
            } label: {
                Label("发布帖子", image: .inkComposePost)
            }
            // Outlined, so it doesn't stack a second dark block on the selected tab below it.
            .buttonStyle(.seekPill(primary: false))

            ForEach(model.items(in: .sidebar)) { item in
                switch item.kind {
                case .search(let prompt, let text):
                    MacSidebarSearchField(item: item, prompt: prompt, text: text, showFeed: showFeed)
                case .menu(let title, let sections):
                    MacSidebarMenu(item: item, title: title ?? item.label, sections: sections, showFeed: showFeed)
                case .button, .share:
                    EmptyView()
                }
            }
        }
        .padding(.bottom, 8)
    }
}

/// Shared look for the sidebar's field and menu: the outlined capsule of the New Post button, a little shorter.
private struct MacSidebarCapsule: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.subheadline)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(Color.seekCard, in: .capsule)
            .overlay { Capsule().strokeBorder(Color.seekHairline.opacity(0.6), lineWidth: 0.5) }
            .contentShape(.capsule)
    }
}

private struct MacSidebarSearchField: View {
    let item: MacToolbarItem
    let prompt: String
    /// The feed's query, which the field follows whenever the reader isn't typing in it.
    let text: String
    let showFeed: () -> Void
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(.inkSearchPosts).foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(prompt, text: $draft)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .submitLabel(.search)
                .onSubmit {
                    showFeed()
                    item.action()
                }
                .accessibilityLabel(item.label)
            if !draft.isEmpty {
                Button("清除搜索", image: .inkClearInput) {
                    draft = ""
                    item.onTextChange("")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .modifier(MacSidebarCapsule())
        .onChange(of: draft) { if isFocused { item.onTextChange(draft) } }
        .onChange(of: text, initial: true) { if !isFocused, draft != text { draft = text } }
    }
}

private struct MacSidebarMenu: View {
    let item: MacToolbarItem
    let title: String
    let sections: [[MacToolbarMenuEntry]]
    let showFeed: () -> Void

    var body: some View {
        Menu {
            ForEach(sections.indices, id: \.self) { index in
                Section {
                    ForEach(sections[index]) { entry in
                        // A toggle draws the menu's own checkmark beside the current sort and category.
                        Toggle(entry.title, isOn: Binding(get: { entry.isOn }, set: { _ in
                            showFeed()
                            entry.action()
                        }))
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(item.image).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(title).foregroundStyle(Color.seekInk).lineLimit(1)
                Spacer(minLength: 0)
                Image(.inkChoose).font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .modifier(MacSidebarCapsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
    }
}
#endif
