import SwiftUI
import UIKit

@MainActor struct LedgerSecurityHost<Content: View>: View {
    @Environment(\.scenePhase) private var phase
    @AppStorage("ledger.appearance") private var appearance = "system"
    @AppStorage("ledger.accent") private var accent = "teal"
    @State private var lock = AppLockService.shared
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        let concealed = lock.shouldConcealContent(isActive: phase == .active)
        content
            .opacity(lock.isLocked ? 0 : 1)
            .disabled(lock.isLocked)
            .accessibilityHidden(concealed)
            .background {
                LedgerPrivacyWindow(covered: concealed,
                                    interactive: phase == .active && lock.isLocked,
                                    appearance: LedgerAppearance(rawValue: appearance) ?? .system,
                                    accent: LedgerAccent(rawValue: accent) ?? .teal)
                    .frame(width: 0, height: 0)
            }
            .task { if phase == .active { await lock.unlock(automatically: true) } }
            .onChange(of: phase) { _, value in
                if value == .background { lock.lock() }
                if value == .active { Task { await lock.unlock(automatically: true) } }
            }
    }
}

/// A separate scene window covers sheets, alerts and the app-switcher snapshot.
/// The original navigation/form state stays mounted underneath it.
@MainActor private struct LedgerPrivacyWindow: UIViewRepresentable {
    let covered: Bool
    let interactive: Bool
    let appearance: LedgerAppearance
    let accent: LedgerAccent
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.onAttach = { [weak coordinator = context.coordinator] scene in coordinator?.attach(scene) }
        return anchor
    }
    func updateUIView(_ uiView: Anchor, context: Context) {
        context.coordinator.update(covered: covered, interactive: interactive, appearance: appearance, accent: accent)
        if let scene = uiView.window?.windowScene { context.coordinator.attach(scene) }
    }
    static func dismantleUIView(_ uiView: Anchor, coordinator: Coordinator) { coordinator.invalidate() }

    final class Anchor: UIView {
        var onAttach: (@MainActor (UIWindowScene?) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); onAttach?(window?.windowScene) }
    }
    @MainActor final class Coordinator {
        private var window: UIWindow?
        private var inactiveObserver: NSObjectProtocol?
        private var activeObserver: NSObjectProtocol?
        private var backgroundObserver: NSObjectProtocol?
        private var covered = false
        private var interactive = false
        private var appearance = LedgerAppearance.system
        private var accent = LedgerAccent.teal
        func attach(_ scene: UIWindowScene?) {
            guard let scene else { return }
            if inactiveObserver == nil {
                // Cover synchronously before UIKit captures the app-switcher image.
                inactiveObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.coverForSnapshot() }
                }
                backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        AppLockService.shared.lock()
                        self?.coverForSnapshot()
                    }
                }
                activeObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.showCurrentSession() }
                }
            }
            if window?.windowScene !== scene {
                close()
                let shield = UIWindow(windowScene: scene)
                shield.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
                shield.backgroundColor = .systemBackground
                shield.accessibilityViewIsModal = true
                window = shield
            }
            render()
        }
        func update(covered: Bool, interactive: Bool, appearance: LedgerAppearance, accent: LedgerAccent) {
            let wasCovered = self.covered
            self.covered = covered; self.interactive = interactive; self.appearance = appearance; self.accent = accent
            if covered && !wasCovered {
                DispatchQueue.main.async { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
            render()
        }
        private func coverForSnapshot() {
            covered = AppLockService.shared.shouldConcealContent(isActive: false)
            interactive = false; render()
        }
        private func showCurrentSession() {
            covered = AppLockService.shared.shouldConcealContent(isActive: true); interactive = covered
            render()
        }
        private func render() {
            guard let window else { return }
            let cover = LedgerLockScreen(interactive: interactive, appearance: appearance, accent: accent)
            if let host = window.rootViewController as? UIHostingController<LedgerLockScreen> { host.rootView = cover }
            else { window.rootViewController = UIHostingController(rootView: cover) }
            window.isUserInteractionEnabled = interactive
            window.isHidden = !covered || !AppLockService.shared.isEnabled
        }
        func close() { window?.isHidden = true; window?.rootViewController = nil; window = nil }
        func invalidate() {
            for observer in [inactiveObserver, activeObserver, backgroundObserver].compactMap({ $0 }) {
                NotificationCenter.default.removeObserver(observer)
            }
            inactiveObserver = nil; activeObserver = nil; backgroundObserver = nil
            close()
        }
    }
}

@MainActor private struct LedgerLockScreen: View {
    let interactive: Bool
    let appearance: LedgerAppearance
    let accent: LedgerAccent
    @State private var lock = AppLockService.shared
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.shield.fill").font(.system(size: 56, weight: .regular)).foregroundStyle(accent.color)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Ledger").font(.largeTitle.bold())
                Text(interactive ? "Suas finanças, protegidas." : "Finanças pessoais").font(.subheadline).foregroundStyle(.secondary)
            }
            if interactive {
                Button { Task { await lock.unlock() } } label: {
                    Label(lock.isAuthenticating ? "Autenticando…" : "Desbloquear com \(lock.methodName)", systemImage: lock.symbol)
                        .font(.headline).padding(.vertical, 8).frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).disabled(lock.isAuthenticating)
                Text("Você também pode usar o código do aparelho na autenticação do iOS.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let message = lock.errorMessage { Text(message).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center) }
            }
            Spacer()
        }
        .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .tint(accent.color).preferredColorScheme(appearance.colorScheme)
    }
}
