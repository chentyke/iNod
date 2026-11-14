import Foundation

public struct ForumSticker: Equatable, Hashable, Sendable {
    public let code: String
    public let filename: String
    public let group: String
    public let isVideo: Bool

    public var url: URL {
        NodeSeekRoute.origin.appending(path: "static/image/sticker/\(group)/\(filename)" + (isVideo ? ".mov" : ""))
    }

    public static func named(_ code: String) -> ForumSticker? {
        for (group, files) in filesByGroup {
            guard code.hasPrefix(group) else { continue }
            let name = String(code.dropFirst(group.count))
            guard let file = files.first(where: { $0.split(separator: ".").first.map(String.init) == name }) else { continue }
            return ForumSticker(code: code, filename: file, group: group, isVideo: group == "emoji")
        }
        return nil
    }

    public static func all(in group: String) -> [ForumSticker] {
        (filesByGroup[group] ?? []).compactMap { named(group + String($0.split(separator: ".")[0])) }
    }

    // File names from the official NodeSeek editor, checked on 2026-10-15.
    private static let filesByGroup: [String: [String]] = [
        "ac": "01.png,02.png,03.png,04.png,05.png,06.png,07.png,08.png,09.png,10.png,11.png,12.png,13.png,14.png,15.png,16.png,17.png,18.png,19.png,20.png,21.png,22.png,23.png,24.png,25.png,26.png,27.png,28.png,29.png,30.png,31.png,32.png,33.png,34.png,35.png,36.png,37.png,38.png,39.png,40.png,41.png,42.png,43.png,44.png,45.png,46.png,47.png,48.png,49.png,50.png,51.png,52.png,53.png,54.png,1001.png,1002.png,1003.png,1004.png,1005.png,1006.png,1007.png,1008.png,1009.png,1010.png,1011.png,1012.png,1013.png,1014.png,1015.png,1016.png,1017.png,1018.png,1019.png,1020.png,1021.png,1022.png,1023.png,1024.png,1025.png,1026.png,1027.png,1028.png,1029.png,1030.png,1031.png,1032.png,1033.png,1034.png,1035.png,1036.png,1037.png,1038.png,1039.png,1040.png,2001.png,2002.png,2003.png,2004.png,2005.png,2006.png,2007.png,2008.png,2009.png,2010.png,2011.png,2012.png,2013.png,2014.png,2015.png,2016.png,2017.png,2018.png,2019.png,2020.png,2021.png,2022.png,2023.png,2024.png,2025.png,2026.png,2027.png,2028.png,2029.png,2030.png,2031.png,2032.png,2033.png,2034.png,2035.png,2036.png,2037.png,2038.png,2039.png,2040.png,2041.png,2042.png,2043.png,2044.png,2045.png,2046.png,2047.png,2048.png,2049.png,2050.png,2051.png,2052.png,2053.png,2054.png,2055.png".split(separator: ",").map(String.init),
        "yct": "001.gif,002.gif,003.gif,004.gif,005.gif,006.gif,007.gif,008.gif,009.gif,010.gif,011.gif,012.gif,013.gif,014.gif,015.gif,016.gif,017.gif,018.gif,019.gif,020.gif,021.gif,022.gif".split(separator: ",").map(String.init),
        "xhj": "001.png,002.png,003.png,004.gif,005.png,006.png,007.png,008.gif,009.gif,010.gif,011.png,012.gif,013.gif,014.gif,015.gif,016.gif,017.gif,018.gif,019.gif,020.gif,021.gif,022.png,023.gif,024.png,025.png,026.gif,027.gif,028.gif,029.gif,030.gif,031.png,032.png".split(separator: ",").map(String.init),
        "emoji": "00,01,02,03,04,05,06,07,08,09,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48".split(separator: ",").map(String.init),
    ]
}
