import Foundation
import Darwin

private struct KeychainCheckFailure: Error, CustomStringConvertible {
    let description: String
}

/// Exercises the renderer's real numerical state without constructing an
/// NSApplication, NSWindow, SCNView, Metal device, or any vault-related type.
private final class KeychainChecks {
    private(set) var assertions = 0

    private func expect(_ condition: @autoclosure () -> Bool, _ message: String,
                                 line: UInt = #line) throws {
        assertions += 1
        guard condition() else { throw KeychainCheckFailure(description: "line \(line): \(message)") }
    }

    private func values(_ state: KeychainPendulumState) -> [Double] {
        [state.angle, state.velocity, state.extensionOffset, state.radialVelocity]
    }

    private func isBounded(_ state: KeychainPendulumState) -> Bool {
        values(state).allSatisfy(\.isFinite) && abs(state.angle) <= 0.90 &&
        abs(state.velocity) <= 4 && (-0.28...0.38).contains(state.extensionOffset) &&
        abs(state.radialVelocity) <= 3 && state.energy.isFinite
    }

    func run() throws {
        try timeBoundaries()
        try extremeInputs()
        try settling()
        try releaseBoundaries()
        try reducedMotionAndReset()
        print("PASS: \(assertions) keychain motion assertions; no windows, rendering, hardware, network or vault access.")
    }

    private func timeBoundaries() throws {
        var seed = KeychainPendulumState()
        seed.drag(toAngle: 0.4, extension: 0.12, elapsed: 1.0 / 60, reduceMotion: false)
        for elapsed in [-1.0, -Double.greatestFiniteMagnitude, 0, Double.nan,
                        Double.infinity, -Double.infinity] {
            var state = seed
            state.advance(length: 0.87, elapsed: elapsed)
            try expect(values(state) == values(seed), "Invalid or non-positive elapsed time must not advance a valid pose")
        }
        var shortStep = seed
        shortStep.advance(length: 0.87, elapsed: 1.0 / 120)
        for elapsed in [1.0 / 30, 1, 3_600, Double.greatestFiniteMagnitude] {
            var state = seed
            state.advance(length: 0.87, elapsed: elapsed)
            try expect(values(state) == values(shortStep), "A delayed frame must be capped to one bounded simulation substep")
        }
        try expect(values(shortStep) != values(seed), "A positive elapsed interval must actually advance motion")

        for elapsed in [-1.0, 0, Double.nan, Double.infinity, Double.greatestFiniteMagnitude] {
            var state = KeychainPendulumState()
            state.drag(toAngle: -0.4, extension: 0.2, elapsed: elapsed, reduceMotion: false)
            try expect(isBounded(state), "Invalid drag timing must not divide by zero or create non-finite velocity")
        }
    }

    private func extremeInputs() throws {
        let extremes: [Double] = [-Double.greatestFiniteMagnitude, -1, 0, 1,
                                   Double.greatestFiniteMagnitude, .infinity, -.infinity, .nan]
        for value in extremes {
            var state = KeychainPendulumState()
            state.drag(toAngle: value, extension: value, elapsed: 0, reduceMotion: false)
            try expect(isBounded(state), "Extreme drag coordinates must remain finite and within mechanical limits")
            for _ in 0..<120 {
                state.advance(length: value, coupling: value, ringVelocity: value, elapsed: 1.0 / 120)
            }
            try expect(isBounded(state), "Invalid length or external forces must not destabilize the simulation")
        }
        var state = KeychainPendulumState()
        var remainedBounded = true
        for step in 0..<2_000 {
            let direction = step.isMultiple(of: 2) ? 1.0 : -1.0
            state.drag(toAngle: direction * 1e200, extension: direction * 1e200,
                       elapsed: 1e-200, reduceMotion: false)
            state.advance(length: 0.61, coupling: direction * 1e200,
                          ringVelocity: -direction * 1e200, elapsed: 1_000)
            remainedBounded = remainedBounded && isBounded(state)
        }
        try expect(remainedBounded, "Repeated extreme opposite drags must not accumulate NaN, infinity or unbounded state")

        let untouched = KeychainPendulumState()
        var independent = untouched
        independent.drag(toAngle: 0.6, extension: 0.3, elapsed: 0.02, reduceMotion: false)
        try expect(untouched.energy == 0 && independent.energy > 0,
                   "Independent scene state must not share mutable motion")
    }

    private func settling() throws {
        for length in [0.5, 0.61, 0.87, 3.0] {
            for direction in [-1.0, 1.0] {
                var state = KeychainPendulumState()
                state.drag(toAngle: 0.85 * direction, extension: 0.38 * direction,
                           elapsed: 1.0 / 240, reduceMotion: false)
                var remainedBounded = true
                for _ in 0..<1_200 {
                    state.advance(length: length, elapsed: 1.0 / 120)
                    remainedBounded = remainedBounded && isBounded(state)
                }
                try expect(remainedBounded, "Released motion must stay finite throughout its settling path")
                try expect(state.energy < 0.024, "Released motion must reach the renderer's rest threshold within ten simulated seconds")
            }
        }
        var resting = KeychainPendulumState()
        for _ in 0..<240 { resting.advance(length: 0.87, elapsed: 1.0 / 120) }
        try expect(resting.energy == 0, "A resting ornament must not generate motion by itself")
    }

    private func reducedMotionAndReset() throws {
        var state = KeychainPendulumState()
        state.drag(toAngle: 0.6, extension: 0.2, elapsed: 0.01, reduceMotion: false)
        try expect(state.velocity != 0 && state.radialVelocity != 0, "Normal drag must establish measurable release velocity")
        state.drag(toAngle: -0.4, extension: -0.1, elapsed: 0.01, reduceMotion: true)
        try expect(state.angle == -0.4 && state.extensionOffset == -0.1,
                   "Reduce Motion must preserve direct user-controlled positioning")
        try expect(state.velocity == 0 && state.radialVelocity == 0,
                   "Reduce Motion must clear old inertia instead of preserving a previous fast drag")
        state.drag(toAngle: 0.3, extension: 0.1, elapsed: 0.01, reduceMotion: false)
        let angle = state.angle, distance = state.extensionOffset
        state.stop()
        try expect(state.angle == angle && state.extensionOffset == distance,
                   "Stopping a clock must preserve the last visible pose")
        try expect(state.velocity == 0 && state.radialVelocity == 0,
                   "Stopping must remove both angular and radial inertia")
        state.reset()
        try expect(values(state).allSatisfy { $0 == 0 } && state.energy == 0,
                   "Reset must restore the complete neutral state")
    }

    private func releaseBoundaries() throws {
        var moving = KeychainPendulumState()
        moving.drag(toAngle: 0.5, extension: 0.2, elapsed: 0.02, reduceMotion: false)
        for elapsed in [0.0, 0.04, 0.119] {
            var released = moving
            released.release(idleElapsed: elapsed, reduceMotion: false)
            try expect(values(released) == values(moving),
                       "A fresh release should retain its recent bounded drag velocity")
        }
        for elapsed in [0.12, 0.5, 10, Double.greatestFiniteMagnitude,
                        Double.nan, Double.infinity, -Double.infinity] {
            var released = moving
            released.release(idleElapsed: elapsed, reduceMotion: false)
            try expect(released.velocity == 0 && released.radialVelocity == 0,
                       "Holding still or losing valid timing must discard stale release velocity")
            try expect(released.angle == moving.angle && released.extensionOffset == moving.extensionOffset,
                       "Discarding stale velocity must not snap the held ornament to another position")
        }
        var reduced = moving
        reduced.release(idleElapsed: 0, reduceMotion: true)
        try expect(reduced.velocity == 0 && reduced.radialVelocity == 0,
                   "Even an immediate release under Reduce Motion must suppress both kinds of inertia")

        var held = moving
        held.drag(toAngle: moving.angle, extension: moving.extensionOffset,
                  elapsed: 0.04, reduceMotion: false)
        held.release(idleElapsed: 0.01, reduceMotion: false)
        try expect(held.velocity == 0 && held.radialVelocity == 0,
                   "A stationary final drag sample must clear old movement before a quick mouse-up")
    }
}

@main
private enum KeychainChecksMain {
    static func main() {
        do {
            let checks = KeychainChecks()
            try checks.run()
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(1)
        }
    }
}
