import AppKit
import Carbon
import Testing
@testable import Ghostty
import GhosttyKit

@MainActor
struct KoreanIMEIntegrationTests {
    @Test func firstKoreanSyllable() async throws {
        let app = try #require((NSApp.delegate as? AppDelegate)?.ghostty.app)
        let prior = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        defer { TISSelectInputSource(prior) }
        let sources = TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
        func id(_ source: TISInputSource) -> String {
            Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(source, kTISPropertyInputSourceID)).takeUnretainedValue() as String
        }
        let parent = try #require(sources.first { id($0) == "com.apple.inputmethod.Korean" })
        let korean = try #require(sources.first { id($0) == "com.apple.inputmethod.Korean.2SetKorean" })
        #expect(TISEnableInputSource(parent) == noErr)
        #expect(TISEnableInputSource(korean) == noErr)
        let capture = "/tmp/ghostty-ime-pty"
        try Data().write(to: URL(fileURLWithPath: capture))
        var config = Ghostty.SurfaceConfiguration()
        config.command = "/bin/sh -c 'stty raw -echo; cat > /tmp/ghostty-ime-pty'"
        let view = Ghostty.SurfaceView(app, baseConfig: config)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)
        defer { window.close() }
        try await Task.sleep(for: .seconds(1))
        print("IME REAL app=\(NSApp.isActive) key=\(window.isKeyWindow) responder=\(window.firstResponder === view) surface=\(view.surface != nil)")
        #expect(TISSelectInputSource(korean) == noErr)
        try await Task.sleep(for: .seconds(1))
        for key: UInt16 in [5, 40, 1] {
            let native = try #require(CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true))
            let event = try #require(NSEvent(cgEvent: native))
            NSApp.postEvent(event, atStart: false)
            try await Task.sleep(for: .milliseconds(500))
            let bytes = try Data(contentsOf: URL(fileURLWithPath: capture))
            print("IME REAL key=\(key) marked=\(view.hasMarkedText()) range=\(view.markedRange()) pty=\(String(decoding: bytes, as: UTF8.self).debugDescription)")
            #expect(view.hasMarkedText())
            #expect(bytes.isEmpty)
        }
        let space = try #require(NSEvent(cgEvent: CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true)!))
        NSApp.postEvent(space, atStart: false)
        try await Task.sleep(for: .milliseconds(500))
        let committed = try Data(contentsOf: URL(fileURLWithPath: capture))
        print("IME REAL final=\(String(decoding: committed, as: UTF8.self).debugDescription)")
        #expect(String(decoding: committed, as: UTF8.self) == "한 ")
    }
}
