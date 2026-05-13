import Foundation
import AppKit

/// Suppresses the floating Mac Xpra.app window that cua's container auto-spawns
/// for each app on the sandbox X display (`xpra seamless :100`).
///
/// Mechanism: `pkill -x Xpra` quietly kills the Mac-side Xpra.app if it's
/// running. Diakonos's Browser pane shows the same Chromium via its own
/// screenshot stream; the Mac Xpra window would be a duplicate.
///
/// **Why it runs on a timer:** Xpra.app does not launch synchronously at
/// Diakonos start — it's spawned by Docker / cuabot lazily when the sandbox
/// connects. So a single pkill at app launch races. We poll every ~3 s
/// for the first 60 s, killing Xpra each time it reappears.
///
/// **Caveat:** this kills any pre-existing Xpra session the user had open for
/// non-Diakonos reasons. v1.4 could check Xpra's PID provenance before killing.
enum XpraSuppressor {

    private static var monitorTask: Task<Void, Never>?

    static func suppressOnLaunch() {
        kill()
        startMonitor()
    }

    /// Reset the monitor — used after the user clicks "Open in floating
    /// window" so Xpra is given time to reappear before we kill it again.
    static func relaunch() {
        // Stop the suppressor briefly, open Xpra, leave it visible for 30 s.
        monitorTask?.cancel()
        monitorTask = nil

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "Xpra"]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run()

        // Resume suppression after a generous grace window.
        Task.detached {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            kill()
            startMonitor()
        }
    }

    nonisolated private static func kill() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-x", "Xpra"]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
    }

    private static func startMonitor() {
        monitorTask?.cancel()
        monitorTask = Task.detached {
            // Poll for the first 60 s after launch; that's the window where
            // cuabot's container connect typically triggers the Mac Xpra app.
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if Task.isCancelled { return }
                kill()
            }
        }
    }
}
