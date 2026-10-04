import Foundation

// MARK: - Pure pieces (exercised by --self-test)

enum SideSetting: String, CaseIterable { case right, left, either }
enum ModeSetting: String { case hold, tap }
enum HotkeyAction: Equatable { case none, startRecording, stopAndSend, cancel }

struct HotkeyOutput: Equatable {
    var action: HotkeyAction = .none
    var deadline: TimeInterval? = nil
}

struct HotkeyMachine {
    static let armDelay: TimeInterval = 0.25
    static let tapMax: TimeInterval = 0.4
    // The server's limit is 120 s.
    static let maxSeconds: TimeInterval = 118

    enum Phase: Equatable { case idle, armed(TimeInterval), recording(TimeInterval), busy }
    // The orb is the pointer trigger; it ignores the side setting.
    enum Trigger { case key, pointer }

    var mode: ModeSetting
    var side: SideSetting
    private(set) var phase: Phase = .idle
    // Owner of the current or most recent session; survives finished() so the shell can check its physical state.
    private(set) var trigger = Trigger.key
    private var leftDown = false
    private var rightDown = false
    private var tapStart: TimeInterval?
    private var pointerHeld = false
    private var pointerTapStart: TimeInterval?
    // The session was armed by the press still held; pointerHeld is true for any held press, a lost-release one too.
    private var pressArmed = false

    init(mode: ModeSetting = .hold, side: SideSetting = .right) {
        self.mode = mode
        self.side = side
    }

    private func matches(_ key: OptionKey) -> Bool {
        switch side {
        case .either: return true
        case .left: return key == .left
        case .right: return key == .right
        }
    }

    private var matchingHeld: Bool {
        (leftDown && matches(.left)) || (rightDown && matches(.right))
    }

    private mutating func setHeld(_ key: OptionKey, _ down: Bool) {
        if key == .left { leftDown = down } else { rightDown = down }
    }

    private func owns(_ source: Trigger) -> Bool {
        phase == .idle || trigger == source
    }

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    // Armed or recording from the orb: a hidden orb could not end it.
    var pointerSessionLive: Bool {
        switch phase {
        case .armed, .recording: return trigger == .pointer
        default: return false
        }
    }

    // A hold recording armed by the orb press still held: a drag may cancel it.
    var pointerRecordingCancellable: Bool {
        mode == .hold && isRecording && trigger == .pointer && pressArmed
    }

    mutating func optionDown(_ key: OptionKey, bare: Bool, at t: TimeInterval) -> HotkeyOutput {
        guard matches(key) else { return HotkeyOutput() }
        let alreadyHeld = matchingHeld
        setHeld(key, true)
        guard !alreadyHeld, phase != .busy, owns(.key) else { return HotkeyOutput() }
        guard bare else { tapStart = nil; return HotkeyOutput() }
        switch mode {
        case .hold:
            guard phase == .idle else { return HotkeyOutput() }
            trigger = .key
            phase = .armed(t)
            return HotkeyOutput(deadline: t + Self.armDelay)
        case .tap:
            tapStart = t
            return HotkeyOutput()
        }
    }

    mutating func optionUp(_ key: OptionKey, at t: TimeInterval) -> HotkeyOutput {
        guard matches(key) else { return HotkeyOutput() }
        setHeld(key, false)
        guard !matchingHeld, phase != .busy, owns(.key) else { return HotkeyOutput() }
        switch mode {
        case .hold:
            switch phase {
            case .armed: phase = .idle; return HotkeyOutput()
            case .recording: phase = .busy; return HotkeyOutput(action: .stopAndSend)
            default: return HotkeyOutput()
            }
        case .tap:
            defer { tapStart = nil }
            guard let start = tapStart, t - start <= Self.tapMax else { return HotkeyOutput() }
            switch phase {
            case .idle:
                trigger = .key
                phase = .recording(t)
                return HotkeyOutput(action: .startRecording, deadline: t + Self.maxSeconds)
            case .recording:
                phase = .busy
                return HotkeyOutput(action: .stopAndSend)
            default: return HotkeyOutput()
            }
        }
    }

    // A press while still held means the last release was lost: treat it as a fresh press.
    mutating func pointerDown(at t: TimeInterval) -> HotkeyOutput {
        pointerHeld = true
        pressArmed = false
        guard phase != .busy, owns(.pointer) else { return HotkeyOutput() }
        switch mode {
        case .hold:
            guard phase == .idle else { return HotkeyOutput() }
            trigger = .pointer
            phase = .armed(t)
            pressArmed = true
            return HotkeyOutput(deadline: t + Self.armDelay)
        case .tap:
            pointerTapStart = t
            return HotkeyOutput()
        }
    }

    mutating func pointerUp(at t: TimeInterval) -> HotkeyOutput {
        guard pointerHeld else { return HotkeyOutput() }
        pointerHeld = false
        pressArmed = false
        guard phase != .busy, owns(.pointer) else { return HotkeyOutput() }
        switch mode {
        case .hold:
            switch phase {
            case .armed: phase = .idle; return HotkeyOutput()
            case .recording: phase = .busy; return HotkeyOutput(action: .stopAndSend)
            default: return HotkeyOutput()
            }
        case .tap:
            defer { pointerTapStart = nil }
            guard let start = pointerTapStart, t - start <= Self.tapMax else { return HotkeyOutput() }
            switch phase {
            case .idle:
                trigger = .pointer
                phase = .recording(t)
                return HotkeyOutput(action: .startRecording, deadline: t + Self.maxSeconds)
            case .recording:
                phase = .busy
                return HotkeyOutput(action: .stopAndSend)
            default: return HotkeyOutput()
            }
        }
    }

    // A press that became a drag: silent; it ends an armed session or a hold recording the press started.
    mutating func pointerCancel() -> HotkeyOutput {
        let cancelsRecording = pointerRecordingCancellable
        pointerHeld = false
        pointerTapStart = nil
        pressArmed = false
        if case .armed = phase, trigger == .pointer { phase = .idle }
        guard cancelsRecording else { return HotkeyOutput() }
        phase = .idle
        return HotkeyOutput(action: .cancel)
    }

    mutating func otherInput(at t: TimeInterval) -> HotkeyOutput {
        tapStart = nil
        guard mode == .hold else { return HotkeyOutput() }
        switch phase {
        case .armed: phase = .idle; return HotkeyOutput()
        case .recording: phase = .idle; return HotkeyOutput(action: .cancel)
        default: return HotkeyOutput()
        }
    }

    mutating func tick(at t: TimeInterval) -> HotkeyOutput {
        switch phase {
        case .armed(let since):
            guard t >= since + Self.armDelay else { return HotkeyOutput(deadline: since + Self.armDelay) }
            phase = .recording(t)
            return HotkeyOutput(action: .startRecording, deadline: t + Self.maxSeconds)
        case .recording(let since):
            guard t >= since + Self.maxSeconds else { return HotkeyOutput(deadline: since + Self.maxSeconds) }
            phase = .busy
            return HotkeyOutput(action: .stopAndSend)
        default:
            return HotkeyOutput()
        }
    }

    // Held flags survive: a missed key-up would swallow the next press, so the shell resyncs
    // them with releaseAll when the session's trigger is not physically down.
    mutating func finished() {
        phase = .idle
        tapStart = nil
        pointerTapStart = nil
    }

    mutating func reset() {
        phase = .idle
        leftDown = false
        rightDown = false
        tapStart = nil
        pointerHeld = false
        pointerTapStart = nil
    }

    mutating func releaseAll(at t: TimeInterval) -> HotkeyOutput {
        leftDown = false
        rightDown = false
        tapStart = nil
        pointerHeld = false
        pointerTapStart = nil
        guard mode == .hold else { return HotkeyOutput() }
        switch phase {
        case .armed: phase = .idle; return HotkeyOutput()
        case .recording: phase = .busy; return HotkeyOutput(action: .stopAndSend)
        default: return HotkeyOutput()
        }
    }
}

func triggerHeld(_ trigger: HotkeyMachine.Trigger, optionDown: Bool, leftButtonDown: Bool) -> Bool {
    trigger == .pointer ? leftButtonDown : optionDown
}
