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
    private var isDictating = false
    private var eventMonitor: Any?

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
        installEventMonitor()
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
            labelWithString: "R.Shift+Enter submit \u{00B7} R.Shift+] dictation \u{00B7} Esc cancel"
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

    /// Catches Right Shift combos at app level — during dictation, keyDown may be intercepted.
    private func installEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self = self, self.panel.isVisible else { return event }
            let rightShift = event.modifierFlags.rawValue & 0x04 != 0
            guard rightShift else { return event }

            // Right Shift + ] = toggle dictation
            if event.keyCode == 30 {
                self.toggleDictation()
                return nil
            }
            // Right Shift + Enter = submit
            if event.keyCode == 36 || event.keyCode == 76 {
                self.submit()
                return nil
            }
            return event
        }
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
            self.startDictation()
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
        isDictating = false
        panel.orderOut(nil)
    }

    // MARK: - Private

    private func submit() {
        let text = currentText
        isDictating = false
        panel.orderOut(nil)
        delegate?.dictationPanel(didSubmitText: text)
    }

    private func cancel() {
        isDictating = false
        panel.orderOut(nil)
        delegate?.dictationPanelDidCancel()
    }

    private func toggleDictation() {
        if isDictating {
            stopDictation()
        } else {
            startDictation()
        }
    }

    private func startDictation() {
        isDictating = true
        NSApp.sendAction(NSSelectorFromString("startDictation:"), to: nil, from: nil)
    }

    private func stopDictation() {
        isDictating = false
        // Hide and re-show the panel after a brief delay to kill dictation.
        let text = textView.string
        let frame = panel.frame
        panel.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            self.textView.string = text
            self.panel.setFrame(frame, display: false)
            self.panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.panel.makeFirstResponder(self.textView)
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        isDictating = false
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

        // Right Shift (flag bit 0x04) combos
        let rightShift = rawFlags.rawValue & 0x04 != 0

        // Right Shift + Enter = submit
        if rightShift && (keyCode == 36 || keyCode == 76) {
            submitHandler?()
            return
        }

        // Right Shift + ] (keyCode 30) = toggle dictation
        if rightShift && keyCode == 30 {
            toggleDictationHandler?()
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
