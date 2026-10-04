import AppKit

extension AppController {
    // MARK: Session

    func startRecording() {
        sessionID += 1
        guard micAuthorized else { return cancelRecording(error: "Microphone could not start") }
        play(.start)
        if defaults.bool(forKey: DefaultsKey.muteKokoro.rawValue) { mute.engage() }
        syncLevelMeter()
        guard recorder.start() else { return cancelRecording(error: "Microphone could not start") }
        uiState = .listening
        if machine.mode == .hold {
            keyCheck = Timer.scheduledTimer(withTimeInterval: keyCheckInterval, repeats: true) { [weak self] _ in
                guard let self = self, case .recording = self.machine.phase, !self.triggerPhysicallyDown else { return }
                self.feed(self.machine.releaseAll(at: now()))
            }
        }
        refreshUI()
    }

    func syncLevelMeter() {
        recorder.onLevel = pet?.isShown == true ? { [weak self] level in self?.pet?.setLevel(level) } : nil
    }

    func stopKeyCheck() {
        keyCheck?.invalidate()
        keyCheck = nil
    }

    func stopAndSend() {
        stopKeyCheck()
        let samples = recorder.stop()
        targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        uiState = .transcribing
        refreshUI()
        guard !samples.isEmpty else { play(.nothingHeard); return endSession() }
        let id = sessionID
        var request = URLRequest(url: serverURL.appendingPathComponent("transcribe"), timeoutInterval: transcribeTimeout)
        request.httpMethod = "POST"
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = wavData(samples: samples, sampleRate: sampleRate)
        let task = session.dataTask(with: request)
        task.delegate = ReplyCollector { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, id == self.sessionID else { return }
                self.received(result)
            }
        }
        task.resume()
    }

    func received(_ result: TranscribeResult) {
        switch result {
        case .text(let text): serverUp = true; deliver(text)
        case .noSpeech: serverUp = true; play(.nothingHeard); endSession()
        case .failed(let reason): serverUp = true; cancelRecording(error: String(sanitise(reason).prefix(80)))
        case .timedOut: cancelRecording(error: "Timed out waiting for the speech server")
        case .unreachable: serverUp = false; cancelRecording(error: "Speech server not reachable")
        }
    }

    func cancelRecording(error: String?) {
        _ = recorder.stop()
        if let error = error {
            lastError = error
            play(.error)
        }
        endSession()
    }

    func endSession() {
        stopKeyCheck()
        mute.release()
        machine.finished()
        if !triggerPhysicallyDown { _ = machine.releaseAll(at: now()) }
        uiState = .idle
        refreshUI()
    }

    func abortSession() {
        sessionID += 1
        stopKeyCheck()
        _ = recorder.stop()
        mute.release()
        machine.reset()
        uiState = .idle
        refreshUI()
    }
}
