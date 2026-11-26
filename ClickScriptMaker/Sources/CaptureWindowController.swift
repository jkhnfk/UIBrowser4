//
//  CaptureWindowController.swift
//  ClickScriptMaker
//
//  Created by Bill Cheeseman on 2026-11-26.
//  Copyright © 2026 PFiddlesoft. All rights reserved.
//

import Cocoa

/**
 The CaptureWindowController.swift file implements Click Script Maker's only window.

 The window follows the workflow that the application is designed for: the user moves the mouse pointer over the UI element that a script should click, then presses the Command-Control-Option-C hot key or clicks the Capture Element Under Mouse button. Click Script Maker captures the element's identity with `ElementLocator`, generates an AppleScript or JavaScript for Automation script with `ClickScriptGenerator`, displays the script in the window and copies it to the clipboard, so that the user can paste it directly into Script Editor or another editor.

 The button can optionally wait a few seconds before it captures the element, which gives the user time to move the mouse pointer to an element in another application after clicking the button. The hot key captures the element immediately.

 The window also shows the accessibility path of the captured element, warns when the element shares its identity attributes with a sibling element, and explains how to grant the Accessibility permission that the accessibility API requires.
 */
final class CaptureWindowController: NSWindowController, NSWindowDelegate {

    // MARK: - PROPERTIES

    /// A type property that gives access to this object from any other object by referencing `CaptureWindowController.sharedInstance`. The window and its contents are created the first time the property is accessed.
    static let sharedInstance: CaptureWindowController = {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 620), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = NSLocalizedString("Click Script Maker", comment: "Title of the application's only window")
        window.isReleasedWhenClosed = false
        // The application has no state to restore, so the window does not participate in state restoration. This avoids the "Unable to find className" message that AppKit logs when a window is restored without a window controller.
        window.isRestorable = false
        window.contentMinSize = NSSize(width: 520, height: 380)
        window.center()
        return CaptureWindowController(window: window)
    }()

    /// The anchor of the element for which the script was generated, or `nil` before the first element is captured.
    private var anchor: ElementAnchor?

    /// The scripting language of the displayed script.
    private var language: ClickScriptLanguage = .appleScript

    /// The generator that builds the script from the anchor.
    private let generator = ClickScriptGenerator()

    /// The number of seconds that the Capture Element Under Mouse button waits before it captures the element. The hot key ignores this value and captures the element immediately.
    private var delaySeconds: Int = 3

    /// The timer that counts down the delay before the button captures the element, or `nil` if no countdown is in progress.
    private var countdownTimer: Timer?

    /// The number of seconds remaining in the countdown.
    private var remainingCountdown: Int = 0

    /// The label that explains how to use the application.
    private var instructionLabel: NSTextField!

    /// The label that explains that the application needs the Accessibility permission.
    private var permissionLabel: NSTextField!

    /// The stack view that contains the Accessibility permission explanation and button, which is hidden when the permission has been granted.
    private var permissionRow: NSStackView!

    /// The button that captures the element under the mouse pointer, directly or after the configured delay.
    private var captureButton: NSButton!

    /// The label that shows the delay before the button captures the element.
    private var delayLabel: NSTextField!

    /// The stepper that sets the delay before the button captures the element.
    private var delayStepper: NSStepper!

    /// The segmented control that chooses between AppleScript and JavaScript for Automation.
    private var languageSegmentedControl: NSSegmentedControl!

    /// The label that describes the captured element and its application.
    private var elementDescriptionLabel: NSTextField!

    /// The label that warns the user when an element's identity attributes are shared by more than one sibling element.
    private var warningLabel: NSTextField!

    /// The label that reports the result of the last capture, copy or save operation.
    private var statusLabel: NSTextField!

    /// The text view that displays the script.
    private var scriptTextView: NSTextView!

    // MARK: - INITIALIZATION

    override init(window: NSWindow?) {
        super.init(window: window)
        window?.delegate = self
        // Reuse the window's frame from the previous session so the window appears where the user left it.
        window?.setFrameAutosaveName("CaptureWindowFrame")
        buildContentView()
        updatePermissionState()
        // The Accessibility permission is granted in System Settings while the application is running, so the window must be updated when the user returns to the application.
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive(_:)), name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("CaptureWindowController must be initialized with init(window:)")
    }

    deinit {
        countdownTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - CAPTURE

    /**
     Captures the element under the mouse pointer immediately and displays the script that clicks it.

     This method is called by the Command-Control-Option-C hot key, which has to work while another application is active, and by the Capture Element Under Mouse button when the user has set the delay to zero.
     */
    func captureElementUnderMouse() {
        cancelCountdown()
        performCapture()
    }

    /// Starts the countdown, if the user configured one, and then captures the element under the mouse pointer.
    @objc private func startCapture(_ sender: Any?) {
        cancelCountdown()
        guard delaySeconds > 0 else {
            performCapture()
            return
        }
        remainingCountdown = delaySeconds
        captureButton.isEnabled = false
        updateCountdownStatus()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            self.remainingCountdown -= 1
            guard self.remainingCountdown > 0 else {
                timer.invalidate()
                self.countdownTimer = nil
                self.captureButton.isEnabled = true
                self.performCapture()
                return
            }
            self.updateCountdownStatus()
        }
    }

    /// Stops a countdown that is in progress and reenables the capture button.
    private func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        remainingCountdown = 0
        captureButton?.isEnabled = true
    }

    /// Shows how many seconds remain before the element is captured.
    private func updateCountdownStatus() {
        statusLabel.stringValue = String(format: NSLocalizedString("Capturing the element under the mouse pointer in %d seconds…", comment: "Status text of the countdown before the element is captured"), remainingCountdown)
    }

    /// Captures the element under the mouse pointer and presents the script, or presents an alert that describes why the element could not be captured.
    private func performCapture() {
        // The accessibility API returns the topmost element at the mouse location. If this application's own window covers the mouse pointer, the window is hidden while the element is captured so that the element that the user sees under the mouse pointer is the element that is captured.
        guard mouseIsOverWindow, let window = window else {
            captureAndPresent()
            return
        }
        window.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.captureAndPresent()
            self?.showWindow(nil)
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }

    /// `true` if the application's window is visible and contains the mouse pointer. Both the window frame and `NSEvent.mouseLocation` are in screen coordinates with a bottom-left origin.
    private var mouseIsOverWindow: Bool {
        guard let window = window, window.isVisible else { return false }
        return window.frame.contains(NSEvent.mouseLocation)
    }

    /// Captures the element under the mouse pointer and presents the script, or presents an alert that describes why the element could not be captured.
    private func captureAndPresent() {
        do {
            present(try ElementLocator.sharedInstance.anchorAtMouseLocation())
        } catch let error as ElementLocatorError {
            presentAlert(for: error)
        } catch {
            presentAlert(for: .noElementAtMouseLocation)
        }
    }

    /// Displays the script generated for the specified anchor, replaces the description of the element and copies the script to the clipboard.
    private func present(_ anchor: ElementAnchor) {
        self.anchor = anchor
        updateElementDescription(for: anchor)
        updateScript()
        copyScriptToPasteboard()
        showWindow(nil)
        // Another application is usually active when the hot key captures the element, so this application must be brought to the front explicitly.
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        // Show the description of the element to VoiceOver users and other users of assistive technology, because the script is generated without the user having clicked anything in the window.
        if let window = window {
            NSAccessibility.post(element: window, notification: .focusedWindowChanged)
        }
    }

    // MARK: - VIEW UPDATES

    /// Updates the description of the captured element and the warning about ambiguity.
    private func updateElementDescription(for anchor: ElementAnchor) {
        var applicationDescription = String(format: NSLocalizedString("Target application: %@", comment: "Description of the application that owns the captured UI element"), anchor.applicationName)
        if let bundleIdentifier = anchor.bundleIdentifier {
            applicationDescription += " (\(bundleIdentifier))"
        }
        elementDescriptionLabel.stringValue = anchor.pathDescription + "\n" + applicationDescription

        // Warn the user if the captured element or one of its ancestors shares its identity attributes with a sibling element, because the generated script then depends on the element's ordinal position among its siblings.
        let ambiguousNodes = anchor.nodes.filter({ $0.isAmbiguous })
        if ambiguousNodes.isEmpty {
            warningLabel.stringValue = ""
            warningLabel.isHidden = true
        } else {
            let ambiguousDescriptions = ambiguousNodes.map({ $0.identityDescription }).joined(separator: ", ")
            warningLabel.stringValue = String(format: NSLocalizedString("More than one sibling matches %@, so the script clicks the element by its position among the matching siblings. Moving a window does not affect the script, but adding, removing or reordering siblings does.", comment: "Warning about ambiguous UI elements in a generated click script"), ambiguousDescriptions)
            warningLabel.isHidden = false
        }
    }

    /// Regenerates the script in the current language and displays it.
    private func updateScript() {
        guard let anchor = anchor else {
            scriptTextView.string = ""
            return
        }
        scriptTextView.string = generator.script(for: anchor, language: language)
        scriptTextView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }

    /// Copies the displayed script to the general pasteboard and reports the result in the status label.
    private func copyScriptToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(scriptTextView.string, forType: .string)
        statusLabel.stringValue = NSLocalizedString("Script copied to the clipboard.", comment: "Status text after a generated click script is copied to the clipboard")
    }

    /// Updates the text of the delay label.
    private func updateDelayLabel() {
        delayLabel.stringValue = String(format: NSLocalizedString("Delay before capturing: %d s", comment: "Label of the delay before the button captures the element"), delaySeconds)
    }

    /// Shows or hides the Accessibility permission row and enables or disables the capture button.
    private func updatePermissionState() {
        let isTrusted = AXIsProcessTrusted()
        permissionRow.isHidden = isTrusted
        instructionLabel.stringValue = isTrusted ? NSLocalizedString("Move the mouse pointer over the UI element that you want a script to click, then press Command-Control-Option-C or click Capture Element Under Mouse. The script appears here and is copied to the clipboard.", comment: "Instructions for the main window") : NSLocalizedString("Move the mouse pointer over the UI element that you want a script to click, then press Command-Control-Option-C or click Capture Element Under Mouse. Click Script Maker needs the Accessibility permission before it can read the element under the mouse pointer.", comment: "Instructions for the main window when the Accessibility permission has not been granted")
        captureButton.isEnabled = isTrusted && countdownTimer == nil
    }


    // MARK: - VIEW MANAGEMENT

    /// Creates the views in the window's content view and installs the layout constraints that arrange them.
    private func buildContentView() {
        guard let contentView = window?.contentView else { return }

        // The label that explains how to use the application.
        instructionLabel = NSTextField(wrappingLabelWithString: "")
        instructionLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        instructionLabel.textColor = NSColor.secondaryLabelColor
        instructionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // The explanation of the Accessibility permission and the button that opens the Privacy & Security pane of System Settings. The row is hidden when the permission has been granted.
        permissionLabel = NSTextField(wrappingLabelWithString: NSLocalizedString("Click Script Maker is not authorized to use the accessibility features of macOS. Turn on the checkbox for Click Script Maker in System Settings > Privacy & Security > Accessibility, then return to this window.", comment: "Explanation of the Accessibility permission"))
        permissionLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        permissionLabel.textColor = NSColor.systemOrange
        permissionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let permissionButton = NSButton(title: NSLocalizedString("Open Accessibility Settings…", comment: "Name of the button that opens the Accessibility pane of System Settings"), target: self, action: #selector(openAccessibilitySettings(_:)))
        permissionButton.bezelStyle = .rounded
        permissionRow = NSStackView(views: [permissionLabel, permissionButton])
        permissionRow.orientation = .horizontal
        permissionRow.alignment = .centerY
        permissionRow.spacing = 8

        // The button that captures the element, the label that shows the delay and the stepper that changes it. The button is the default button, so the user can also press Return.
        captureButton = NSButton(title: NSLocalizedString("Capture Element Under Mouse", comment: "Name of the button that captures the element under the mouse pointer"), target: self, action: #selector(startCapture(_:)))
        captureButton.bezelStyle = .rounded
        captureButton.keyEquivalent = "\r"
        delayLabel = NSTextField(labelWithString: "")
        delayLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        delayLabel.textColor = NSColor.secondaryLabelColor
        delayStepper = NSStepper()
        delayStepper.minValue = 0
        delayStepper.maxValue = 10
        delayStepper.increment = 1
        delayStepper.integerValue = delaySeconds
        delayStepper.valueWraps = false
        delayStepper.target = self
        delayStepper.action = #selector(changeDelay(_:))
        updateDelayLabel()
        let captureSpacerView = NSView()
        captureSpacerView.setContentHuggingPriority(NSLayoutConstraint.Priority.defaultLow, for: .horizontal)
        let captureRowStackView = NSStackView(views: [captureButton, delayLabel, delayStepper, captureSpacerView])
        captureRowStackView.orientation = .horizontal
        captureRowStackView.alignment = .centerY
        captureRowStackView.spacing = 8

        // The segmented control that chooses the scripting language of the generated script.
        languageSegmentedControl = NSSegmentedControl(labels: ClickScriptLanguage.allCases.map({ $0.displayName }), trackingMode: .selectOne, target: self, action: #selector(changeLanguage(_:)))
        languageSegmentedControl.selectedSegment = language.rawValue
        let languageSpacerView = NSView()
        languageSpacerView.setContentHuggingPriority(NSLayoutConstraint.Priority.defaultLow, for: .horizontal)
        let languageRowStackView = NSStackView(views: [languageSegmentedControl, languageSpacerView])
        languageRowStackView.orientation = .horizontal
        languageRowStackView.alignment = .centerY
        languageRowStackView.spacing = 8

        // The label that describes the captured element and its application.
        elementDescriptionLabel = NSTextField(wrappingLabelWithString: "")
        elementDescriptionLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        elementDescriptionLabel.textColor = NSColor.secondaryLabelColor
        elementDescriptionLabel.isSelectable = true
        elementDescriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // The label that warns about elements whose identity attributes are shared by sibling elements.
        warningLabel = NSTextField(wrappingLabelWithString: "")
        warningLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        warningLabel.textColor = NSColor.systemOrange
        warningLabel.isSelectable = true
        warningLabel.isHidden = true
        warningLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // The scroll view and its text view display the script. The text view is not editable, but it can be scrolled horizontally because generated scripts contain long lines.
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.setContentHuggingPriority(NSLayoutConstraint.Priority.defaultLow, for: .vertical)
        scrollView.setContentCompressionResistancePriority(NSLayoutConstraint.Priority.defaultLow, for: .vertical)

        scriptTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
        scriptTextView.minSize = NSSize(width: 0, height: 0)
        scriptTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scriptTextView.isVerticallyResizable = true
        scriptTextView.isHorizontallyResizable = true
        scriptTextView.autoresizingMask = [.width]
        scriptTextView.isEditable = false
        scriptTextView.isSelectable = true
        scriptTextView.isRichText = false
        scriptTextView.usesFindBar = true
        scriptTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        scriptTextView.isAutomaticQuoteSubstitutionEnabled = false
        scriptTextView.isAutomaticDashSubstitutionEnabled = false
        scriptTextView.isAutomaticTextReplacementEnabled = false
        scriptTextView.isAutomaticSpellingCorrectionEnabled = false
        scriptTextView.textContainerInset = NSSize(width: 4, height: 6)
        scriptTextView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scriptTextView.textContainer?.widthTracksTextView = false
        scrollView.documentView = scriptTextView

        // The status label and the buttons that copy or save the script. The status label reports the result of the last operation, such as the copy of the script to the clipboard.
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority.defaultLow, for: .horizontal)
        let copyButton = NSButton(title: NSLocalizedString("Copy Script", comment: "Name of the button that copies a generated click script to the clipboard"), target: self, action: #selector(copyScript(_:)))
        copyButton.bezelStyle = .rounded
        let saveButton = NSButton(title: NSLocalizedString("Save Script…", comment: "Name of the button that saves a generated click script to a file"), target: self, action: #selector(saveScript(_:)))
        saveButton.bezelStyle = .rounded
        let buttonRowSpacerView = NSView()
        buttonRowSpacerView.setContentHuggingPriority(NSLayoutConstraint.Priority.defaultLow, for: .horizontal)
        buttonRowSpacerView.setContentCompressionResistancePriority(NSLayoutConstraint.Priority.defaultLow, for: .horizontal)
        let buttonRowStackView = NSStackView(views: [statusLabel, buttonRowSpacerView, copyButton, saveButton])
        buttonRowStackView.orientation = .horizontal
        buttonRowStackView.alignment = .centerY
        buttonRowStackView.spacing = 8

        // The label that reminds the user of the hot key.
        let hintLabel = NSTextField(wrappingLabelWithString: NSLocalizedString("Command-Control-Option-C captures the element under the mouse pointer even while another application is active.", comment: "Reminder of the capture hot key"))
        hintLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        hintLabel.textColor = NSColor.tertiaryLabelColor
        hintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Arrange the views from top to bottom. The scroll view absorbs the extra height when the user resizes the window, and hidden views such as the warning label and the permission row are removed from the layout. Each row is given the full width of the stack view explicitly, because a stack view's alignment alone does not stretch every type of view to the full width.
        let rowViews: [NSView] = [instructionLabel, permissionRow, captureRowStackView, languageRowStackView, elementDescriptionLabel, warningLabel, scrollView, buttonRowStackView, hintLabel]
        let stackView = NSStackView(views: rowViews)
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.distribution = .fill
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)
        var constraints: [NSLayoutConstraint] = [
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ]
        for rowView in rowViews {
            constraints.append(rowView.widthAnchor.constraint(equalTo: stackView.widthAnchor))
        }
        NSLayoutConstraint.activate(constraints)
    }

    // MARK: - ACTION METHODS

    /// Changes the scripting language of the displayed script when the user chooses a segment of the segmented control, and copies the new script to the clipboard.
    @objc private func changeLanguage(_ sender: NSSegmentedControl) {
        language = ClickScriptLanguage(rawValue: sender.selectedSegment) ?? .appleScript
        guard anchor != nil else { return }
        updateScript()
        copyScriptToPasteboard()
    }

    /// Changes the number of seconds that the capture button waits before it captures the element.
    @objc private func changeDelay(_ sender: NSStepper) {
        delaySeconds = min(max(sender.integerValue, 0), 10)
        updateDelayLabel()
    }

    /// Copies the displayed script to the general pasteboard.
    @objc private func copyScript(_ sender: Any?) {
        guard !scriptTextView.string.isEmpty else { return }
        copyScriptToPasteboard()
    }

    /// Saves the displayed script to a file that the user chooses.
    @objc private func saveScript(_ sender: Any?) {
        guard let window = window else { return }
        let savePanel = NSSavePanel()
        savePanel.title = NSLocalizedString("Save Click Script", comment: "Title of the save panel for a generated click script")
        savePanel.nameFieldStringValue = NSLocalizedString("Click Script", comment: "Default name of a saved click script") + "." + language.fileExtension
        savePanel.canCreateDirectories = true
        savePanel.beginSheetModal(for: window) { [weak self] response in
            guard response == NSApplication.ModalResponse.OK, let url = savePanel.url, let self = self else { return }
            do {
                try self.scriptTextView.string.write(to: url, atomically: true, encoding: String.Encoding.utf8)
                self.statusLabel.stringValue = String(format: NSLocalizedString("Script saved to %@.", comment: "Status text after a generated click script is saved"), url.lastPathComponent)
            } catch {
                self.presentSaveError(error)
            }
        }
    }

    /// Opens the Accessibility pane of the Privacy & Security pane of System Settings so that the user can grant the Accessibility permission.
    @objc private func openAccessibilitySettings(_ sender: Any?) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - ACCESSIBILITY PERMISSION

    /**
     Asks macOS to show the Accessibility permission prompt if the application has not been granted the permission.

     macOS shows the prompt only once for each copy of the application, so the window also contains a button that opens the Accessibility pane of System Settings.
     */
    func promptForAccessibilityIfNeeded() {
        updatePermissionState()
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Updates the window when the user returns to the application, as after granting the Accessibility permission in System Settings.
    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        updatePermissionState()
    }

    // MARK: - ALERTS

    /// Presents an alert that describes why a click script could not be generated.
    private func presentAlert(for error: ElementLocatorError) {
        let alert = NSAlert()
        alert.alertStyle = NSAlert.Style.warning
        alert.messageText = NSLocalizedString("Couldn't generate the click script", comment: "Alert message text for failed to generate a click script")
        let failureReason = error.errorDescription ?? ""
        let recoverySuggestion = error.recoverySuggestion ?? ""
        alert.informativeText = failureReason + (recoverySuggestion.isEmpty ? "" : "\n\n" + recoverySuggestion)
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "Name of OK button"))

        // Present the alert as a sheet on the window, or as an application-modal dialog if the window is not available.
        if let window = window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    /// Presents an alert that describes why the script could not be saved.
    private func presentSaveError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = NSAlert.Style.warning
        alert.messageText = NSLocalizedString("Couldn't save the click script", comment: "Alert message text for failed to save a click script")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "Name of OK button"))
        if let window = window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

}
