import AppKit
import AVFoundation

extension AppController {
    // MARK: Speech (text-to-speech container)

    // Unlike checkHealth, runs during a session too: it only reads the speech container's state.
    func checkSpeech() {
        let task = session.dataTask(with: URLRequest(url: speechURL.appendingPathComponent("health"), timeoutInterval: healthTimeout))
        task.delegate = ReplyCollector(limit: maxSpeechHealthBytes) { [weak self] reply in
            var ok = false
            if case .body(200, _) = reply { ok = true }
            DispatchQueue.main.async { self?.setSpeechUp(ok) }
        }
        task.resume()
    }

    // Updated here rather than in refreshUI, whose guard skips unchanged icon text.
    func setSpeechUp(_ up: Bool) {
        let was = speechUp
        speechUp = up
        speechLine?.title = speechStatusText(up)
        applySpeechEnabled()
        if up, was != true { fetchVoices() }
    }

    func applySpeechEnabled() {
        let enabled = speechItemsEnabled(up: speechUp, hasVoices: !voices.isEmpty)
        voiceItem?.isEnabled = enabled.voice
        speedItem?.isEnabled = enabled.speed
        testItem?.isEnabled = enabled.test
    }

    // A failed fetch keeps the last list.
    func fetchVoices() {
        let task = session.dataTask(with: URLRequest(url: speechURL.appendingPathComponent("voices"), timeoutInterval: healthTimeout))
        task.delegate = ReplyCollector(limit: maxVoicesBytes) { [weak self] reply in
            guard case .body(200, let data) = reply else { return }
            let list = parseVoices(data)
            DispatchQueue.main.async {
                guard let self = self, !list.isEmpty, list != self.voices else { return }
                self.voices = list
                if let menu = self.voiceItem?.submenu { self.fillVoices(menu, conf: self.speechConf.read()) }
                self.applySpeechEnabled()
            }
        }
        task.resume()
    }

    // An explicit request, so it plays even when speech is muted; never while the microphone is open.
    func speakTest(voice: String, speed: String) {
        stopTestVoice()
        guard testMayStart(uiState), let body = speakBody(text: testSentence, voice: voice, speed: speed) else { return }
        let id = testGeneration
        var request = URLRequest(url: speechURL.appendingPathComponent("speak"), timeoutInterval: speakTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let task = session.dataTask(with: request)
        task.delegate = ReplyCollector(limit: maxSpeakBytes) { [weak self] reply in
            DispatchQueue.main.async {
                guard let self = self, id == self.testGeneration else { return }
                self.testTask = nil
                self.spoke(reply)
            }
        }
        testTask = task
        task.resume()
    }

    // Failure is silent; only an answer or a refused connection says anything about the container.
    func spoke(_ reply: CollectedReply) {
        switch reply {
        case .body(let status, let data):
            setSpeechUp(true)
            guard testMayPlay(status: status, state: uiState), looksLikeWAV(data),
                  let player = try? AVAudioPlayer(data: data), player.duration <= maxTestSeconds else { return }
            testPlayer = player
            player.play()
        case .transport(let error):
            if transportResult(error) == .unreachable { setSpeechUp(false) }
        case .tooLarge: break
        }
    }

    // Also drops a test reply still on its way; the generation check keeps a cancelled one from judging the container.
    func stopTestVoice() {
        testGeneration += 1
        testTask?.cancel()
        testTask = nil
        testPlayer?.stop()
        testPlayer = nil
    }

    @objc func testVoice(_ sender: NSMenuItem) {
        let conf = speechConf.read()
        speakTest(voice: conf.voice, speed: conf.speed)
    }

    @objc func setVoice(_ sender: NSMenuItem) {
        guard let voice = sender.representedObject as? String, isVoiceID(voice) else { return }
        speechConf.write(voice: voice)
        speakTest(voice: voice, speed: speechConf.read().speed)
    }

    @objc func setSpeed(_ sender: NSMenuItem) {
        guard let speed = sender.representedObject as? String, isSpeedText(speed) else { return }
        speechConf.write(speed: speed)
        speakTest(voice: speechConf.read().voice, speed: speed)
    }

    @objc func toggleManualMute(_ sender: NSMenuItem) {
        let on = !mute.isManual
        mute.setManual(on)
        if recordingMuteReturns(turningOn: on, state: uiState,
                                muteWhileRecording: defaults.bool(forKey: DefaultsKey.muteKokoro.rawValue)) { mute.engage() }
    }
}
