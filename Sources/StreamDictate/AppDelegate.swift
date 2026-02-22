import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotkeyMonitor = HotkeyMonitor()
    private lazy var dictationPanel: DictationPanel = {
        let panel = DictationPanel()
        panel.delegate = self
        return panel
    }()

    /// The app that was frontmost before we showed our panel.
    private var previousApp: NSRunningApplication?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        checkPermissions()

        hotkeyMonitor.delegate = self
        hotkeyMonitor.start()

        let axTrusted = AXIsProcessTrusted()
        NSLog("[AppDelegate] StreamDictate launched. Accessibility: %@", axTrusted ? "YES" : "NO")
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyMonitor.stop()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "StreamDictate")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "StreamDictate v0.3", action: nil, keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func updateStatusIcon(active: Bool) {
        DispatchQueue.main.async { [weak self] in
            let symbolName = active ? "mic.fill" : "mic"
            self?.statusItem.button?.image = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: "StreamDictate"
            )
        }
    }

    // MARK: - Permissions

    private func checkPermissions() {
        if !PermissionChecker.checkAccessibility() {
            NSLog("[AppDelegate] Accessibility not granted — will prompt")
        }

        PermissionChecker.checkMicrophone { granted in
            if !granted {
                PermissionChecker.showPermissionAlert(
                    title: "Microphone Access Required",
                    message: "Grant access in System Settings > Privacy & Security > Microphone."
                )
            }
        }
    }

    // MARK: - Text Injection

    /// Inject a string via CGEvent in batches of up to 20 UTF-16 code units.
    private func injectString(_ string: String) {
        guard !string.isEmpty else { return }
        let utf16 = Array(string.utf16)
        let batchSize = 20

        var offset = 0
        while offset < utf16.count {
            let end = min(offset + batchSize, utf16.count)
            let batch = Array(utf16[offset..<end])

            guard let source = CGEventSource(stateID: .hidSystemState) else { return }
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { return }

            keyDown.keyboardSetUnicodeString(stringLength: batch.count, unicodeString: batch)
            keyUp.keyboardSetUnicodeString(stringLength: batch.count, unicodeString: batch)

            keyDown.post(tap: .cgAnnotatedSessionEventTap)
            keyUp.post(tap: .cgAnnotatedSessionEventTap)

            offset = end
        }
    }
}

// MARK: - HotkeyMonitorDelegate

extension AppDelegate: HotkeyMonitorDelegate {
    func hotkeyDidActivate() {
        if dictationPanel.isVisible {
            // Second press while panel is open → submit.
            let text = dictationPanel.currentText
            dictationPanel.dismiss()
            finishWithText(text)
        } else {
            // First press → open panel and start dictation.
            previousApp = NSWorkspace.shared.frontmostApplication
            updateStatusIcon(active: true)
            dictationPanel.showAndDictate()
        }
    }

    func hotkeyDidDeactivate() {
        // Not used in popup mode.
    }
}

// MARK: - DictationPanelDelegate

extension AppDelegate: DictationPanelDelegate {
    func dictationPanel(didSubmitText text: String) {
        finishWithText(text)
    }

    func dictationPanelDidCancel() {
        updateStatusIcon(active: false)
        previousApp?.activate(options: [])
        previousApp = nil
    }

    private func finishWithText(_ text: String) {
        updateStatusIcon(active: false)

        guard !text.isEmpty else {
            previousApp?.activate(options: [])
            previousApp = nil
            return
        }

        // Return focus to the app the user was in, then inject text.
        previousApp?.activate(options: [])
        previousApp = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.injectString(text)
        }
    }
}
