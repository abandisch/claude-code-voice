// Pardon's entry point: the only file with top-level statements; everything else is in PardonKit.
import AppKit
import PardonKit

// MARK: - Entry

if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? bundleID)
    .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
    exit(0)
}
// pkill and Ctrl-C must still reach applicationWillTerminate, which releases the mute flag.
let signalSources: [DispatchSourceSignal] = [SIGTERM, SIGINT].map { sig in
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler { NSApp.terminate(nil) }
    source.resume()
    return source
}
let controller = AppController()
NSApplication.shared.delegate = controller
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
