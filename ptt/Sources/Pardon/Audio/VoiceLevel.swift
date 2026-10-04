import Foundation

// RMS in dBFS onto 0...1: -50 dB (a quiet room) is 0, -10 dB (loud, close speech) is 1.
func voiceLevel<S: Sequence>(_ samples: S) -> Double where S.Element == Int16 {
    var sum = 0.0
    var count = 0
    for s in samples {
        let x = Double(s) / 32768
        sum += x * x
        count += 1
    }
    guard count > 0, sum > 0 else { return 0 }
    return min(max((10 * log10(sum / Double(count)) + 50) / 40, 0), 1)
}

let levelAttack = 0.6
let levelRelease = 0.15

// Anything that is not a finite number counts as silence.
func smoothLevel(_ previous: Double, toward input: Double) -> Double {
    func unit(_ x: Double) -> Double { x.isFinite ? min(max(x, 0), 1) : 0 }
    let p = unit(previous), x = unit(input)
    return p + (x - p) * (x > p ? levelAttack : levelRelease)
}
