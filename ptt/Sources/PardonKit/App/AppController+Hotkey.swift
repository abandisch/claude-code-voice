import Foundation

extension AppController {
    // MARK: Hotkey

    // Without the tap a paste could not be posted, so the pet does nothing.
    func petPressed() {
        guard tap != nil else { return }
        feed(machine.pointerDown(at: now()))
    }

    func petReleased() {
        feed(machine.pointerUp(at: now()))
    }

    // Stale ticks are safe only because tick re-checks the phase.
    func feed(_ out: HotkeyOutput) {
        if let deadline = out.deadline {
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - now())) { [weak self] in
                guard let self = self else { return }
                if case .armed = self.machine.phase, !self.triggerPhysicallyDown {
                    return self.feed(self.machine.releaseAll(at: now()))
                }
                self.feed(self.machine.tick(at: now()))
            }
        }
        switch out.action {
        case .none: break
        case .startRecording: startRecording()
        case .stopAndSend: stopAndSend()
        case .cancel: cancelRecording(error: nil)
        }
    }
}
