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
        let capture = "/tmp/ghostty-ime-pty-\(getpid())"
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
        TISSelectInputSource(prior)
        window.close()
    } catch { log("ERROR \(error)"); failures += 1 }
    log("RESULT \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    exit(failures == 0 ? 0 : 1)
}
