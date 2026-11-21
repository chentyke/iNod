import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct CategoryPicker: View {
    @Environment(AccountSession.self) private var account
    @Binding var selection: String
    var sort: Binding<FeedSort>?
    @Environment(\.dismiss) private var dismiss
    private var categories: CategoryStore { account.categories }
    private let columns = [GridItem(.adaptive(minimum: 145), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(categories.items) { category in
                        Button {
                            selection = category.id
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    SeekIconTile(symbol: category.inkIcon)
                                    Spacer()
                                    if category.id == selection {
                                        Image(.inkSelectedBoard).foregroundStyle(Color.seekButtonIcon)
                                    }
                                }
                                Text(category.title).font(.headline).foregroundStyle(Color.seekInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .seekCard(padding: 16, radius: 20)
                            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(category.id == selection ? Color.seekGreen : .clear, lineWidth: 1.5) }
                        }
                        .buttonStyle(.seekRow)
                        .accessibilityAddTraits(category.id == selection ? .isSelected : [])
                    }
                }.padding(20)
                if let error = categories.error {
                    VStack(spacing: 12) {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                        Button("重新读取版块") { Task { await categories.refresh(force: true) } }
                    }.padding(20)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let sort {
                    FeedSortPicker(selection: sort)
                        .padding(.horizontal, 20).padding(.top, 8)
                        .background(SeekCanvas())
                }
            }
            .seekCanvas(margins: .keepsGutter, in: .scrollView)
            .navigationTitle("选择版块").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { await categories.refresh() }
            .refreshable { await categories.refresh(force: true) }
        }
        .presentationDragIndicator(.visible)
    }
}
