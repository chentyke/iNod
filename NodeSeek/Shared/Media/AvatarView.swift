import NodeSeekClient
import SwiftUI

struct AvatarView: View {
    let name: String
    let url: URL?
    var size: CGFloat = 32
    @Environment(AccountSession.self) private var account
    @State private var image: CGImage?
    @State private var loadedURL: URL?
    private var imageURL: URL? {
        url.map { account.versionedAvatarURL($0) }
    }

    private var displayedImage: CGImage? {
        guard let imageURL else { return nil }
        if loadedURL == imageURL, let image { return image }
        return AvatarImageLoader.shared.image(for: imageURL)
    }

    /// Stable per-name color, so a member keeps the same monogram everywhere.
    private var monogramTint: Color {
        let palette: [Color] = [.blue, .indigo, .purple, .pink, .orange, .teal, .cyan, .mint, .seekGreen]
        let seed = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[seed % palette.count]
    }

    var body: some View {
        Group {
            if let image = displayedImage {
                Image(image, scale: 1, label: Text(name)).resizable().scaledToFill()
            } else {
                Circle().fill(monogramTint.gradient)
                    .overlay { Text(String(name.prefix(1)).uppercased()).font(.system(size: size * 0.42, weight: .semibold, design: .rounded)).foregroundStyle(.white) }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityHidden(true)
        .task(id: imageURL) {
            let url = imageURL
            loadedURL = url
            image = url.flatMap { AvatarImageLoader.shared.image(for: $0) }
            guard image == nil, let url else { return }
            do {
                let result = try await AvatarImageLoader.shared.load(url)
                try Task.checkCancellation()
                image = result
            } catch { }
        }
    }
}
