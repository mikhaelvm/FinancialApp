import Foundation
import LocalAuthentication
import Observation

@MainActor
protocol DeviceAuthenticating: AnyObject {
    var methodName: String { get }
    var symbol: String { get }
    func authenticate(reason: String) async throws -> Bool
    func cancel()
}

@MainActor
final class SystemDeviceAuthentication: DeviceAuthenticating {
    private var current: LAContext?
    private var biometry: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }
    var methodName: String {
        switch biometry {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "autenticação do aparelho"
        }
    }
    var symbol: String { biometry == .faceID ? "faceid" : (biometry == .touchID ? "touchid" : "lock.shield") }
    func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"
        context.touchIDAuthenticationAllowableReuseDuration = 0
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw FinanceError.invalid("Configure um código de desbloqueio e, se disponível, Face ID ou Touch ID nos Ajustes do iPhone.")
        }
        current = context
        defer { if current === context { current = nil } }
        return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }
    func cancel() { current?.invalidate(); current = nil }
}

/// Access protection, not a separate encryption layer for the SwiftData store.
@MainActor @Observable
final class AppLockService {
    static let shared = AppLockService()
    static let enabledKey = "trackr.lock.enabled"
    private let defaults: UserDefaults
    private let authentication: any DeviceAuthenticating
    private var revision = 0
    private var attemptedAutomaticUnlock = false
    private(set) var isEnabled: Bool
    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    private(set) var errorMessage: String?
    var methodName: String { authentication.methodName }
    var symbol: String { authentication.symbol }
    static var protectionEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    init(defaults: UserDefaults = .standard, authentication: (any DeviceAuthenticating)? = nil) {
        self.defaults = defaults
        self.authentication = authentication ?? SystemDeviceAuthentication()
        let enabled = defaults.bool(forKey: Self.enabledKey)
        isEnabled = enabled
        isLocked = enabled
    }

    @discardableResult func setEnabled(_ enabled: Bool) async -> Bool {
        guard enabled != isEnabled else { return true }
        let reason = enabled ? "Ativar o bloqueio de acesso ao Trackr." : "Desativar o bloqueio de acesso ao Trackr."
        guard await authenticate(reason: reason) else { return false }
        defaults.set(enabled, forKey: Self.enabledKey)
        isEnabled = enabled; isLocked = false; attemptedAutomaticUnlock = true
        FinanceEvents.saved()
        return true
    }

    func lock() {
        revision += 1
        authentication.cancel()
        isAuthenticating = false
        isLocked = isEnabled
        attemptedAutomaticUnlock = false
        errorMessage = nil
    }

    @discardableResult func unlock(automatically: Bool = false) async -> Bool {
        guard isEnabled && isLocked else { return true }
        if automatically && attemptedAutomaticUnlock { return false }
        attemptedAutomaticUnlock = true
        guard await authenticate(reason: "Desbloquear suas finanças no Trackr.") else { return false }
        isLocked = false
        return true
    }

    func requireUnlockedAccess() throws {
        if isEnabled && isLocked { throw FinanceError.invalid("Abra o Trackr e desbloqueie o acesso antes de usar esta ação ou consultar seus dados.") }
    }

    func shouldConcealContent(isActive: Bool) -> Bool {
        isEnabled && (isLocked || !isActive)
    }

    func resetAfterDataErase() {
        revision += 1; authentication.cancel(); isAuthenticating = false
        defaults.removeObject(forKey: Self.enabledKey)
        isEnabled = false; isLocked = false; errorMessage = nil; attemptedAutomaticUnlock = false
    }

    private func authenticate(reason: String) async -> Bool {
        guard !isAuthenticating else { return false }
        let request = revision
        isAuthenticating = true; errorMessage = nil
        defer { if request == revision { isAuthenticating = false } }
        do {
            let success = try await authentication.authenticate(reason: reason)
            guard request == revision else { return false }
            if !success { errorMessage = "A autenticação não foi concluída. Tente novamente." }
            return success
        } catch {
            guard request == revision else { return false }
            if let issue = error as? LAError, [.userCancel, .systemCancel, .appCancel].contains(issue.code) {
                errorMessage = nil
            } else if let issue = error as? FinanceError { errorMessage = issue.localizedDescription }
            else { errorMessage = "Não foi possível autenticar. Tente novamente ou use o código do aparelho." }
            return false
        }
    }
}
