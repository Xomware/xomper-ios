import Foundation

/// Deterministic `RandomNumberGenerator` for reproducible mock-draft
/// runs. Uses the SplitMix64 PRNG — tiny, fast, and stateful via a
/// single `UInt64` seed. Same seed in → identical sequence out, which
/// is exactly what the engine tests rely on for the Wildcard / Hype
/// Train cases.
///
/// Not cryptographically secure. We don't need it to be — the only
/// goal is "two runs with seed 42 must match, and seeds 42 vs 43 must
/// differ in observable output."
///
/// Reference: Vigna 2014. Implementation matches the canonical
/// SplitMix64 constants used in the Swift forum thread for the
/// `RandomNumberGenerator` protocol.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Avoid the degenerate state == 0 case by mixing the seed
        // through one round of SplitMix64 up-front. Calling code that
        // passes seed = 0 still gets a useful sequence.
        self.state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z &>> 31)
    }

    /// Convenience: uniform `Double` in `[0, 1)`. Useful for jitter and
    /// percentage-based sampling without paying the `Double.random(in:)`
    /// indirection through a `_modifying` accessor.
    mutating func nextUnit() -> Double {
        // Use the top 53 bits — fits in a Double's mantissa without
        // rounding. Standard pattern from Vigna's reference.
        let bits = next() &>> 11
        return Double(bits) * (1.0 / Double(1 &<< 53))
    }

    /// Uniform `Double` in `[lower, upper)`. Both bounds finite; no
    /// guard for `upper <= lower` — callers must validate.
    mutating func nextDouble(in range: Range<Double>) -> Double {
        let u = nextUnit()
        return range.lowerBound + u * (range.upperBound - range.lowerBound)
    }

    /// Uniform integer in `[lower, upper)`. Crashes on empty ranges
    /// to match `Int.random(in:)` semantics.
    mutating func nextInt(in range: Range<Int>) -> Int {
        precondition(range.lowerBound < range.upperBound, "SeededRNG.nextInt requires non-empty range")
        let span = UInt64(range.upperBound - range.lowerBound)
        // Modulo bias is acceptable for our small spans (Wildcard
        // top-N = 8, etc.). Documented tradeoff for v1.
        return range.lowerBound + Int(next() % span)
    }
}
