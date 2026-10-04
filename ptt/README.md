# Pardon (push-to-talk menu bar app)

A small macOS menu bar app for the Parakeet STT container: hold the Option key (or the
floating orb), speak, let go, and the transcript is pasted into whatever window has focus.
Audio is recorded in memory and sent only to `127.0.0.1:8881`. No audio or transcript is
written to disk or to any log; settings live in the app's preferences file, and the Kokoro
mute flag (below) is a file.

## Before the first build

- A Mac with Apple Silicon running macOS 13 or later.
- Xcode Command Line Tools (`xcode-select --install`); the build uses `/usr/bin/swiftc`.
- The STT container running: `make build-stt`, then `make run-stt` (see `stt/README.md`).
- Optional, once: `make ptt-cert`. macOS ties the Microphone and Accessibility grants to
  the app's signature, and an ad-hoc signed build gets a new one every time, so each
  rebuild would ask for both permissions again. This creates a self-signed code-signing
  identity named `Pardon` in your login keychain; it is used for nothing but signing this
  app and is not trusted for TLS or anything else. Its private key cannot be exported.
  When macOS asks whether `codesign` may use the `Pardon` key (it may also ask for your
  login keychain password), choose **Allow**, not Always Allow: macOS should then ask again
  on later builds, which keeps any use of the key visible to you. Always Allow removes the
  prompt and lets any program running as you sign with the key silently. To remove the
  identity: Keychain Access → login → My Certificates → Pardon → delete.

  Be aware of what this identity is: a signing key for an app that holds Microphone and
  Accessibility permission. Any program running as you could use it to sign something
  that then inherits those permissions. Ad-hoc builds do not have this exposure, but lose
  the permissions on every rebuild. Recommended: use the certificate while you are
  rebuilding often; once Pardon is stable, delete it (as above) and let builds be ad-hoc
  signed, which cannot be impersonated this way, at the cost of granting the two
  permissions again after each rebuild.

## Build and run

`make ptt` builds `ptt/build/Pardon.app`, replaces `~/Applications/Pardon.app` (override
with `PTT_APP=…`) and starts it. The microphone icon appears in the menu bar and the orb
near the bottom-right of the screen; there is no Dock icon. On first launch:

1. Allow the microphone when macOS asks.
2. In the Accessibility dialog, choose Open System Settings and switch Pardon on.
3. The icon changes from a slashed microphone to a plain one.

Pardon notices the Accessibility grant normally within a couple of seconds; if not, quit
and reopen Pardon.

`make test-ptt` compiles an unsigned copy into a temp directory and runs its self-test
(the hotkey state machine, key decoding, WAV header, transcript sanitising, response
parsing, the reply size cap, the focus check, the paste key lookup, the mute flag, the
orb as a trigger (handover with the key, lost releases, which clicks count), and the
orb's gesture and its drag grace for a recording, hit test, placement, saved position,
looks and how long an outcome shows, animations, the idle frame rate and the Animate when
idle toggle, voice level and level smoothing, and the characters (the registry, the saved
choice, the arc reactor's ring geometry and animations, and that it draws nothing outside
its circle); no GUI, microphone or network, and it touches only a temporary directory). Also
`make stop-ptt` and `make clean-ptt` (stops the app and removes `ptt/build` and the
installed app; not the certificate or the entries in System Settings).

## Using it

- **Hold to talk** (default): hold Option on its own, speak, release. Recording starts
  0.25 s after the press, so a quick press does nothing and an Option chord typed within
  a quarter of a second never starts the microphone. Pressing any later key, or any click
  while recording except a left click on the orb, cancels silently.
- **Tap to toggle**: tap Option (under 0.4 s, on its own) to start, tap again to send.
  Typing while recording does not cancel.
- The menu chooses which Option key counts: right (default), left or either. Changing
  the mode or the key abandons a recording in progress.
- Recordings stop and send by themselves at 118 s (the server's limit is 120 s).
- Sleep, a locked screen, switching user or losing Accessibility abandons a recording or
  a transcription in progress; nothing is pasted.
- **Auto-submit (Return)**, off by default: presses Return after pasting, but only when
  the transcript has at least three words. With it on, Pardon types and submits whatever
  the local speech server returns into the focused window, so leave it off for terminals
  unless you accept that.
- **Mute Kokoro while recording**, on by default: creates `~/.claude/hooks/mute` (content
  `pardon`) when recording starts and removes it once the transcript has been pasted (the
  flag stays through transcription and paste, not only while you speak), so the voice hook
  stays quiet. It stops new speech; it does not cut off a sentence already playing. A mute
  you set with `make mute` before recording is left alone; `make mute` during a recording
  does not survive it (the file still holds `pardon`, so it is removed at the end).
- **Open at Login** registers the installed copy in `~/Applications`.
- Transcripts are cleaned before pasting: line breaks, tabs and other control or
  formatting characters become spaces, and at most 4000 characters are pasted.
- The clipboard is restored about a second after the paste (unless something else has
  changed it in between), and the transcript is marked transient so clipboard managers
  can skip it. It stays on this Mac: it is not shared with your other devices through
  Universal Clipboard.
- The paste is Cmd-V on whichever key types "v" with Command held in your current keyboard
  layout, so it works on Dvorak and other non-QWERTY layouts, including those whose
  shortcuts stay on QWERTY positions (such as "Dvorak – QWERTY ⌘").
- The paste goes to the focused window of the app that was in front when you stopped
  speaking (if you switch windows within that app meanwhile, it lands in the new one). If
  another app has come to the front by the time the transcript arrives, nothing is pasted
  (nor submitted) and Basso plays. Focus is checked again just before Cmd-V and before
  Return: a switch before the paste stops both, a switch after it stops only Return. Pardon cannot know whether a paste landed: the last
  transcript can be copied from the menu (**Copy last transcript**) until Pardon quits. It
  is kept in memory only.

Sounds: Tink when recording starts, Pop when the text is pasted, Purr when nothing was
heard, Basso on any error. After an error the menu's status line says what went wrong
until the next successful paste.

## The orb

A small floating circle that does what the Option key does, for when a hand is on the
mouse. It sits above ordinary windows, on every Space and over full-screen apps, but
below the Dock, menus and system overlays, and never takes focus from the window the
transcript is meant for.

- **Press and hold** it to talk, release to send: the same Hold to talk / Tap to toggle
  setting, delays and 118 s limit as the key (in tap mode, click once to start and once to
  send). While one of the orb or the Option key is recording, the other is ignored; in tap
  mode the key cannot stop a recording the orb started, and the orb cannot stop one the
  key started.
- **Drag** it to move it. Before a recording starts, a press that moves more than a few
  points becomes a drag and records nothing. Once a hold-mode recording started by this
  press is running, moving more than 10 points from where you pressed within 1.5 seconds of
  pressing cancels it silently (nothing is sent) and drags the orb; after that, or for a
  smaller move, the movement is ignored and releasing sends. In tap mode the stop click
  never drags, and a recording started with the Option key is not affected by dragging the
  orb.
- It stays where you drop it, on that display, and is pulled back on screen at launch and
  when displays change; it returns to its place when an unplugged display comes back. To
  reset its position: `defaults delete io.github.abandisch.pardon orbOrigin`, then
  relaunch Pardon.
- **Right-click** (or Control-click) opens the same menu as the menu bar icon.
- **Show pet** in the menu hides or shows it (on by default). Hidden, it does nothing and
  the microphone level is not measured, from the moment it is hidden.
- **Pet** in the menu, just below Show pet, picks how it is drawn: **Arc reactor**
  (the default) or the original blue **Orb**. The change is immediate, in the same place,
  and does not interrupt a recording. The submenu is greyed out while the orb is hidden.
  The choice is remembered across launches; to reset it to the default:
  `defaults delete io.github.abandisch.pardon character`.
- **Animate when idle** in the menu, just below Pet (on by default; greyed out while the
  orb is hidden), turns the repeating motion of the ready, pasted, nothing heard and error
  looks on or off. Off, those looks hold still, but the one-off effects still play (the
  ripple or flash after a paste, the dim after nothing heard), listening and transcribing
  still move, and Reduce Motion overrides it. On, the idle animation runs at 30 frames a
  second to keep the window server's work low.
- Without Accessibility it stays grey and pressing it does nothing (the paste could not
  be posted anyway).

The arc reactor: a white-hot core inside cyan rings, on a dark disc.

| Look | Meaning |
| --- | --- |
| Lit, segment ring turning slowly, core gently pulsing | Ready |
| Rings spinning faster, core growing and whitening with your voice | Listening |
| Three lit blocks stepping clockwise round the segment ring, a lap every 1.2 s | Transcribing |
| One ring rippling out from the core | Pasted |
| Brief dim | Nothing heard |
| Amber-red, turning slowly | The last attempt failed (back to normal after about ten seconds; the menu's status line still says it failed), or the speech server is not running |
| Grey, dimmer, still | A permission is missing (Accessibility or microphone) or the hotkey is unavailable |

The blue Orb character:

| Look | Meaning |
| --- | --- |
| Dim blue, slow breath | Ready |
| Bright, pulsing with your voice, blue warming toward white | Listening |
| Swirling shimmer | Transcribing |
| One quick flash | Pasted |
| Soft fade | Nothing heard |
| Amber-red | The last attempt failed (back to normal after about ten seconds; the menu's status line still says it failed), or the speech server is not running |
| Grey, still | A permission is missing (Accessibility or microphone) or the hotkey is unavailable |

With **Animate when idle** off, the turning, pulsing and breathing of the ready, pasted,
nothing heard and error looks stop.

With Reduce Motion on (System Settings → Accessibility → Display) every look is still: no
turning, breathing, pulsing, chase, swirl, ripple, flash or fade. VoiceOver reads it as a
button labelled with Pardon's status. Instead of motion, the arc reactor shows listening by a
steady, larger, whiter core and a brighter segment ring.

## What it does and does not do

- Audio stays in memory and is sent only to `http://127.0.0.1:8881/transcribe` (a fixed
  address; no setting), never through a proxy and never to a redirect target. The only
  other request is the `/health` check every 10 s and when the menu opens; it pauses
  during a recording or transcription. Anything listening on `127.0.0.1:8881` receives
  the audio, so keep the container running or quit Pardon. A transcription reply larger
  than 256 KB is refused without being read further.
- No transcript or audio is logged or written to disk.
- **Microphone**: to record while you are dictating. The microphone is on only while
  recording.
- **Accessibility**: to see the Option key from any app, and to post Cmd-V (and Return)
  into the focused window. Pardon never blocks or changes your keystrokes, and does not
  ask for Input Monitoring.
- The app is signed with the hardened runtime, which blocks library injection through
  `DYLD_INSERT_LIBRARIES` into a process that holds the Microphone and Accessibility grants.
- Settings live in the app's own preferences (`io.github.abandisch.pardon`).

## Every ingredient

- ~3000 lines of our own Swift in `ptt/Sources/Pardon/`: `main.swift` (the entry point),
  `App/`, `Hotkey/`, `Audio/`, `Transcription/` and `Delivery/` (the app), `Pet/` (the orb,
  its blue character and the arc reactor character, both drawn in code with no image
  files), and `SelfTest/` (the `--self-test` checks).
- Apple system frameworks only: AppKit, AVFoundation, Carbon (keyboard layout lookup),
  CoreGraphics, QuartzCore (the orb's animation), ApplicationServices, ServiceManagement,
  Foundation. No third-party code, no package manager.
- `ptt/build.sh` (compile, Info.plist, entitlements, sign) and `ptt/make-cert.sh` (stock
  `openssl` and `security`).

## Troubleshooting

- **Slashed microphone icon**: any of Accessibility missing, microphone denied, or the
  speech server not running. Open the menu to see which; it offers a button to the right
  System Settings pane when a permission is missing.
- **Speech server not running**: `make run-stt`, then wait for `parakeet ready:` in
  `make logs-stt`.
- **Accessibility shows Pardon switched on but the menu still asks for it** (or says the
  hotkey is unavailable): after an ad-hoc rebuild, System Settings may still show Pardon
  switched on while macOS refuses it. Remove Pardon from the Accessibility list with the
  minus button, then run `make ptt` and grant again; or run `make ptt-cert` once to stop
  this recurring.
- **Microphone access denied**: System Settings → Privacy & Security → Microphone, then
  switch Pardon on.
- **Orb not visible**: check **Show pet** in the menu; if it is on, reset its position with
  `defaults delete io.github.abandisch.pardon orbOrigin` and relaunch Pardon.
- **Hotkey does nothing in a password field or in Terminal**: while a password field or
  Terminal's Secure Keyboard Entry is active, macOS may withhold key events from Pardon.
- **Nothing is pasted**: check System Settings → Privacy & Security → Accessibility, or
  use **Copy last transcript** from the menu.
- **Permissions asked again after every rebuild**: `make ptt-cert`, then `make ptt`.
- **A copied or downloaded build is blocked by Gatekeeper**: out of scope for now;
  build it on the Mac that runs it.
