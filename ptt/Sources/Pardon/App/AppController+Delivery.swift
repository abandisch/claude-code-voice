import AppKit

extension AppController {
    // MARK: Deliver

    func writeTranscript(_ text: String, to pb: NSPasteboard) {
        pb.prepareForNewContents(with: .currentHostOnly)
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        // Clipboard managers that honour this marker skip the transcript.
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        pb.writeObjects([item])
    }

    func deliver(_ text: String) {
        let id = sessionID
        let target = targetPID
        let focusError = "Focus changed; use Copy last transcript"
        func moved() -> Bool { focusMoved(from: target, to: NSWorkspace.shared.frontmostApplication?.processIdentifier) }
        lastTranscript = text
        guard !moved() else { return cancelRecording(error: focusError) }
        let pb = NSPasteboard.general
        let saved: [NSPasteboardItem] = (pb.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        writeTranscript(text, to: pb)
        let ours = pb.changeCount
        let submit = defaults.bool(forKey: DefaultsKey.autoSubmit.rawValue) && wordCount(text) >= 3

        var pasted = false
        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) {
            guard id == self.sessionID else { return }
            guard mayPost(.paste, pasted: pasted, moved: moved()) else {
                self.lastError = focusError
                return self.play(.error)
            }
            self.postKey(currentPasteKeyCode(), flags: .maskCommand)
            pasted = true
            self.lastError = nil
            self.play(.sent)
        }
        if submit {
            DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay + returnDelay) {
                guard id == self.sessionID, mayPost(.submit, pasted: pasted, moved: moved()) else { return }
                self.postKey(returnKeyCode, flags: [])
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay + restoreDelay) {
            if pb.changeCount == ours {
                pb.clearContents()
                if !saved.isEmpty { pb.writeObjects(saved) }
            }
            guard id == self.sessionID else { return }
            self.endSession()
        }
    }

    func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        // Private state: physically held modifiers (the Option key) must not leak into Cmd-V.
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: pardonEventTag)
            event.post(tap: .cghidEventTap)
        }
    }
}
