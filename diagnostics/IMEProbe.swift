import AppKit
import Carbon

func removeDocumentAccess() {
    guard let document = TSMGetActiveDocument() else { report("no TSM document"); return }
    let status = TSMRemoveDocumentProperty(document, TSMDocumentPropertyTag(kTSMDocumentSupportDocumentAccessPropertyTag))
    report("remove document access \(status)")
}

func report(_ s: String) { print("\(ProcessInfo.processInfo.systemUptime) \(s)"); fflush(stdout) }

final class NativeTextView: NSTextView {
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        report("native setMarkedText \(string)")
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }
    override func insertText(_ string: Any, replacementRange: NSRange) {
        report("native insertText \(string) replacement=\(replacementRange) selected=\(selectedRange()) marked=\(markedRange())")
        super.insertText(string, replacementRange: replacementRange)
    }
}

final class InputView: NSView, NSTextInputClient {
    var marked = ""
    var commits: [String] = []
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        report("keyDown key=\(event.keyCode) chars=\(String(reflecting: event.characters)) current=\(NSTextInputContext.current === inputContext) before=\(marked)")
        commits = []
        if CommandLine.arguments.contains("--document-key") { removeDocumentAccess() }
        if CommandLine.arguments.contains("--handle") {
            report("handled=\(inputContext!.handleEvent(event))")
        } else {
            interpretKeyEvents([event])
        }
        report("after marked=\(marked) commits=\(commits)")
    }
    func hasMarkedText() -> Bool { report("hasMarkedText -> \(!marked.isEmpty)"); return !marked.isEmpty }
    func markedRange() -> NSRange { NSRange(location: marked.isEmpty && CommandLine.arguments.contains("--ranges") ? NSNotFound : 0, length: marked.utf16.count) }
    func selectedRange() -> NSRange { let r = NSRange(location: CommandLine.arguments.contains("--ranges") ? NSNotFound : 0, length: 0); report("selectedRange -> \(r)"); return r }
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        marked = (string as? NSAttributedString)?.string ?? string as? String ?? ""
        report("setMarkedText \(String(reflecting: marked))")
    }
    func unmarkText() { report("unmarkText"); marked = "" }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { report("validAttributes"); if CommandLine.arguments.contains("--underline") { return [.underlineStyle] }; if CommandLine.arguments.contains("--clause") { return [.markedClauseSegment] }; if CommandLine.arguments.contains("--font") { return [.font] }; return [] }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { report("substring \(range)"); if CommandLine.arguments.contains("--actual") { actualRange?.pointee = NSRange(location: NSNotFound, length: 0) }; return nil }
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
report("secure input \(IsSecureEventInputEnabled())")
app.setActivationPolicy(.regular)
app.finishLaunching()
let prior = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
let sources = TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
func id(_ source: TISInputSource) -> String {
    Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(source, kTISPropertyInputSourceID)).takeUnretainedValue() as String
}
if let parent = sources.first(where: { id($0) == "com.apple.inputmethod.Korean" }) {
    report("enable Korean input method \(TISEnableInputSource(parent))")
}
guard let korean = sources.first(where: { id($0) == "com.apple.inputmethod.Korean.2SetKorean" }) else { fatalError("Korean IME unavailable") }
report("enable Korean input mode \(TISEnableInputSource(korean))")
let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 420, height: 140), styleMask: [.titled, .closable], backing: .buffered, defer: false)
window.title = "Ghostty Korean IME diagnostic"
let view: NSView = CommandLine.arguments.contains("--native") ? NativeTextView(frame: window.contentView!.bounds) : InputView(frame: window.contentView!.bounds)
window.contentView = view
window.makeKeyAndOrderFront(nil)
window.makeFirstResponder(view)
if CommandLine.arguments.contains("--activate") { view.inputContext?.activate() }
app.activate(ignoringOtherApps: true)
let keys: [(UInt16, String)] = [(5,"ㅎ"),(40,"ㅏ"),(1,"ㄴ"),(5,"ㅎ"),(40,"ㅏ"),(1,"ㄴ"),(51,"\u{7f}"),(51,"\u{7f}"),(51,"\u{7f}")]
DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
    app.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(view)
    report("app active=\(app.isActive) key=\(window.isKeyWindow) responder=\(window.firstResponder === view) context=\(String(describing: view.inputContext)) current=\(String(describing: NSTextInputContext.current))")
    if CommandLine.arguments.contains("--document") { removeDocumentAccess() }
    report("select Korean \(TISSelectInputSource(korean))")
    report("selected source \(id(TISCopyCurrentKeyboardInputSource().takeRetainedValue()))")
    for (i, key) in keys.enumerated() {
        DispatchQueue.main.asyncAfter(deadline: .now() + (CommandLine.arguments.contains("--delay") ? 2.0 : 0.0) + Double(i) * (CommandLine.arguments.contains("--slow") ? 0.8 : 0.2)) {
            let native = CGEvent(keyboardEventSource: nil, virtualKey: key.0, keyDown: true)!
            let event = NSEvent(cgEvent: native)!
            report("enqueue native key \(key.0), chars=\(String(reflecting: event.characters))")
            if CommandLine.arguments.contains("--discard") { view.inputContext?.discardMarkedText() }; app.postEvent(event, atStart: false)
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
        TISSelectInputSource(prior)
        app.terminate(nil)
    }
}
app.run()
