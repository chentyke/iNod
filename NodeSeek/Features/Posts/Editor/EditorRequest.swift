import NodeSeekCore
import Foundation

struct EditorRequest: Identifiable {
    let id = UUID()
    let mode: EditorMode
    let seed: EditorDraft
}
