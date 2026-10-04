import Testing
@testable import PardonKit

@Suite struct VoiceLevelTests {
    @Test func level() {
        check("level: empty buffer is 0", voiceLevel([Int16]()) == 0)
        check("level: silence is 0", voiceLevel([Int16](repeating: 0, count: 64)) == 0)
        check("level: full scale is 1", voiceLevel([Int16.max, Int16.min, Int16.max, Int16.min]) == 1)
        check("level: -30 dBFS is mid-scale", abs(voiceLevel([Int16](repeating: 1036, count: 64)) - 0.5) < 0.01)
        check("level: below -50 dBFS is 0", voiceLevel([Int16](repeating: 10, count: 64)) == 0)
        check("level: -40 dBFS is a quarter", abs(voiceLevel([Int16](repeating: 328, count: 64)) - 0.25) < 0.01)
        check("level: -10 dBFS reaches the top", voiceLevel([Int16](repeating: 10363, count: 64)) == 1
              && voiceLevel([Int16](repeating: 10362, count: 64)) >= 0.99)
        check("level: just above -50 dBFS is small but positive", (0..<0.01).contains(voiceLevel([Int16](repeating: 104, count: 64)))
              && voiceLevel([Int16](repeating: 104, count: 64)) > 0)
        check("level: RMS, not peak or mean", abs(voiceLevel([Int16](repeating: 0, count: 32) + [Int16](repeating: 1465, count: 32)) - 0.5) < 0.01)
    }

    @Test func smooth() {
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
        check("smooth: fast attack", near(smoothLevel(0, toward: 1), levelAttack))
        check("smooth: slower release", near(smoothLevel(1, toward: 0), 1 - levelRelease) && levelRelease < levelAttack)
        check("smooth: input above 1 is capped", near(smoothLevel(0.5, toward: 7), 0.5 + 0.5 * levelAttack))
        check("smooth: NaN input counts as silence", near(smoothLevel(0.5, toward: .nan), 0.5 - 0.5 * levelRelease))
        check("smooth: negative input counts as silence", near(smoothLevel(0.5, toward: -3), 0.5 - 0.5 * levelRelease))
        check("smooth: infinite input counts as silence", near(smoothLevel(0.5, toward: .infinity), 0.5 - 0.5 * levelRelease))
        check("smooth: NaN previous starts from 0", near(smoothLevel(.nan, toward: 0.5), 0.5 * levelAttack))
        check("smooth: previous above 1 starts from 1", near(smoothLevel(5, toward: 0.5), 1 - 0.5 * levelRelease))
        check("smooth: negative previous starts from 0", near(smoothLevel(-2, toward: 0.5), 0.5 * levelAttack))
    }
}
