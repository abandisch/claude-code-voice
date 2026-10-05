import AppKit
import ServiceManagement

extension AppController: NSMenuDelegate {
    public func menuWillOpen(_ menu: NSMenu) {
        checkHealth()
        checkSpeech()
        // Otherwise setSpeechUp fetches them when speech comes up.
        if speechUp == true { fetchVoices() }
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let health = self.health
        let status = NSMenuItem(title: statusText(health), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        statusLine = status
        let pane = "x-apple.systempreferences:com.apple.preference.security?"
        switch health {
        case .needsAccessibility, .hotkeyUnavailable:
            add(menu, "Open Accessibility Settings…", #selector(openSettings(_:)), on: false, rep: pane + "Privacy_Accessibility")
        case .micDenied:
            add(menu, "Open Microphone Settings…", #selector(openSettings(_:)), on: false, rep: pane + "Privacy_Microphone")
        default: break
        }
        add(menu, "Copy last transcript", #selector(copyLastTranscript(_:)), on: false, rep: "").isEnabled = lastTranscript != nil
        menu.addItem(.separator())
        add(menu, "Hold to talk", #selector(setMode(_:)), on: mode == .hold, rep: ModeSetting.hold.rawValue)
        add(menu, "Tap to toggle", #selector(setMode(_:)), on: mode == .tap, rep: ModeSetting.tap.rawValue)
        menu.addItem(.separator())
        let header = NSMenuItem(title: "Option key", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for s in SideSetting.allCases {
            add(menu, s.rawValue.capitalized, #selector(setSide(_:)), on: side == s, rep: s.rawValue).indentationLevel = 1
        }
        menu.addItem(.separator())
        add(menu, "Auto-submit (Return)", #selector(toggleDefault(_:)),
            on: defaults.bool(forKey: DefaultsKey.autoSubmit.rawValue), rep: DefaultsKey.autoSubmit.rawValue)
        menu.addItem(.separator())
        addSpeechItems(menu)
        menu.addItem(.separator())
        add(menu, "Show pet", #selector(toggleDefault(_:)),
            on: defaults.bool(forKey: DefaultsKey.showOrb.rawValue), rep: DefaultsKey.showOrb.rawValue)
        let characters = NSMenu()
        characters.autoenablesItems = false
        let active = petCharacter(named: defaults.string(forKey: DefaultsKey.character.rawValue)).displayName
        for c in petCharacters {
            add(characters, c.displayName, #selector(setCharacter(_:)), on: c.displayName == active, rep: c.displayName)
        }
        let character = NSMenuItem(title: "Pet", action: nil, keyEquivalent: "")
        character.submenu = characters
        // A hidden pet has nothing to redraw.
        character.isEnabled = defaults.bool(forKey: DefaultsKey.showOrb.rawValue)
        menu.addItem(character)
        let animate = add(menu, "Animate when idle", #selector(toggleDefault(_:)),
                          on: defaults.bool(forKey: DefaultsKey.animateIdle.rawValue), rep: DefaultsKey.animateIdle.rawValue)
        animate.isEnabled = character.isEnabled
        menu.addItem(.separator())
        let loginStatus = SMAppService.mainApp.status
        let login = add(menu, loginStatus == .requiresApproval ? "Open at Login (approve in System Settings)" : "Open at Login",
                        #selector(toggleLogin(_:)), on: loginStatus == .enabled, rep: "")
        if loginStatus == .requiresApproval { login.state = .mixed }
        menu.addItem(.separator())
        let info = Bundle.main.infoDictionary
        let version = (info?["PardonBuild"] as? String) ?? (info?["CFBundleShortVersionString"] as? String) ?? "unknown"
        let about = NSMenuItem(title: "Pardon \(version)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        menu.addItem(NSMenuItem(title: "Quit Pardon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    // Voice and speed checkmarks come from pardon.conf, which the hooks read too.
    func addSpeechItems(_ menu: NSMenu) {
        let status = NSMenuItem(title: speechStatusText(speechUp), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        speechLine = status
        add(menu, "Mute speech", #selector(toggleManualMute(_:)), on: mute.isManual, rep: "")
        add(menu, "Mute speech while recording", #selector(toggleDefault(_:)),
            on: defaults.bool(forKey: DefaultsKey.muteKokoro.rawValue), rep: DefaultsKey.muteKokoro.rawValue)
        let conf = speechConf.read()
        let voiceMenu = NSMenu()
        voiceMenu.autoenablesItems = false
        fillVoices(voiceMenu, conf: conf)
        let voice = NSMenuItem(title: "Voice", action: nil, keyEquivalent: "")
        voice.submenu = voiceMenu
        menu.addItem(voice)
        voiceItem = voice
        let speedMenu = NSMenu()
        speedMenu.autoenablesItems = false
        for s in speedSteps { add(speedMenu, s, #selector(setSpeed(_:)), on: s == conf.speed, rep: s) }
        let speed = NSMenuItem(title: "Speed", action: nil, keyEquivalent: "")
        speed.submenu = speedMenu
        menu.addItem(speed)
        speedItem = speed
        testItem = add(menu, "Test voice", #selector(testVoice(_:)), on: false, rep: "")
        applySpeechEnabled()
    }

    func fillVoices(_ menu: NSMenu, conf: SpeechConf) {
        menu.removeAllItems()
        for v in voiceNames(voices) { add(menu, v.name, #selector(setVoice(_:)), on: v.id == conf.voice, rep: v.id) }
    }

    @discardableResult
    func add(_ menu: NSMenu, _ title: String, _ action: Selector, on: Bool, rep: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        item.representedObject = rep
        menu.addItem(item)
        return item
    }

    @objc func openSettings(_ sender: NSMenuItem) {
        guard let url = (sender.representedObject as? String).flatMap(URL.init(string:)) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func copyLastTranscript(_ sender: NSMenuItem) {
        guard let text = lastTranscript else { return }
        writeTranscript(text, to: NSPasteboard.general)
    }

    @objc func setMode(_ sender: NSMenuItem) {
        defaults.set(sender.representedObject as? String, forKey: DefaultsKey.mode.rawValue)
        abortSession()
        machine.mode = mode
    }

    @objc func setSide(_ sender: NSMenuItem) {
        defaults.set(sender.representedObject as? String, forKey: DefaultsKey.side.rawValue)
        abortSession()
        machine.side = side
    }

    @objc func toggleDefault(_ sender: NSMenuItem) {
        guard let key = (sender.representedObject as? String).flatMap(DefaultsKey.init(rawValue:)) else { return }
        defaults.set(!defaults.bool(forKey: key.rawValue), forKey: key.rawValue)
        if key == .animateIdle { updatePet(health) }
        guard key == .showOrb else { return }
        let visible = defaults.bool(forKey: key.rawValue)
        // A hidden pet could not end its own session: the key ignores it.
        if !visible, machine.pointerSessionLive { abortSession() }
        pet?.setShown(visible)
        syncLevelMeter()
        refreshUI()
    }

    // Only the drawing changes: a session in progress carries on.
    @objc func setCharacter(_ sender: NSMenuItem) {
        let name = sender.representedObject as? String
        guard name != petCharacter(named: defaults.string(forKey: DefaultsKey.character.rawValue)).displayName else { return }
        defaults.set(name, forKey: DefaultsKey.character.rawValue)
        pet?.reloadCharacter()
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        switch service.status {
        case .notRegistered, .notFound:
            do {
                try service.register()
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            } catch {
                SMAppService.openSystemSettingsLoginItems()
            }
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
        default:
            try? service.unregister()
        }
    }
}
