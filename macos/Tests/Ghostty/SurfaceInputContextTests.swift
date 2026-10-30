import AppKit
import Carbon
import Testing
@testable import Ghostty

@MainActor
struct SurfaceInputContextTests {
    @Test func documentAccessIsDisabledOnlyForTerminalContext() throws {
        let previous = NSTextInputContext.current
        let editorView = NSTextView()
        let terminalView = NSTextView()
        let editorContext = NSTextInputContext(client: editorView)
        let terminalContext = Ghostty.SurfaceInputContext(client: terminalView)
        defer {
            terminalContext.deactivate()
            editorContext.deactivate()
            previous?.activate()
            withExtendedLifetime((editorView, terminalView)) {}
        }

        editorContext.activate()
        #expect(try supportsDocumentAccess())

        terminalContext.activate()
        #expect(try !supportsDocumentAccess())

        terminalContext.deactivate()
        editorContext.activate()
        #expect(try supportsDocumentAccess())

        terminalContext.activate()
        #expect(try !supportsDocumentAccess())
    }

    private func supportsDocumentAccess() throws -> Bool {
        let document = try #require(TSMGetActiveDocument())
        return TSMGetDocumentProperty(
            document,
            TSMDocumentPropertyTag(kTSMDocumentSupportDocumentAccessPropertyTag),
            0,
            nil,
            nil) == noErr
    }
}
