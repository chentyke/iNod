import Foundation
import NodeSeekCore

extension SiteDataStore {
    public func drawWinners(_ draw: LuckyDraw) async throws -> [LuckyFloor] {
        let floors: LuckyFloorsResponse = try await load(.luckyFloors(draw))
        let url = URL(string: "https://api.drand.sh/\(LuckyDraw.chain)/public/\(draw.round)")!
        let data: Data
        #if DEBUG
        if let responsesForUITests {
            guard let mock = responsesForUITests[url.absoluteString] else {
                throw SiteError.message("Missing UI test response for \(url.absoluteString)")
            }
            data = mock
        } else {
            data = try await Self.fetchDrandBeaconData(from: url)
        }
        #else
        data = try await Self.fetchDrandBeaconData(from: url)
        #endif
        let beacon = try JSONDecoder().decode(DrandBeacon.self, from: data)
        guard beacon.round == draw.round,
              beacon.randomness.count == 64,
              beacon.randomness.allSatisfy(\.isHexDigit) else {
            throw SiteError.invalidResponse
        }
        return draw.winners(floors: floors.data, randomness: beacon.randomness)
    }

    private static func fetchDrandBeaconData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw SiteError.message("公开随机数暂时不可用，请稍后重试。")
        }
        return data
    }
}

private struct DrandBeacon: Decodable {
    let round: Int
    let randomness: String
}
