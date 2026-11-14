import NodeSeekCore
import Foundation

@MainActor
public enum EditorDraftStore {
    public static func load(ownerID: Int, mode: EditorMode) -> EditorDraft? {
        guard let data = UserDefaults.standard.data(forKey: EditorDraft.key(ownerID: ownerID, mode: mode)) else { return nil }
        return try? JSONDecoder().decode(EditorDraft.self, from: data)
    }
    public static func save(_ draft: EditorDraft?, ownerID: Int, mode: EditorMode) {
        let key = EditorDraft.key(ownerID: ownerID, mode: mode)
        if let draft, let data = try? JSONEncoder().encode(draft) { UserDefaults.standard.set(data, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }
}
