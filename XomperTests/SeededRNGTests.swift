import XCTest
@testable import Xomper

/// Tests for `SeededRNG`. The engine relies on same-seed-in →
/// same-sequence-out so test fixtures stay stable.
final class SeededRNGTests: XCTestCase {

    func testSameSeed_producesIdenticalSequence() {
        var a = SeededRNG(seed: 42)
        var b = SeededRNG(seed: 42)
        for _ in 0..<128 {
            XCTAssertEqual(a.next(), b.next(), "Same seed must reproduce next()")
        }
    }

    func testDifferentSeeds_diverge() {
        var a = SeededRNG(seed: 42)
        var b = SeededRNG(seed: 43)
        var divergences = 0
        for _ in 0..<128 {
            if a.next() != b.next() { divergences += 1 }
        }
        XCTAssertGreaterThan(divergences, 100, "Different seeds should rarely collide; expect close to 128 divergences")
    }

    func testNextUnit_inRange() {
        var rng = SeededRNG(seed: 99)
        for _ in 0..<1024 {
            let u = rng.nextUnit()
            XCTAssertGreaterThanOrEqual(u, 0)
            XCTAssertLessThan(u, 1)
        }
    }

    func testNextDouble_respectsBounds() {
        var rng = SeededRNG(seed: 7)
        for _ in 0..<512 {
            let v = rng.nextDouble(in: -1.0..<1.0)
            XCTAssertGreaterThanOrEqual(v, -1.0)
            XCTAssertLessThan(v, 1.0)
        }
    }

    func testNextInt_inRange() {
        var rng = SeededRNG(seed: 31)
        for _ in 0..<512 {
            let n = rng.nextInt(in: 0..<8)
            XCTAssertGreaterThanOrEqual(n, 0)
            XCTAssertLessThan(n, 8)
        }
    }
}
