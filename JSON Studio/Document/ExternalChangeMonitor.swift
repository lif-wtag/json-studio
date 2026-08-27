import AppKit
import Combine
import SwiftUI

/// Watches the document's file for writes by other processes (DC-10).
///
/// **Polling, not a file-system event source, and that is deliberate.** A `DispatchSource` on an
/// open descriptor follows the *inode*, and almost every writer that matters — `git checkout`, and
/// any editor that saves atomically — writes a new file and renames it over the old one. The
/// descriptor then points at an unlinked inode that will never change again, so the watch goes
/// quiet exactly when it is needed. A `stat` every couple of seconds cannot miss that.
///
/// It also checks **the moment the app is reactivated**, which is when this actually happens: the
/// developer switches to a terminal, runs something, and comes back.
@MainActor
final class ExternalChangeMonitor: ObservableObject {

    /// Set when someone else's write is waiting to be accepted or declined. Carries the bytes that
    /// are on disk now, so accepting does not re-read and risk picking up a third version.
    @Published private(set) var pendingChange: Data?

    private var url: URL?
    private var timer: Timer?
    private var activationObserver: (any NSObjectProtocol)?
    /// The bytes the app last read from or wrote to the file.
    private var lastKnown: Data?
    /// The attributes at the last look, so an untouched file costs one `stat` rather than a read.
    private var lastRevision: ExternalChange.Revision?

    /// How often to `stat`. Slow enough to be free, fast enough that the developer has usually not
    /// started typing into a stale document — and reactivation covers the case that matters anyway.
    private static let interval: TimeInterval = 2

    func start(url: URL?, lastKnown: Data?) {
        // Restarting on the same file would otherwise reset an alert the developer is looking at.
        guard url != self.url || self.lastKnown != lastKnown else { return }

        stop()
        self.url = url
        self.lastKnown = lastKnown
        guard let url else { return }
        lastRevision = ExternalChange.Revision.read(url)

        let timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.check() }
        }
        // The default run-loop mode stops firing while a menu is open or a window is being
        // resized, which is precisely when a developer is not looking at the editor.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor [weak self] in self?.check() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    /// Called after the app itself writes, so its own save never raises the alert.
    func recordOwnWrite(_ data: Data) {
        lastKnown = data
        pendingChange = nil
        if let url { lastRevision = ExternalChange.Revision.read(url) }
    }

    /// The developer accepted or declined. Either way the version on disk is now the one we know
    /// about — declining must not make the same alert reappear two seconds later.
    func resolvePendingChange() {
        if let pendingChange { lastKnown = pendingChange }
        pendingChange = nil
    }

    private func check() {
        guard let url else { return }

        // The cheap pre-check. Equal attributes are strong evidence nothing happened; unequal ones
        // are no evidence that anything did, which is why they only trigger a read.
        let revision = ExternalChange.Revision.read(url)
        guard revision != lastRevision else { return }
        lastRevision = revision

        switch ExternalChange.inspect(url: url, lastKnown: lastKnown) {
        case .unchanged, .missing:
            // Missing is not an alert: there is nothing to reload, and the document keeps what it
            // has. `Design/error-copy.md` says so explicitly.
            break
        case .changed(let data):
            // One alert per change: if the file changes again while it is up, the newest content
            // replaces the pending one rather than stacking a second alert.
            pendingChange = data
        }
    }

    deinit {
        timer?.invalidate()
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }
}
