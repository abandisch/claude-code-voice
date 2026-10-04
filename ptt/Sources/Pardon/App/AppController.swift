// Pardon: hold Option, speak, release; the transcript from the local STT container
// (127.0.0.1:8881) is pasted into the focused window. Build with ptt/build.sh.
import AppKit
import ApplicationServices
import AVFoundation

// MARK: - App

// Every path that leaves recording or busy ends in endSession() or abortSession().
final class AppController: NSObject, NSApplicationDelegate {
    let defaults = UserDefaults.standard
    let recorder = Recorder()
    let mute = KokoroMute()
    var machine = HotkeyMachine()
    var uiState = UIState.idle
    var serverUp: Bool?
    var lastError: String?
    var lastTranscript: String?
    var targetPID: pid_t?
    var sessionID = 0
    var keyCheck: Timer?
    var tap: CFMachPort?
    var tapSource: CFRunLoopSource?
    var statusItem: NSStatusItem!
    var statusLine: NSMenuItem?
    var shown = ""
    var sounds: [Cue: NSSound] = [:]
    var pet: PetWindow?
    // Cleared by the next start cue, or by its decay.
    var petOutcome = PetOutcome.none
    var outcomeDecay = OutcomeDecay()
    let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.urlCredentialStorage = nil
        // Audio must not be routed through a system proxy.
        c.connectionProxyDictionary = [:]
        c.waitsForConnectivity = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = transcribeTimeout
        c.timeoutIntervalForResource = 150
        return URLSession(configuration: c, delegate: RedirectRefuser(), delegateQueue: nil)
    }()

    var mode: ModeSetting { ModeSetting(rawValue: defaults.string(forKey: DefaultsKey.mode.rawValue) ?? "") ?? .hold }
    var side: SideSetting { SideSetting(rawValue: defaults.string(forKey: DefaultsKey.side.rawValue) ?? "") ?? .right }
    var micAuthorized: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    var optionPhysicallyDown: Bool { CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate) }
    var triggerPhysicallyDown: Bool {
        triggerHeld(machine.trigger, optionDown: optionPhysicallyDown,
                    leftButtonDown: CGEventSource.buttonState(.combinedSessionState, button: .left))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: [DefaultsKey.mode.rawValue: ModeSetting.hold.rawValue,
                                     DefaultsKey.side.rawValue: SideSetting.right.rawValue,
                                     DefaultsKey.autoSubmit.rawValue: false, DefaultsKey.muteKokoro.rawValue: true,
                                     DefaultsKey.showOrb.rawValue: true, DefaultsKey.animateIdle.rawValue: true])
        machine = HotkeyMachine(mode: mode, side: side)
        mute.release()
        for cue in Cue.allCases { sounds[cue] = NSSound(named: cue.rawValue) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        let pet = PetWindow(defaults: defaults, menu: menu)
        pet.onPress = { [weak self] in self?.petPressed() }
        pet.onRelease = { [weak self] in self?.petReleased() }
        pet.onDrag = { [weak self] in
            guard let self = self else { return }
            self.feed(self.machine.pointerCancel())
        }
        pet.isRecording = { [weak self] in self?.machine.isRecording ?? false }
        pet.canCancelRecording = { [weak self] in self?.machine.pointerRecordingCancellable ?? false }
        self.pet = pet
        pet.setShown(defaults.bool(forKey: DefaultsKey.showOrb.rawValue))

        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: recorder.engine,
                                               queue: .main) { [weak self] _ in
            guard let self = self, self.uiState == .listening else { return }
            self.cancelRecording(error: "Audio device changed")
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.abortSession() }
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"),
                                                            object: nil, queue: .main) { [weak self] _ in
            self?.abortSession()
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: recorder.prepare()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if granted { self.recorder.prepare() }
                    self.refreshUI()
                }
            }
        default: break
        }
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(prompt)

        let permissionTimer = Timer.scheduledTimer(withTimeInterval: permissionInterval, repeats: true) { [weak self] _ in
            self?.checkTap()
        }
        permissionTimer.tolerance = 0.5
        let healthTimer = Timer.scheduledTimer(withTimeInterval: healthInterval, repeats: true) { [weak self] _ in
            self?.checkHealth()
        }
        healthTimer.tolerance = 2
        checkTap()
        checkHealth()
        refreshUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        mute.release()
    }
}
