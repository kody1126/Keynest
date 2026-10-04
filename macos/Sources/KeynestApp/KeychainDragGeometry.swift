import Foundation

/// Planar grab-point geometry, independent of SceneKit and credential data.
///
/// The caller freezes out-of-plane tilt/yaw during a drag, expresses the held
/// point after those fixed transforms, and intersects the pointer ray with the
/// same plane. The constraint is target = rotateZ(angle) * (a, b - length).
enum KeychainDragGeometry {
    struct Solution: Equatable {
        /// Absolute Z rotation, including any resting angle.
        let angle: Double
        let length: Double
        /// True when physical limits make exact pointer tracking impossible.
        let isConstrained: Bool
    }

    static func solve(grabPoint: SIMD2<Double>, target: SIMD2<Double>,
                      initialLength: Double, angleRange: ClosedRange<Double>,
                      lengthRange: ClosedRange<Double>) -> Solution? {
        let inputs = [grabPoint.x, grabPoint.y, target.x, target.y, initialLength,
                      angleRange.lowerBound, angleRange.upperBound,
                      lengthRange.lowerBound, lengthRange.upperBound]
        guard inputs.allSatisfy(\.isFinite), initialLength > 0,
              lengthRange.lowerBound > 0,
              angleRange.upperBound - angleRange.lowerBound <= 2 * .pi else { return nil }
        let radius = hypot(target.x, target.y)
        guard radius.isFinite else { return nil }

        // Avoid r*r overflow. A point inside |a| is unreachable and is later
        // projected to the allowed length/angle boundary instead of becoming NaN.
        let ratio = radius > 0 ? min(1, abs(grabPoint.x) / radius) : 1
        let height = radius * sqrt(max(0, 1 - ratio * ratio))
        // Usually the grip is below the pivot (+). A chain/collar grip can be
        // above it (-); retaining that branch prevents a jump on first movement.
        let side = initialLength >= grabPoint.y ? 1.0 : -1.0
        let unconstrainedLength = grabPoint.y + side * height
        guard unconstrainedLength.isFinite else { return nil }
        let candidateLength = clamp(unconstrainedLength, to: lengthRange)
        let angleCenter = angleRange.lowerBound + (angleRange.upperBound - angleRange.lowerBound) / 2
        let desiredAngle = radius > 0
            ? atan2(target.x, -target.y) - atan2(grabPoint.x, candidateLength - grabPoint.y)
            : angleCenter
        let unwrappedAngle = angleCenter + (desiredAngle - angleCenter).remainder(dividingBy: 2 * .pi)
        let angle = clamp(unwrappedAngle, to: angleRange)

        // With the angle fixed (possibly clamped), the closest legal length is
        // the projection onto that rotated hanging axis, not the original radius.
        let targetLocalY = -sin(angle) * target.x + cos(angle) * target.y
        let projectedLength = grabPoint.y - targetLocalY
        guard projectedLength.isFinite else { return nil }
        let length = clamp(projectedLength, to: lengthRange)
        let actual = projectedPoint(grabPoint: grabPoint, angle: angle, length: length)
        let tolerance = 1e-8 * max(1, radius, abs(grabPoint.x), abs(grabPoint.y), length)
        let error = hypot(actual.x - target.x, actual.y - target.y)
        guard actual.x.isFinite, actual.y.isFinite, error.isFinite else { return nil }
        return Solution(angle: angle, length: length, isConstrained: error > tolerance)
    }

    static func projectedPoint(grabPoint: SIMD2<Double>, angle: Double, length: Double) -> SIMD2<Double> {
        let x = grabPoint.x, y = grabPoint.y - length
        return SIMD2(cos(angle) * x - sin(angle) * y,
                     sin(angle) * x + cos(angle) * y)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }
}
