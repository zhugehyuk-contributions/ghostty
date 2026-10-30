import AppKit
import Carbon

func report(_ s: String) { print(s); fflush(stdout) }

final class InputView: NSView, NSTextInputClient {
    var marked = ""
    var commits: [String] = []
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        report("keyDown key=\(event.keyCode) chars=\(String(reflecting: event.characters)) current=\(NSTextInputContext.current === inputContext) before=\(marked)")
        commits = []
        if CommandLine.arguments.contains("--handle") {
            report("handled=\(inputContext!.handleEvent(event))")
        } else {
            interpretKeyEvents([event])
        }
        report("after marked=\(marked) commits=\(commits)")
    }
    func hasMarkedText() -> Bool { !marked.isEmpty }
    func markedRange() -> NSRange { NSRange(location: 0, length: marked.utf16.count) }
    func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        marked = (string as? NSAttributedString)?.string ?? string as? String ?? ""
        report("setMarkedText \(String(reflecting: marked))")
    }
    func unmarkText() { report("unmarkText"); marked = "" }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func characterIndex(for point: NSPoint) -> Int { 0 }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        window?.convertToScreen(NSRect(x: 30, y: 30, width: 10, height: 20)) ?? .zero
    }
    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? string as? String ?? ""
        report("insertText \(String(reflecting: text)) replacement=\(replacementRange)")
        marked = ""; commits.append(text)
    }
    override func doCommand(by selector: Selector) { report("command \(selector)") }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.finishLaunching()
let prior = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
let sources = TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
func id(_ source: TISInputSource) -> String {
    Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(source, kTISPropertyInputSourceID)).takeUnretainedValue() as String
}
for s in sources { report("source \(id(s))") }
guard let korean = sources.first(where: { id($0) == "com.apple.inputmethod.Korean.2SetKorean" }) else { fatalError("Korean IME unavailable") }
TISEnableInputSource(korean)
let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 420, height: 140), styleMask: [.titled, .closable], backing: .buffered, defer: false)
window.title = "Ghostty Korean IME diagnostic"
let view = InputView(frame: window.contentView!.bounds)
window.contentView = view
window.makeKeyAndOrderFront(nil)
window.makeFirstResponder(view)
app.activate(ignoringOtherApps: true)
let keys: [(UInt16, String)] = [(5,"ㅎ"),(40,"ㅏ"),(1,"ㄴ"),(5,"ㅎ"),(40,"ㅏ"),(1,"ㄴ"),(51,"\u{7f}"),(51,"\u{7f}"),(51,"\u{7f}")]
DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
    app.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(view)
    report("app active=\(app.isActive) key=\(window.isKeyWindow) responder=\(window.firstResponder === view) context=\(String(describing: view.inputContext)) current=\(String(describing: NSTextInputContext.current))")
    report("select Korean \(TISSelectInputSource(korean))")
    for (i, key) in keys.enumerated() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.2) {
            let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: key.1, charactersIgnoringModifiers: key.1, isARepeat: false, keyCode: key.0)!
            app.postEvent(ev, atStart: false)
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        TISSelectInputSource(prior)
        app.terminate(nil)
    }
}
app.run()
