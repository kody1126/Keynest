import Foundation
import Darwin

private struct DragCheckFailure: Error { let message: String }

@main private enum KeychainDragChecks {
    static func main() {
        var assertions = 0
        var cases = 0
        func expect(_ condition: Bool, _ message: String) throws {
            assertions += 1
            guard condition else { throw DragCheckFailure(message: message) }
        }
        func close(_ first: Double, _ second: Double, tolerance: Double = 1e-8) -> Bool {
            abs(first - second) <= tolerance
        }
        func solved(_ point: SIMD2<Double>, _ target: SIMD2<Double>, initial: Double,
                    angles: ClosedRange<Double> = -0.9...0.9,
                    lengths: ClosedRange<Double> = 0.3...2.2) throws -> KeychainDragGeometry.Solution {
            guard let value = KeychainDragGeometry.solve(grabPoint: point, target: target,
                                                         initialLength: initial, angleRange: angles,
                                                         lengthRange: lengths) else {
                throw DragCheckFailure(message: "A finite valid geometry unexpectedly failed to solve")
            }
            return value
        }

        do {
            // The prior world-space offset method drifted ~0.115 world units
            // when this held point moved 0.10 along x. This solves the grip itself.
            let grip = SIMD2<Double>(0, -0.6)
            let target = SIMD2<Double>(0.1, -1.11)
            let result = try solved(grip, target, initial: 0.51)
            let actual = KeychainDragGeometry.projectedPoint(grabPoint: grip, angle: result.angle, length: result.length)
            try expect(close(actual.x, target.x) && close(actual.y, target.y), "The actual held point must follow the pointer exactly")
            try expect(!result.isConstrained, "An ordinary small drag should not hit a physical limit")
            cases += 1

            // Includes 0.7-1.8 chains, off-center grips, both resting-angle signs,
            // and sampled user angles. Round-trip the actual geometric point.
            for length in [0.7, 1.1, 1.8] {
                for restAngle in [-0.08, 0.07] {
                    for motionAngle in [-0.65, -0.2, 0.0, 0.3, 0.65] {
                        for grip in [SIMD2<Double>(0, -0.65), SIMD2(0.23, -0.4), SIMD2(-0.2, -0.8)] {
                            let absoluteAngle = restAngle + motionAngle
                            let target = KeychainDragGeometry.projectedPoint(grabPoint: grip, angle: absoluteAngle, length: length)
                            let answer = try solved(grip, target, initial: length,
                                                    angles: (restAngle - 0.85)...(restAngle + 0.85),
                                                    lengths: (length - 0.28)...(length + 0.38))
                            try expect(close(answer.angle, absoluteAngle), "Resting angle must be included exactly once")
                            try expect(close(answer.length, length), "Solving must preserve the intended chain length")
                            try expect(!answer.isConstrained, "Reachable sampled grips must track without clamping")
                            cases += 1
                        }
                    }
                }
            }

            let upperGrip = SIMD2<Double>(0.09, 0.82)
            let upperTarget = KeychainDragGeometry.projectedPoint(grabPoint: upperGrip, angle: 0.13, length: 0.7)
            let upper = try solved(upperGrip, upperTarget, initial: 0.7, lengths: 0.42...1.08)
            try expect(close(upper.angle, 0.13) && close(upper.length, 0.7), "A grip above the pivot must retain the initial branch")
            try expect(!upper.isConstrained, "An above-pivot collar grip can be reachable")
            cases += 1

            let limitedGrip = SIMD2<Double>(0.16, -0.5)
            let outside = KeychainDragGeometry.projectedPoint(grabPoint: limitedGrip, angle: 1.2, length: 1)
            let limited = try solved(limitedGrip, outside, initial: 1, angles: -0.4...0.4, lengths: 0.3...2)
            try expect(close(limited.angle, 0.4) && limited.isConstrained, "Angle limits must remain explicit and finite")
            let expectedLength = limitedGrip.y - (-sin(limited.angle) * outside.x + cos(limited.angle) * outside.y)
            try expect(close(limited.length, min(2, max(0.3, expectedLength))), "After angle clipping, project the closest legal length")
            cases += 1

            for desiredLength in [0.1, 3.0] {
                let target = KeychainDragGeometry.projectedPoint(grabPoint: grip, angle: 0.2, length: desiredLength)
                let answer = try solved(grip, target, initial: 1, lengths: 0.72...1.38)
                try expect(close(answer.length, desiredLength < 0.72 ? 0.72 : 1.38), "Length limits must constrain unreachable pointer locations")
                try expect(answer.isConstrained, "A clipped chain length must be reported")
                cases += 1
            }

            let centered = try solved(SIMD2(0.2, -0.3), .zero, initial: 1)
            try expect(centered.angle.isFinite && centered.length.isFinite && centered.isConstrained,
                       "Dragging through the anchor must not create NaN or divide by zero")
            let inside = try solved(SIMD2(0.4, -0.3), SIMD2(0.03, -0.02), initial: 1)
            try expect(inside.angle.isFinite && inside.length.isFinite && inside.isConstrained,
                       "An unreachable radius smaller than the horizontal grip offset must stay bounded")
            cases += 1

            for bad in [Double.nan, Double.infinity, -Double.infinity] {
                try expect(KeychainDragGeometry.solve(grabPoint: SIMD2(bad, 0), target: SIMD2(0, -1),
                                                       initialLength: 1, angleRange: -1...1, lengthRange: 0.3...2) == nil,
                           "Non-finite grab offsets must be rejected")
                try expect(KeychainDragGeometry.solve(grabPoint: grip, target: SIMD2(0, bad),
                                                       initialLength: 1, angleRange: -1...1, lengthRange: 0.3...2) == nil,
                           "Non-finite pointer inputs must be rejected")
            }
            try expect(KeychainDragGeometry.solve(grabPoint: grip, target: SIMD2(0, -1),
                                                   initialLength: 0, angleRange: -1...1, lengthRange: 0.3...2) == nil,
                       "A nonpositive initial chain length must be rejected")
            try expect(KeychainDragGeometry.solve(grabPoint: grip, target: SIMD2(0, -1),
                                                   initialLength: 1, angleRange: -1...1, lengthRange: 0...2) == nil,
                       "A length range including zero must be rejected")
            cases += 1
            print("PASS Keychain drag geometry: \(cases) cases, \(assertions) assertions; pure planar math, no App, renderer, window or vault.")
        } catch let error as DragCheckFailure {
            print("FAIL Keychain drag geometry: \(error.message)")
            exit(1)
        } catch {
            print("FAIL Keychain drag geometry: unexpected error")
            exit(1)
        }
    }
}
