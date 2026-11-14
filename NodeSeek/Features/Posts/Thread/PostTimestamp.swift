import SwiftUI

struct PostTimestamp: View {
    let date: Date
    @Environment(\.calendar) private var calendar

    var body: some View {
        let style = Date.FormatStyle.dateTime.month().day().hour().minute()
        let isThisYear = calendar.isDate(date, equalTo: .now, toGranularity: .year)
        Text(date, format: isThisYear ? style : style.year())
    }
}
