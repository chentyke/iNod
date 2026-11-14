import NodeSeekCore
import SwiftUI

struct ForumDateText: View {
    let value: String
    var body: some View {
        if let date = ForumDate.parse(value) {
            Text(date, format: .dateTime.year().month().day().hour().minute())
        } else { Text(value) }
    }
}
