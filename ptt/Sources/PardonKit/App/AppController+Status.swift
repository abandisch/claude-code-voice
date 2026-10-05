import AppKit
import ApplicationServices
import AVFoundation

extension AppController {
    // MARK: Server health

    func checkHealth() {
        guard uiState == .idle else { return }
        let request = URLRequest(url: serverURL.appendingPathComponent("health"), timeoutInterval: healthTimeout)
        session.dataTask(with: request) { [weak self] _, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                self?.serverUp = ok
                self?.refreshUI()
            }
        }.resume()
    }

    // MARK: Cues

    // Also sets the pet's outcome, so this must stay ahead of any early return.
    func play(_ cue: Cue) {
        petOutcome = PetOutcome(cue)
        let generation = outcomeDecay.next()
        if petOutcome != .none {
            DispatchQueue.main.asyncAfter(deadline: .now() + OutcomeDecay.seconds) { [weak self] in
                guard let self = self, self.outcomeDecay.isCurrent(generation) else { return }
                self.petOutcome = .none
                self.updatePet(self.health)
            }
        }
        updatePet(health)
        guard let sound = sounds[cue] else { return }
        sound.stop()
        sound.play()
    }

    // MARK: UI

    var health: Health {
        if !AXIsProcessTrusted() { return .needsAccessibility }
        if tap == nil { return .hotkeyUnavailable }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined: return .micPending
        default: return .micDenied
        }
        return serverUp == false ? .serverDown : .ready
    }

    func statusText(_ health: Health) -> String {
        switch uiState {
        case .listening: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .idle:
            switch health {
            case .ready: return lastError.map { "Ready — last attempt failed: \($0)" } ?? "Ready"
            case .needsAccessibility: return "Grant Accessibility in System Settings"
            case .hotkeyUnavailable: return "Hotkey unavailable — switch Pardon off and on in Accessibility"
            case .micPending: return "Waiting for microphone permission"
            case .micDenied: return "Microphone access denied"
            case .serverDown: return "Transcription server not running — make run-stt"
            }
        }
    }

    func updatePet(_ health: Health) {
        pet?.update(petLook(ui: uiState, health: health, outcome: petOutcome), label: "Pardon: \(statusText(health))")
    }

    func refreshUI() {
        guard let button = statusItem?.button else { return }
        let health = self.health
        updatePet(health)
        let text = statusText(health)
        let symbol: String
        switch uiState {
        case .listening: symbol = "mic.fill"
        case .transcribing: symbol = "ellipsis.circle"
        case .idle: symbol = health == .ready ? "mic" : "mic.slash"
        }
        guard "\(symbol)|\(text)" != shown else { return }
        shown = "\(symbol)|\(text)"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Pardon: \(text)") {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = uiState == .idle ? (health == .ready ? "P" : "P!") : (uiState == .listening ? "P●" : "P…")
        }
        statusLine?.title = text
    }
}
