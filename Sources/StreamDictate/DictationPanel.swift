import Cocoa

protocol DictationPanelDelegate: AnyObject {
    func dictationPanel(didSubmitText text: String)
    func dictationPanelDidCancel()
}

/// A floating text-editing panel that supports both typing and macOS system dictation.
final class DictationPanel: NSObject, NSWindowDelegate {
    weak var delegate: DictationPanelDelegate?

    private let panel: NSPanel
    private let textView: DictationTextView
    private let scrollView: NSScrollView

    var isVisible: Bool { panel.isVisible }

    var currentText: String {
        textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 180),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        textView = DictationTextView()
        scrollView = NSScrollView()

        super.init()

        setupPanel()
        setupViews()
    }

    // MARK: - Setup

    private func setupPanel() {
        panel.title = "StreamDictate"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 300, height: 100)
        panel.delegate = self
        panel.center()
    }

    private func setupViews() {
        guard let container = panel.contentView else { return }

        // --- scroll view ---
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        // --- text view ---
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 16)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.drawsBackground = false
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude
        )

        textView.submitHandler = { [weak self] in self?.submit() }
        textView.cancelHandler = { [weak self] in self?.cancel() }
        textView.toggleDictationHandler = { [weak self] in self?.toggleDictation() }

        scrollView.documentView = textView
        container.addSubview(scrollView)

        // --- hint label ---
        let hint = NSTextField(
            labelWithString: "R.Shift+Enter submit \u{00B7} Enter newline \u{00B7} Esc cancel"
        )
        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.alignment = .center
        container.addSubview(hint)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 28),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -4),

            hint.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            hint.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            hint.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            hint.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    // MARK: - Public

    /// Show the panel, focus the text view, and start macOS dictation.
    func showAndDictate() {
        textView.string = ""
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(textView)

        // Brief delay so the window is fully key before starting dictation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, self.panel.isVisible else { return }
            self.triggerDictation()
        }
    }

    /// Show the panel without starting dictation (typing-only).
    func showForTyping() {
        textView.string = ""
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(textView)
    }

    func dismiss() {
        panel.orderOut(nil)
    }

    // MARK: - Private

    private func submit() {
        let text = currentText
        panel.orderOut(nil)
        delegate?.dictationPanel(didSubmitText: text)
    }

    private func cancel() {
        panel.orderOut(nil)
        delegate?.dictationPanelDidCancel()
    }

    private func toggleDictation() {
        triggerDictation()
    }

    /// Programmatically activate macOS system dictation via the responder chain.
    /// Same mechanism as Edit > Start Dictation menu item.
    private func triggerDictation() {
        NSApp.sendAction(NSSelectorFromString("startDictation:"), to: nil, from: nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        delegate?.dictationPanelDidCancel()
    }
}

// MARK: - DictationTextView

/// Custom NSTextView that intercepts keys for submit / cancel / dictation toggle.
final class DictationTextView: NSTextView {
    var submitHandler: (() -> Void)?
    var cancelHandler: (() -> Void)?
    var toggleDictationHandler: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let keyCode = event.keyCode
        let rawFlags = event.modifierFlags

        // Return/Enter: check for Right Shift to submit
        if keyCode == 36 || keyCode == 76 {
            // Right Shift (flag bit 0x04) + Enter = submit
            if rawFlags.rawValue & 0x04 != 0 {
                submitHandler?()
                return
            }
            // Plain Enter = newline (default NSTextView behavior)
            super.keyDown(with: event)
            return
        }

        // Escape (53)
        if keyCode == 53 {
            cancelHandler?()
            return
        }

        super.keyDown(with: event)
    }
}
