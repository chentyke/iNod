import NodeSeekCore
import SwiftUI

struct StardustActiveFilterBar: View {
    let chips: [StardustFilter.Chip]
    let onRemove: (StardustFilter.Chip) -> Void
    let onClearAll: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            StardustChipFlowLayout(spacing: StardustMetrics.chipSpacing) {
                ForEach(chips) { chip in
                    Button {
                        onRemove(chip)
                    } label: {
                        HStack(spacing: 4) {
                            Text(chip.label)
                                .monospacedDigit()
                            Image(.inkClearFilter)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.seekButtonIcon)
                                .accessibilityHidden(true)
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.seekInk)
                        .padding(.horizontal, StardustMetrics.chipHorizontalPadding)
                        .padding(.vertical, StardustMetrics.chipVerticalPadding)
                        .background(Color.seekTray, in: .capsule)
                    }
                    .buttonStyle(.seekRow)
                    .accessibilityIdentifier("stardust-chip-\(chip.id)")
                    .accessibilityLabel("移除筛选：\(chip.label)")
                }
            }
            Spacer(minLength: 4)
            Button("清除", action: onClearAll)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.seekGreen)
                .buttonStyle(.seekRow)
                .fixedSize()
                .accessibilityIdentifier("stardust-clear-filters")
                .accessibilityLabel("清除全部筛选")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stardust-active-filters")
    }
}

struct StardustFilterSheet: View {
    @Binding var draft: StardustFilter
    let hasAppliedFilter: Bool
    let onApply: () -> Void
    let onClear: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private var typeOptions: [(id: String, title: String)] {
        [("", "全部")] + StardustRecord.filterableTypes.map { ($0, StardustRecord.typeTitle($0)) }
    }

    private var validationMessage: String? {
        if !draft.isPeerValid {
            return "请输入有效的用户编号或 NodeSeek 个人主页链接。"
        }
        if !draft.isReferenceValid {
            return "Ref ID 需为正整数。"
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("记录类型") {
                    let columns = Array(
                        repeating: GridItem(.flexible(), spacing: 8),
                        count: typeSize.isAccessibilitySize ? 1 : 3
                    )
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(typeOptions, id: \.id) { option in
                            let isSelected = draft.type == option.id
                            Button {
                                draft.type = option.id
                            } label: {
                                Text(option.title)
                                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .foregroundStyle(isSelected ? Color.seekOnInk : Color.seekInk)
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .padding(.horizontal, 8)
                                    .background(isSelected ? Color.seekInk : Color.seekTray, in: .capsule)
                            }
                            .buttonStyle(.seekRow)
                            .accessibilityIdentifier("stardust-filter-type-\(option.id.isEmpty ? "all" : option.id)")
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.seekCard)
                }

                Section {
                    LabeledContent("对方 UID") {
                        TextField("用户编号或主页链接", text: $draft.peer)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("stardust-filter-peer")
                    }
                    .listRowBackground(Color.seekCard)

                    LabeledContent("Ref ID") {
                        TextField("收款或转账编号", text: $draft.reference)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("stardust-filter-reference")
                    }
                    .listRowBackground(Color.seekCard)
                } header: {
                    Text("精确条件")
                } footer: {
                    if let validationMessage {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    } else {
                        Text("可按对方用户编号或主页链接、Ref ID 组合筛选星尘记录。")
                    }
                }

                if !draft.isEmpty || hasAppliedFilter {
                    Section {
                        Button("清除筛选条件", action: onClear)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .accessibilityIdentifier("stardust-sheet-clear-button")
                    }
                    .listRowBackground(Color.seekCard)
                }
            }
            .seekCanvas()
            .listSectionSpacing(20)
            .navigationTitle("筛选记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用", action: onApply)
                        .fontWeight(.semibold)
                        .disabled(!draft.isValid)
                        .accessibilityIdentifier("stardust-filter-apply")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct StardustChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(in: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.enumerated().reduce(CGFloat.zero) { total, item in
            total + item.element.height + (item.offset > 0 ? spacing : 0)
        }
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(in: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for entry in row.entries {
                let yOffset = (row.height - entry.size.height) / 2
                entry.subview.place(
                    at: CGPoint(x: x, y: y + yOffset),
                    proposal: ProposedViewSize(entry.size)
                )
                x += entry.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        struct Entry {
            let subview: LayoutSubview
            let size: CGSize
        }
        var entries: [Entry] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(in maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for subview in subviews {
            let fitting = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let nextWidth = current.entries.isEmpty ? fitting.width : current.width + spacing + fitting.width
            if !current.entries.isEmpty, nextWidth > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.entries.append(.init(subview: subview, size: fitting))
            current.width = current.entries.count == 1 ? fitting.width : current.width + spacing + fitting.width
            current.height = max(current.height, fitting.height)
        }
        if !current.entries.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
