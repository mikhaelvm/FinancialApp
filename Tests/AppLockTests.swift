import XCTest
import LocalAuthentication
@testable import FinancialApp

@MainActor
private final class StubDeviceAuthentication: DeviceAuthenticating {
    var methodName = "Face ID"
    var symbol = "faceid"
    var succeeds = true
    var failure: Error?
    var delays = false
    var requests = 0
    var cancellations = 0
    var started: (() -> Void)?
    var continuation: CheckedContinuation<Bool, Error>?
    func authenticate(reason: String) async throws -> Bool {
        requests += 1
        if let failure { throw failure }
        if delays {
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                started?()
            }
        }
        return succeeds
    }
    func cancel() { cancellations += 1 }
}

@MainActor
final class AppLockTests: XCTestCase {
    private func fixture(enabled: Bool = false) throws -> (AppLockService, StubDeviceAuthentication, UserDefaults, String) {
        let name = "LedgerTests.Lock.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.set(enabled, forKey: AppLockService.enabledKey)
        let authentication = StubDeviceAuthentication()
        return (AppLockService(defaults: defaults, authentication: authentication), authentication, defaults, name)
    }

    func testActivationRequiresSuccessfulAuthenticationAndPersists() async throws {
        let (lock, auth, defaults, name) = try fixture()
        defer { defaults.removePersistentDomain(forName: name) }
        auth.succeeds = false
        let rejected = await lock.setEnabled(true)
        XCTAssertFalse(rejected); XCTAssertFalse(lock.isEnabled)
        XCTAssertFalse(defaults.bool(forKey: AppLockService.enabledKey))
        auth.succeeds = true
        let activated = await lock.setEnabled(true)
        XCTAssertTrue(activated); XCTAssertFalse(lock.isLocked)
        XCTAssertTrue(AppLockService(defaults: defaults, authentication: auth).isLocked)
    }

    func testDisablingRequiresAuthenticationAndCancellationKeepsLock() async throws {
        let (lock, auth, defaults, name) = try fixture(enabled: true)
        defer { defaults.removePersistentDomain(forName: name) }
        auth.succeeds = false
        let disabled = await lock.setEnabled(false)
        XCTAssertFalse(disabled); XCTAssertTrue(lock.isEnabled); XCTAssertTrue(lock.isLocked)
        XCTAssertTrue(defaults.bool(forKey: AppLockService.enabledKey))
        auth.succeeds = true
        let accepted = await lock.setEnabled(false)
        XCTAssertTrue(accepted); XCTAssertFalse(lock.isEnabled); XCTAssertFalse(lock.isLocked)
    }

    func testFailureDoesNotLoopTheSystemPromptAndBackgroundLocksAgain() async throws {
        let (lock, auth, defaults, name) = try fixture(enabled: true)
        defer { defaults.removePersistentDomain(forName: name) }
        auth.succeeds = false
        let first = await lock.unlock(automatically: true)
        let second = await lock.unlock(automatically: true)
        XCTAssertFalse(first); XCTAssertFalse(second); XCTAssertEqual(auth.requests, 1)
        auth.succeeds = true
        let manualRetry = await lock.unlock()
        XCTAssertTrue(manualRetry); XCTAssertNoThrow(try lock.requireUnlockedAccess())
        lock.lock()
        XCTAssertTrue(lock.isLocked); XCTAssertThrowsError(try lock.requireUnlockedAccess())
        let afterReturn = await lock.unlock(automatically: true)
        XCTAssertTrue(afterReturn); XCTAssertEqual(auth.requests, 3)
    }

    func testAnOldSuccessCannotUnlockAfterEnteringBackground() async throws {
        let (lock, auth, defaults, name) = try fixture(enabled: true)
        defer { defaults.removePersistentDomain(forName: name) }
        let started = expectation(description: "System authentication started")
        auth.delays = true; auth.started = { started.fulfill() }
        let operation = Task { await lock.unlock() }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(lock.isAuthenticating)
        lock.lock()
        auth.continuation?.resume(returning: true); auth.continuation = nil
        let result = await operation.value
        XCTAssertFalse(result); XCTAssertTrue(lock.isLocked); XCTAssertFalse(lock.isAuthenticating)
    }

    func testDataResetDisablesProtectionAndInvalidatesTheSession() throws {
        let (lock, _, defaults, name) = try fixture(enabled: true)
        defer { defaults.removePersistentDomain(forName: name) }
        lock.resetAfterDataErase()
        XCTAssertFalse(lock.isEnabled); XCTAssertFalse(lock.isLocked)
        XCTAssertFalse(defaults.bool(forKey: AppLockService.enabledKey))
        XCTAssertNoThrow(try lock.requireUnlockedAccess())
    }

    func testSystemCancellationKeepsAccessClosedWithoutAnErrorOrPromptLoop() async throws {
        let (lock, auth, defaults, name) = try fixture(enabled: true)
        defer { defaults.removePersistentDomain(forName: name) }
        auth.failure = NSError(domain: LAError.errorDomain, code: LAError.Code.userCancel.rawValue)
        let cancelled = await lock.unlock(automatically: true)
        let retry = await lock.unlock(automatically: true)
        XCTAssertFalse(cancelled); XCTAssertFalse(retry)
        XCTAssertTrue(lock.isLocked); XCTAssertNil(lock.errorMessage)
        XCTAssertEqual(auth.requests, 1)
    }
}
