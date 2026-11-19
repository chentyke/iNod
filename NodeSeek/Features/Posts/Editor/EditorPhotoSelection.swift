import NodeSeekClient
import NodeSeekCore
import PhotosUI
import SwiftUI

struct EditorPhotoSelection: ViewModifier {
    let ownerID: Int?
    @Binding var presented: Bool
    @Binding var uploading: Bool
    let onImage: (URL) -> Void
    let onError: (String) -> Void

    @Environment(AccountSession.self) private var account
    @State private var photos: [PhotosPickerItem] = []
    @State private var upload: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $presented, selection: $photos, maxSelectionCount: 10,
                          selectionBehavior: .ordered, matching: .images)
            .onChange(of: photos) { _, selection in
                guard !selection.isEmpty, !uploading else { return }
                photos = []
                uploading = true
                upload = Task {
                    await attachPhotos(selection)
                    if !Task.isCancelled {
                        uploading = false
                        upload = nil
                    }
                }
            }
            .onChange(of: ownerID) { cancel() }
            .onDisappear { cancel() }
    }

    private func cancel() {
        upload?.cancel()
        upload = nil
        uploading = false
    }

    private func attachPhotos(_ photos: [PhotosPickerItem]) async {
        guard let user = account.user, user.id == ownerID else { return }
        let revision = account.revision
        let preferences = NodeImageUploadPreferences(userID: user.id)
        let options = preferences.imageOptions(username: user.name)
        let expiration = preferences.deleteAfterDays
        var links: [URL] = []

        defer {
            if !Task.isCancelled, preferences.copyAfterUpload, !links.isEmpty, account.revision == revision {
                UIPasteboard.general.string = links.map { preferences.linkFormat.text(for: $0) }.joined(separator: "\n")
            }
        }

        do {
            let key = try NodeImageKeyStore.read(userID: user.id)
            guard NodeImageAPI.validKey(key) else {
                throw SiteError.message("请到「我的」中的「图片上传与管理」连接 NodeImage 后再选图。")
            }
            let history = account.nodeImageHistory
            for photo in photos {
                let prepared = try await NodeImageInput.photo(photo).prepare()
                let payload = try await Task.detached(priority: .userInitiated) {
                    try UploadImageProcessor.render(prepared, options: options)
                }.value
                guard !Task.isCancelled, account.revision == revision else { return }
                let image = try await history.client.upload(
                    image: payload.data, format: payload.format, key: key, deleteAfterDays: expiration
                )
                guard !Task.isCancelled, account.revision == revision else { return }
                history.recordUpload(image, userID: user.id, key: key)
                onImage(image.url)
                links.append(image.url)
            }
        } catch {
            if !Task.isCancelled, account.revision == revision { onError(SiteError.displayMessage(for: error)) }
        }
    }
}
