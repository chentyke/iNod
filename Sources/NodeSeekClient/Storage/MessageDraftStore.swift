import NodeSeekCore
import Foundation

@MainActor
public enum MessageDraftStore {
    public static func load(ownerID: Int, peerID: Int) -> MessageDraft {
        guard let data = UserDefaults.standard.data(forKey: MessageDraft.key(ownerID: ownerID, peerID: peerID)),
              let draft = try? JSONDecoder().decode(MessageDraft.self, from: data) else { return MessageDraft() }
        return draft
    }
    public static func save(_ draft: MessageDraft, ownerID: Int, peerID: Int) {
        let key = MessageDraft.key(ownerID: ownerID, peerID: peerID)
        if draft.content.isEmpty { UserDefaults.standard.removeObject(forKey: key) }
        else if let data = try? JSONEncoder().encode(draft) { UserDefaults.standard.set(data, forKey: key) }
    }
}
