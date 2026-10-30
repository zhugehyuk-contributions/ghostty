import AppKit
import Carbon

extension Ghostty {
    /// An input context for a terminal, which cannot replace text already sent to the PTY.
    class SurfaceInputContext: NSTextInputContext {
        override func activate() {
            super.activate()

            // AppKit advertises document access for NSTextInputClient by default.
            // This includes support for replacing previously committed text, which
            // SurfaceView cannot provide. The Korean IME otherwise commits its first
            // character before discovering this and falling back to marked text.
            // Remove the capability when activating our document, before the input
            // method chooses how to compose. Doing this in keyDown is too late.
            guard let document = TSMGetActiveDocument() else { return }
            TSMRemoveDocumentProperty(
                document,
                TSMDocumentPropertyTag(kTSMDocumentSupportDocumentAccessPropertyTag))
        }
    }
}
