import AppKit
import Carbon
import GhosttyKit

@MainActor
func runKoreanIMEDiagnostic(_ app: ghostty_app_t) async {
    func log(_ text: String) { print("IME REAL \(text)"); fflush(stdout) }
    var failures = 0
    func check(_ value: Bool, _ label: String) {
        log("\(value ? "PASS" : "FAIL") \(label)")
        if !value { failures += 1 }
    }
    do {
        let prior = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let sources = TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
        func id(_ source: TISInputSource) -> String {
            Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(source, kTISPropertyInputSourceID)).takeUnretainedValue() as String
        }
        let parent = sources.first { id($0) == "com.apple.inputmethod.Korean" }!
        let korean = sources.first { id($0) == "com.apple.inputmethod.Korean.2SetKorean" }!
        check(TISEnableInputSource(parent) == noErr, "enable Korean")
        check(TISEnableInputSource(korean) == noErr, "enable Korean mode")
        var capture = "/tmp/ghostty-ime-pty-\(getpid())"
        try Data().write(to: URL(fileURLWithPath: capture))
        var config = Ghostty.SurfaceConfiguration()
        config.command = "/bin/sh -c 'stty raw -echo; cat > \(capture)'"
        let view = Ghostty.SurfaceView(app, baseConfig: config)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)
        try await Task.sleep(for: .seconds(1))
        check(NSApp.isActive && window.isKeyWindow && window.firstResponder === view && view.surface != nil, "active real terminal surface")
        check(TISSelectInputSource(korean) == noErr, "select Korean")
        try await Task.sleep(for: .seconds(1))
        for key: UInt16 in [5, 40, 1] {
            let native = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)!
            NSApp.postEvent(NSEvent(cgEvent: native)!, atStart: false)
            try await Task.sleep(for: .milliseconds(500))
            let bytes = try Data(contentsOf: URL(fileURLWithPath: capture))
            log("key=\(key) marked=\(view.hasMarkedText()) range=\(view.markedRange()) pty=\(String(decoding: bytes, as: UTF8.self).debugDescription)")
            check(view.hasMarkedText(), "preedit after key \(key)")
            check(bytes.isEmpty, "no premature PTY input after key \(key)")
        }
        NSApp.postEvent(NSEvent(cgEvent: CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true)!)!, atStart: false)
        try await Task.sleep(for: .milliseconds(500))
        let committed = try Data(contentsOf: URL(fileURLWithPath: capture))
        log("final=\(String(decoding: committed, as: UTF8.self).debugDescription)")
        check(String(decoding: committed, as: UTF8.self) == "한 ", "PTY receives exactly composed syllable and space")
        @MainActor func typeKeys(_ keys: [(UInt16, CGEventFlags)]) async throws {
            for (key, flags) in keys {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)!
                event.flags = flags
                NSApp.postEvent(NSEvent(cgEvent: event)!, atStart: false)
                try await Task.sleep(for: .milliseconds(200))
            }
            try await Task.sleep(for: .milliseconds(300))
        }
        func received() throws -> String {
            String(decoding: try Data(contentsOf: URL(fileURLWithPath: capture)), as: UTF8.self)
        }
        let english = sources.first { id($0) == "com.apple.keylayout.ABC" } ?? sources.first { id($0) == "com.apple.keylayout.US" }!
        check(TISEnableInputSource(english) == noErr && TISSelectInputSource(english) == noErr, "switch to English")
        try await Task.sleep(for: .seconds(1))
        var before = try received()
        try await typeKeys([(0, []), (0, .maskShift), (0, .maskControl), (123, [])])
        check(try received() == before + "aA\u{1}\u{1b}[D", "ASCII, Shift, Ctrl+A, Left arrow")
        if let international = sources.first(where: { id($0) == "com.apple.keylayout.USInternational-PC" }) {
            check(TISEnableInputSource(international) == noErr && TISSelectInputSource(international) == noErr, "switch to US International")
            try await Task.sleep(for: .seconds(1))
            before = try received()
            try await typeKeys([(39, []), (14, [])])
            check(try received() == before + "é", "dead-key accent composition")
        } else { log("SKIP US International unavailable") }
        if let japanese = sources.first(where: { id($0).contains("Kotoeri") && id($0).hasSuffix(".Japanese") }) {
            for source in sources where id(source).contains("Kotoeri") { _ = TISEnableInputSource(source) }
            check(TISSelectInputSource(japanese) == noErr, "switch to Japanese")
            try await Task.sleep(for: .seconds(1))
            before = try received()
            try await typeKeys([(40, []), (31, []), (45, []), (45, [])])
            check(try view.hasMarkedText() && received() == before, "Japanese preedit stays out of PTY")
            try await typeKeys([(36, [])])
            log("Japanese committed=\((try received()).debugDescription)")
            check(try received() == before + "こん", "Japanese commit without extra Return")
        } else { log("SKIP Japanese unavailable") }
        check(TISSelectInputSource(korean) == noErr, "switch back to Korean")
        try await Task.sleep(for: .seconds(1))
        before = try received()
        try await typeKeys([(5, []), (40, []), (1, [])])
        check(try view.hasMarkedText() && received() == before, "Korean preedit after switching back")
        try await typeKeys([(49, [])])
        check(try received() == before + "한 ", "Korean commit after switching back")
        check(EnableSecureEventInput() == noErr, "enable Secure Keyboard Entry")
        capture += "-second"
        try Data().write(to: URL(fileURLWithPath: capture))
        config.command = "/bin/sh -c 'stty raw -echo; cat > \(capture)'"
        let second = Ghostty.SurfaceView(app, baseConfig: config)
        window.contentView = second
        window.makeFirstResponder(second)
        try await Task.sleep(for: .seconds(1))
        check(TISSelectInputSource(korean) == noErr, "Korean in new terminal surface")
        try await Task.sleep(for: .seconds(1))
        try await typeKeys([(5, []), (40, []), (1, [])])
        check(try second.hasMarkedText() && received().isEmpty, "new surface preedit with Secure Keyboard Entry")
        try await typeKeys([(49, [])])
        check(try received() == "한 ", "new surface commits exact Korean syllable")
        check(DisableSecureEventInput() == noErr, "restore Secure Keyboard Entry")
        TISSelectInputSource(prior)
        window.close()
    } catch { log("ERROR \(error)"); failures += 1 }
    log("RESULT \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    exit(failures == 0 ? 0 : 1)
}
