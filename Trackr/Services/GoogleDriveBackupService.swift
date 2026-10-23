import Foundation
import Observation
import SwiftData
import UIKit
import GoogleSignIn
import BackgroundTasks

@MainActor @Observable
final class GoogleDriveBackupService {
    static let shared = GoogleDriveBackupService()
    static let backgroundID = "com.mikhael.trackr.backup.refresh"
    private(set) var email: String?
    private(set) var isBusy = false
    private(set) var files: [DriveBackupFile] = []
    var error: String?
    var message: String?
    private var revision = 0
    private var changedWhileBusy = false
    private var pending: Task<Void, Never>?
    private var initializing: Task<Void, Never>?
    private let api = GoogleDriveAPI()

    static var clientID: String {
        Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String ?? ""
    }
    static var isConfigured: Bool {
        guard clientID.hasSuffix(".apps.googleusercontent.com"), !clientID.contains("YOUR_") else { return false }
        let expected = clientID.split(separator: ".").reversed().joined(separator: ".")
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return types.contains { ($0["CFBundleURLSchemes"] as? [String] ?? []).contains(expected) }
    }
    var isConnected: Bool { email != nil }
    var lastBackup: Date? {
        let time = UserDefaults.standard.double(forKey: "trackr.drive.lastBackup")
        return time > 0 ? Date(timeIntervalSince1970: time) : nil
    }
    var synchronization: Bool {
        get { UserDefaults.standard.object(forKey: "trackr.drive.syncEnabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "trackr.drive.syncEnabled")
            scheduleBackground()
            if newValue { Task { await foreground() } }
        }
    }
    var lastSync: Date? {
        let time = UserDefaults.standard.double(forKey: "trackr.drive.lastSync")
        return time > 0 ? Date(timeIntervalSince1970: time) : nil
    }
    private var accountKey: String? {
        UserDefaults.standard.string(forKey: "trackr.drive.user").map { Self.clientID + ":" + $0 }
    }
    var automatic: Bool {
        get { UserDefaults.standard.bool(forKey: "trackr.drive.automatic") }
        set {
            UserDefaults.standard.set(newValue, forKey: "trackr.drive.automatic")
            if newValue { scheduleBackground(); financialDataChanged() }
            else { scheduleBackground() }
        }
    }

    func initialize() async {
        if let initializing { await initializing.value; return }
        guard Self.isConfigured, email == nil, !isBusy, GIDSignIn.sharedInstance.hasPreviousSignIn() else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: Self.clientID)
        let currentRevision = revision
        let task = Task { @MainActor in
            do {
                let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
                guard currentRevision == revision else { GIDSignIn.sharedInstance.signOut(); return }
                adopt(user)
                scheduleBackground()
            } catch { /* Manual connection shows authentication errors; launch remains usable offline. */ }
        }
        initializing = task
        await task.value
        initializing = nil
    }

    func connect() async {
        guard !isBusy, Self.isConfigured else { return }
        guard let presenter = Self.presenter() else { error = "Não foi possível abrir o login. Tente novamente."; return }
        isBusy = true; error = nil; message = nil
        defer { finishOperation() }
        let currentRevision = revision
        do {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: Self.clientID)
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: nil,
                                                                  additionalScopes: [DriveBackupPolicy.scope])
            guard currentRevision == revision else { GIDSignIn.sharedInstance.signOut(); return }
            guard result.user.grantedScopes?.contains(DriveBackupPolicy.scope) == true else {
                throw FinanceError.invalid("Autorize a área privada do Trackr no Google Drive.")
            }
            adopt(result.user)
            message = "Google Drive conectado."
            scheduleBackground()
            isBusy = false
            if synchronization { try await synchronize(context: Persistence.sharedContainer().mainContext) }
        } catch {
            if currentRevision == revision, (error as NSError).code != -5 { self.error = error.localizedDescription }
        }
    }

    private func adopt(_ user: GIDGoogleUser) {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "trackr.drive.user") != user.userID {
            for key in ["trackr.drive.lastBackup", "trackr.drive.fingerprint", "trackr.drive.automatic", "trackr.drive.lastSync", "trackr.drive.syncEnabled"] { defaults.removeObject(forKey: key) }
            files = []
        }
        defaults.set(user.userID, forKey: "trackr.drive.user")
        email = user.profile?.email ?? "Conta Google"
    }

    private func token() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser, user.grantedScopes?.contains(DriveBackupPolicy.scope) == true else {
            throw FinanceError.invalid("Conecte o Google Drive e autorize o backup.")
        }
        return try await user.refreshTokensIfNeeded().accessToken.tokenString
    }

    func backup(context: ModelContext, automatically: Bool = false) async {
        guard !isBusy, isConnected, !AppLockService.shared.isLocked else { return }
        isBusy = true; error = nil; message = nil
        defer { finishOperation() }
        let currentRevision = revision
        do {
            let data = try BackupService.encode(BackupService.snapshot(context: context))
            let digest = try DriveBackupPolicy.fingerprint(data)
            if automatically && UserDefaults.standard.string(forKey: "trackr.drive.fingerprint") == digest { return }
            let access = try await token()
            try Task.checkCancellation()
            guard currentRevision == revision, !AppLockService.shared.isLocked else { return }
            let uploaded = try await api.upload(data, token: access)
            guard currentRevision == revision else { return }
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "trackr.drive.lastBackup")
            UserDefaults.standard.set(digest, forKey: "trackr.drive.fingerprint")
            message = "Backup salvo no Google Drive."
            do {
                let versions = try await api.list(token: access)
                // Never prune before the new upload has succeeded and is visible in the list.
                if versions.contains(where: { $0.id == uploaded.id }) {
                    for file in versions.dropFirst(DriveBackupPolicy.retainedVersions) {
                        try Task.checkCancellation()
                        guard currentRevision == revision else { return }
                        try await api.delete(file, token: access)
                    }
                }
                guard currentRevision == revision else { return }
                files = Array(versions.prefix(DriveBackupPolicy.retainedVersions))
            } catch { message = "Backup salvo. Não foi possível atualizar as versões antigas." }
        } catch {
            if currentRevision == revision, !(error is CancellationError) { self.error = error.localizedDescription }
        }
    }

    func listBackups() async {
        guard !isBusy, isConnected, !AppLockService.shared.isLocked else { return }
        isBusy = true; error = nil
        defer { finishOperation() }
        let currentRevision = revision
        do {
            let access = try await token()
            let result = try await api.list(token: access)
            guard currentRevision == revision else { return }
            files = result
        } catch { if currentRevision == revision { self.error = error.localizedDescription } }
    }

    func download(_ file: DriveBackupFile) async -> TrackrBackup? {
        guard !isBusy, isConnected, !AppLockService.shared.isLocked else { return nil }
        isBusy = true; error = nil
        defer { finishOperation() }
        let currentRevision = revision
        do {
            let access = try await token()
            let data = try await api.download(file, token: access)
            guard currentRevision == revision, !AppLockService.shared.isLocked else { return nil }
            return try BackupService.decode(data)
        } catch { if currentRevision == revision { self.error = error.localizedDescription }; return nil }
    }

    /// Local disconnect keeps cloud backups available for a later connection.
    func disconnect() {
        revision += 1; pending?.cancel(); initializing?.cancel(); changedWhileBusy = false
        if Self.isConfigured || isConnected { GIDSignIn.sharedInstance.signOut() }
        email = nil; files = []; message = nil; error = nil
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("trackr.drive.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundID)
    }

    /// Download all device documents before capturing local changes; the
    /// snapshot after network awaits includes edits made while the request ran.
    func synchronize(context: ModelContext) async throws {
        guard !isBusy, isConnected, synchronization, !AppLockService.shared.isLocked,
              let account = accountKey else { return }
        isBusy = true; error = nil
        defer { finishOperation() }
        let currentRevision = revision
        var state = try DriveSyncCache.load(account: account)
        let access = try await token()
        let remoteFiles = try await api.list(token: access, synchronization: true)
        guard remoteFiles.count <= 256 else { throw FinanceError.invalid("Muitos aparelhos registrados no Drive. Exporte uma cópia local e revise a conta.") }
        var ownFile: DriveBackupFile?
        var ownDocument: DriveSyncDocument?
        for file in remoteFiles {
            let data = try await api.download(file, token: access)
            let remote = try JSONDecoder().decode(DriveSyncDocument.self, from: data)
            if remote.owner == state.document.owner, ownFile == nil { ownFile = file; ownDocument = remote }
            try state.document.merge(remote)
        }
        // Upgrade the backup-only version without requiring a manual restore.
        if remoteFiles.isEmpty, state.baseline == nil {
            if let latest = try await api.list(token: access).first {
                let backup = try BackupService.decode(try await api.download(latest, token: access))
                try state.document.capture(try DriveSyncState.index(backup), baseline: nil)
            }
        }
        try Task.checkCancellation()
        guard currentRevision == revision, synchronization, !AppLockService.shared.isLocked else { return }
        let snapshot = try BackupService.snapshot(context: context)
        let current = try DriveSyncState.index(snapshot)
        let hasFinancialData = snapshot.count > snapshot.categories.count
        try state.document.capture(current, baseline: state.baseline, preferLocal: remoteFiles.isEmpty && hasFinancialData)
        let merged = try state.materialize()
        let mergedIndex = try DriveSyncState.index(merged)
        // Save pending revisions before applying or uploading. A failed upload
        // will be retried without forgetting deletions or local modifications.
        state.baseline = current
        try DriveSyncCache.save(state, account: account)
        if current != mergedIndex { try DriveSyncPersistence.apply(merged, context: context) }
        state.baseline = mergedIndex
        try DriveSyncCache.save(state, account: account)
        if ownDocument?.records != state.document.records {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            _ = try await api.upload(encoder.encode(state.document), token: access, device: state.document.owner, updating: ownFile?.id)
        }
        try Task.checkCancellation()
        guard currentRevision == revision else { return }
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "trackr.drive.lastSync")
        message = "Dados sincronizados."
        scheduleBackground()
    }

    func synchronizeNow(context: ModelContext) async {
        do { try await synchronize(context: context) }
        catch { if !(error is CancellationError) { self.error = error.localizedDescription } }
    }

    /// Local erase starts a fresh sync identity on a later connection. It must
    /// never publish the erased database as deletions to the other devices.
    func clearSynchronizationCache() throws {
        try DriveSyncCache.clearAll()
    }

    func financialDataChanged() {
        guard (automatic || synchronization), isConnected else { return }
        if isBusy { changedWhileBusy = true; return }
        pending?.cancel()
        pending = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(5)); try Task.checkCancellation() }
            catch { return }
            guard UIApplication.shared.applicationState == .active, !AppLockService.shared.isLocked else { return }
            do {
                let context = try Persistence.sharedContainer().mainContext
                if synchronization { try await synchronize(context: context) }
                if automatic { await backup(context: context, automatically: true) }
            } catch { if !(error is CancellationError) { self.error = error.localizedDescription } }
        }
    }

    private func finishOperation() {
        isBusy = false
        if changedWhileBusy { changedWhileBusy = false; financialDataChanged() }
    }

    func foreground() async {
        await initialize()
        if synchronization, isConnected {
            do { try await synchronize(context: Persistence.sharedContainer().mainContext) }
            catch { if !(error is CancellationError) { self.error = error.localizedDescription } }
        }
        if automatic { financialDataChanged() }
        scheduleBackground()
    }

    static func registerBackground() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundID, using: nil) { task in
            let work = Task { @MainActor in
                let service = Self.shared
                service.scheduleBackground()
                // Protected apps only upload while the user has an unlocked foreground session.
                guard (service.automatic || service.synchronization), !AppLockService.protectionEnabled else { task.setTaskCompleted(success: true); return }
                await service.initialize()
                do {
                    let context = try Persistence.sharedContainer().mainContext
                    if service.synchronization { try await service.synchronize(context: context) }
                    if service.automatic { await service.backup(context: context, automatically: true) }
                    task.setTaskCompleted(success: !Task.isCancelled && service.error == nil)
                } catch { task.setTaskCompleted(success: false) }
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    private func scheduleBackground() {
        guard Self.isConfigured else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundID)
        guard isConnected, automatic || synchronization else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func presenter() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var controller = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
}
