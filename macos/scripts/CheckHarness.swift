// A small executable-test adapter for Command Line Tools installations without
// XCTest. The original tests are compiled unchanged except for their imports.
// This supports the assertion/lifecycle APIs actually used by this repository;
// unsupported future APIs fail compilation rather than becoming no-ops.
import Foundation

private struct RecordedAssertionFailure: Error {}
private enum HarnessProbeError: Error { case expected }

private final class CheckState: @unchecked Sendable {
    static let shared = CheckState()
    private let mutex = NSLock()
    private var assertions = 0
    private var failures = 0
    private var tests = 0
    private var failedTests = 0
    private var currentTest = "harness"

    func assertion() {
        mutex.lock(); defer { mutex.unlock() }
        assertions += 1
    }

    func failure(_ description: String, file: StaticString, line: UInt) {
        mutex.lock(); defer { mutex.unlock() }
        failures += 1
        print("FAIL \(currentTest): \(file):\(line): \(description)")
    }

    func begin(_ name: String) -> Int {
        mutex.lock(); defer { mutex.unlock() }
        currentTest = name
        tests += 1
        return failures
    }

    func end(_ name: String, previousFailures: Int) {
        mutex.lock(); defer { mutex.unlock() }
        if failures == previousFailures {
            print("PASS \(name)")
        } else {
            failedTests += 1
            print("FAIL \(name) (\(failures - previousFailures) failure(s))")
        }
    }

    func snapshot() -> (tests: Int, assertions: Int, failures: Int, failedTests: Int) {
        mutex.lock(); defer { mutex.unlock() }
        return (tests, assertions, failures, failedTests)
    }
}

class XCTestCase {
    private var teardownBlocks: [() throws -> Void] = []

    func setUp() {}
    func setUpWithError() throws {}
    func tearDown() {}
    func tearDownWithError() throws {}

    func addTeardownBlock(_ block: @escaping () throws -> Void) {
        teardownBlocks.append(block)
    }

    fileprivate func performTeardownBlocks() {
        for block in teardownBlocks.reversed() {
            do { try block() }
            catch {
                CheckState.shared.failure("Teardown block threw an error.", file: #filePath, line: #line)
            }
        }
        teardownBlocks.removeAll()
    }
}

private func assertionFailure(_ name: String, _ message: () -> String, file: StaticString, line: UInt) {
    let extra = message()
    CheckState.shared.failure(extra.isEmpty ? name : "\(name): \(extra)", file: file, line: line)
}

func XCTAssertTrue(_ expression: @autoclosure () throws -> Bool,
                   _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    CheckState.shared.assertion()
    do {
        if try !expression() { assertionFailure("XCTAssertTrue failed", message, file: file, line: line) }
    } catch { assertionFailure("XCTAssertTrue expression threw", message, file: file, line: line) }
}

func XCTAssertFalse(_ expression: @autoclosure () throws -> Bool,
                    _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    CheckState.shared.assertion()
    do {
        if try expression() { assertionFailure("XCTAssertFalse failed", message, file: file, line: line) }
    } catch { assertionFailure("XCTAssertFalse expression threw", message, file: file, line: line) }
}

func XCTAssertNil<T>(_ expression: @autoclosure () throws -> T?,
                     _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    CheckState.shared.assertion()
    do {
        if try expression() != nil { assertionFailure("XCTAssertNil failed", message, file: file, line: line) }
    } catch { assertionFailure("XCTAssertNil expression threw", message, file: file, line: line) }
}

func XCTAssertEqual<T: Equatable>(_ first: @autoclosure () throws -> T, _ second: @autoclosure () throws -> T,
                                  _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    CheckState.shared.assertion()
    do {
        let left = try first()
        let right = try second()
        if left != right { assertionFailure("XCTAssertEqual failed", message, file: file, line: line) }
    } catch { assertionFailure("XCTAssertEqual expression threw", message, file: file, line: line) }
}

func XCTAssertNotEqual<T: Equatable>(_ first: @autoclosure () throws -> T, _ second: @autoclosure () throws -> T,
                                     _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    CheckState.shared.assertion()
    do {
        let left = try first()
        let right = try second()
        if left == right { assertionFailure("XCTAssertNotEqual failed", message, file: file, line: line) }
    } catch { assertionFailure("XCTAssertNotEqual expression threw", message, file: file, line: line) }
}

func XCTAssertLessThan<T: Comparable>(_ first: @autoclosure () throws -> T, _ second: @autoclosure () throws -> T,
                                      _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    CheckState.shared.assertion()
    do {
        let left = try first()
        let right = try second()
        if !(left < right) { assertionFailure("XCTAssertLessThan failed", message, file: file, line: line) }
    } catch { assertionFailure("XCTAssertLessThan expression threw", message, file: file, line: line) }
}

func XCTAssertNoThrow<T>(_ expression: @autoclosure () throws -> T,
                         _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    CheckState.shared.assertion()
    do { _ = try expression() }
    catch { assertionFailure("XCTAssertNoThrow expression threw", message, file: file, line: line) }
}

func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T,
                             _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line,
                             _ errorHandler: (Error) throws -> Void = { _ in }) {
    CheckState.shared.assertion()
    do {
        _ = try expression()
        assertionFailure("XCTAssertThrowsError did not throw", message, file: file, line: line)
    } catch {
        do { try errorHandler(error) }
        catch { assertionFailure("XCTAssertThrowsError handler threw", message, file: file, line: line) }
    }
}

func XCTUnwrap<T>(_ expression: @autoclosure () throws -> T?,
                  _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) throws -> T {
    CheckState.shared.assertion()
    let value: T?
    do { value = try expression() }
    catch {
        assertionFailure("XCTUnwrap expression threw", message, file: file, line: line)
        throw error
    }
    guard let value else {
        assertionFailure("XCTUnwrap found nil", message, file: file, line: line)
        throw RecordedAssertionFailure()
    }
    return value
}

enum CheckRunner {
    static func run<T: XCTestCase>(_ name: String, makeCase: () -> T, body: (T) throws -> Void) {
        let previousFailures = CheckState.shared.begin(name)
        let instance = makeCase()
        do {
            try instance.setUpWithError()
            instance.setUp()
            try body(instance)
        } catch is RecordedAssertionFailure {
            // XCTUnwrap already registered this failure before throwing.
        } catch {
            CheckState.shared.failure("Test threw an uncaught error: \(error.localizedDescription)", file: #filePath, line: #line)
        }
        instance.performTeardownBlocks()
        do { try instance.tearDownWithError() }
        catch { CheckState.shared.failure("tearDownWithError threw.", file: #filePath, line: #line) }
        instance.tearDown()
        CheckState.shared.end(name, previousFailures: previousFailures)
    }

    static func finish(expectedTestCount: Int) -> Int32 {
        var snapshot = CheckState.shared.snapshot()
        if snapshot.tests != expectedTestCount || snapshot.tests == 0 || snapshot.assertions == 0 {
            CheckState.shared.failure("Test discovery/execution count mismatch.", file: #filePath, line: #line)
            snapshot = CheckState.shared.snapshot()
        }
        print("\n\(snapshot.tests) tests, \(snapshot.assertions) assertions, \(snapshot.failedTests) failed tests, \(snapshot.failures) failures")
        return snapshot.failures == 0 ? 0 : 1
    }

    // Executed in a separate process before the real suite. Every assertion API
    // is deliberately failed, and the shell verifies both count and exit code.
    static func negativeSelfTest() -> Int32 {
        run("Harness negative self-test", makeCase: { XCTestCase() }) { _ in
            func throwingValue() throws -> Int { throw HarnessProbeError.expected }
            XCTAssertTrue(false)
            XCTAssertFalse(true)
            XCTAssertNil(Optional(1))
            XCTAssertEqual(1, 2)
            XCTAssertNotEqual(1, 1)
            XCTAssertLessThan(2, 1)
            XCTAssertNoThrow(try throwingValue())
            XCTAssertThrowsError(1)
            do { _ = try XCTUnwrap(Optional<Int>.none) } catch {}
        }
        let snapshot = CheckState.shared.snapshot()
        let status = finish(expectedTestCount: 1)
        if snapshot.assertions == 9 && snapshot.failures == 9 && status == 1 {
            print("HARNESS_SELF_TEST_OK")
        }
        return status
    }
}
