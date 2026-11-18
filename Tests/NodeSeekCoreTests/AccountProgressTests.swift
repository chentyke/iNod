import Foundation
import Testing
@testable import NodeSeekCore

@Test func accountLevelTiersFollowOfficialQuadraticFormula() {
    #expect(AccountLevel.tiers.map(\.level) == [0, 1, 2, 3, 4, 5, 6])
    #expect(AccountLevel.tiers.map(\.requiredCoins) == [0, 100, 400, 900, 1600, 2500, 3600])
    #expect(AccountLevel.requiredCoins(for: -3) == 0)
    #expect(AccountLevel.requiredCoins(for: 9) == 3600)
}

@Test func accountLevelProgressComputesFloorTargetRemainingAndFraction() throws {
    #expect(AccountLevel.progress(forCoins: nil) == nil)

    let negative = try #require(AccountLevel.progress(forCoins: -5))
    #expect(negative.level == 0)
    #expect(negative.currentFloor == 0)
    #expect(negative.nextLevel == 1)
    #expect(negative.nextTarget == 100)
    #expect(negative.remainingCoins == 105)
    #expect(negative.fraction == 0)
    #expect(!negative.isMaxLevel)

    let levelZeroHalf = try #require(AccountLevel.progress(forCoins: 50))
    #expect(levelZeroHalf.level == 0)
    #expect(levelZeroHalf.remainingCoins == 50)
    #expect(abs(levelZeroHalf.fraction - 0.5) < 1e-9)

    let exactLevelOne = try #require(AccountLevel.progress(forCoins: 100))
    #expect(exactLevelOne.level == 1)
    #expect(exactLevelOne.currentFloor == 100)
    #expect(exactLevelOne.nextLevel == 2)
    #expect(exactLevelOne.nextTarget == 400)
    #expect(exactLevelOne.remainingCoins == 300)
    #expect(exactLevelOne.fraction == 0)

    let midLevelThree = try #require(AccountLevel.progress(forCoins: 1280))
    #expect(midLevelThree.level == 3)
    #expect(midLevelThree.currentFloor == 900)
    #expect(midLevelThree.nextLevel == 4)
    #expect(midLevelThree.nextTarget == 1600)
    #expect(midLevelThree.remainingCoins == 320)
    #expect(abs(midLevelThree.fraction - 380.0 / 700.0) < 1e-9)
    #expect(!midLevelThree.isMaxLevel)

    let maxLevel = try #require(AccountLevel.progress(forCoins: 3600))
    #expect(maxLevel.level == 6)
    #expect(maxLevel.currentFloor == 3600)
    #expect(maxLevel.nextLevel == nil)
    #expect(maxLevel.nextTarget == nil)
    #expect(maxLevel.remainingCoins == nil)
    #expect(maxLevel.isMaxLevel)
    #expect(maxLevel.fraction == 1)

    let beyondMax = try #require(AccountLevel.progress(forCoins: 8200))
    #expect(beyondMax.level == 6)
    #expect(beyondMax.isMaxLevel)
    #expect(beyondMax.fraction == 1)
}

@Test func dailyProgressDecodesAndClampsQuotasSafely() throws {
    let raw = #"""
    {
        "postBonusCount": 1,
        "maxPostBonusCount": 4,
        "commentBonusCount": 8,
        "maxCommentBonusCount": 20,
        "freeLikeUsed": 1,
        "maxFreeLike": 3
    }
    """#
    let decoded = try JSONDecoder().decode(DailyProgress.self, from: Data(raw.utf8))
    #expect(decoded.postBonus == DailyProgress.Quota(used: 1, limit: 4))
    #expect(decoded.postBonus.remaining == 3)
    #expect(!decoded.postBonus.isReached)
    #expect(abs(decoded.postBonus.fraction - 0.25) < 1e-9)

    #expect(decoded.commentBonus.remaining == 12)
    #expect(!decoded.commentBonus.isReached)
    #expect(abs(decoded.commentBonus.fraction - 0.4) < 1e-9)

    #expect(decoded.freeLike.remaining == 2)
    #expect(!decoded.freeLike.isReached)
    #expect(abs(decoded.freeLike.fraction - 1.0 / 3.0) < 1e-9)

    // A 0/0 quota (for instance Lv 0 free-like quota) is unavailable rather than completed.
    let zeroLimit = DailyProgress.Quota(used: 0, limit: 0)
    #expect(zeroLimit.remaining == 0)
    #expect(!zeroLimit.isReached)
    #expect(zeroLimit.fraction == 0)

    // Out-of-bounds values clamp without exceeding [0, 1].
    let overLimit = DailyProgress.Quota(used: 6, limit: 4)
    #expect(overLimit.remaining == 0)
    #expect(overLimit.isReached)
    #expect(overLimit.fraction == 1)

    let negativeInput = DailyProgress.Quota(used: -3, limit: 4)
    #expect(negativeInput.used == 0)
    #expect(negativeInput.remaining == 4)
    #expect(!negativeInput.isReached)
    #expect(negativeInput.fraction == 0)
}
