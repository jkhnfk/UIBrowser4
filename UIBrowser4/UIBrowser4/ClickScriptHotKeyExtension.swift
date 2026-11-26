//
//  ClickScriptHotKeyExtension.swift
//  UIBrowser4
//
//  Created by Bill Cheeseman on 2026-11-26.
//  Copyright © 2026 PFiddlesoft. All rights reserved.
//

import Cocoa
import Carbon.HIToolbox

/**
 The ClickScriptHotKeyExtension.swift file implements UI Browser's Command-Control-Option-C hot key for the Generate Click Script feature.

 The hot key generates a click script for the UI element under the mouse pointer. It must work while another application is active, because the user points the mouse pointer at an element in the user interface of the target application, not at an element in UI Browser's own user interface. A menu item key equivalent only works while UI Browser itself is active, so the hot key is registered with the Carbon Event Manager's `RegisterEventHotKey(_:_:_:_:_:_:)` function instead, which delivers the hot key event to UI Browser no matter which application is active. Registration consumes the keyboard event, so the target application never sees it, and it does not require the assistance of the accessibility API.

 `ClickScriptHotKey` is the singleton that owns the Carbon hot key and its event handler. `MasterSplitItemViewController` installs the hot key in its `viewDidLoad()` method by calling `installClickScriptHotKey()`, and the hot key calls `showClickScriptForElementUnderMouse()` in *ClickScriptButtonExtension.swift*, the same method that the *Click Script for Element Under Mouse* menu item calls.
 */
private final class ClickScriptHotKey {

    // MARK: - PROPERTIES

    /// The singleton that registers the hot key and handles its events.
    static let sharedInstance = ClickScriptHotKey()

    /// The four-character code 'UIB4' that identifies UI Browser's hot keys in Carbon events.
    static let signature: OSType = 0x55494234

    /// The identifier of the click script hot key. UI Browser registers only one hot key, but Carbon identifies each registered hot key by a signature and an identifier.
    static let clickScriptHotKeyIdentifier: UInt32 = 1

    /// The Carbon hot key reference, or `nil` if the hot key is not registered.
    private var hotKeyReference: EventHotKeyRef?

    /// The Carbon event handler reference, or `nil` if the event handler is not installed.
    private var eventHandlerReference: EventHandlerRef?

    /// The closure to call when the user presses the hot key.
    private var action: (() -> Void)?

    // MARK: - INITIALIZATION

    private init() {}

    deinit {
        uninstall()
    }

    /**
     Registers the Command-Control-Option-C hot key and installs the event handler that calls the specified closure when the user presses it.

     The method does nothing if the hot key is already registered, and it replaces the closure if the hot key is registered again.

     - parameter action: The closure to call when the user presses the hot key.
     */
    func install(action: @escaping () -> Void) {
        self.action = action
        guard hotKeyReference == nil else { return }

        // Install the event handler before registering the hot key so that the hot key can never be pressed without a handler to receive it. The event handler's userData parameter passes an unretained pointer to this singleton, which the C callback converts back to the Swift object because a C function pointer cannot capture the object itself.
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { (callReference, event, userData) -> OSStatus in
            // The event handler is called for every hot key event delivered to UI Browser. It compares the event's hot key identifier with the identifier of the click script hot key, so that a hot key added to UI Browser in the future does not trigger the click script.
            guard let userData = userData, let event = event else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<ClickScriptHotKey>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyIdentifier = EventHotKeyID()
            let parameterStatus = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyIdentifier)
            guard parameterStatus == noErr, hotKeyIdentifier.signature == ClickScriptHotKey.signature, hotKeyIdentifier.id == ClickScriptHotKey.clickScriptHotKeyIdentifier else {
                return OSStatus(eventNotHandledErr)
            }
            hotKey.performAction()
            return noErr
        }, 1, &eventType, userData, &eventHandlerReference)
        guard handlerStatus == noErr else {
            NSLog("UI Browser could not install the event handler for the click script hot key (error \(handlerStatus)).")
            return
        }

        // Register Command-Control-Option-C. The Carbon virtual key code for the letter C is kVK_ANSI_C, which identifies the key by its position on the keyboard rather than by the character that the current keyboard layout produces. The modifiers are the Carbon equivalents of the NSEvent.ModifierFlags values.
        let hotKeyIdentifier = EventHotKeyID(signature: ClickScriptHotKey.signature, id: ClickScriptHotKey.clickScriptHotKeyIdentifier)
        let modifiers = UInt32(cmdKey | optionKey | controlKey)
        let registrationStatus = RegisterEventHotKey(UInt32(kVK_ANSI_C), modifiers, hotKeyIdentifier, GetApplicationEventTarget(), 0, &hotKeyReference)
        guard registrationStatus == noErr else {
            NSLog("UI Browser could not register the Command-Control-Option-C click script hot key (error \(registrationStatus)).")
            uninstall()
            return
        }
    }

    /// Unregisters the hot key and removes its event handler.
    func uninstall() {
        if let hotKeyReference = hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
        if let eventHandlerReference = eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
        action = nil
    }

    // MARK: - EVENT HANDLING

    /// Calls the closure that the client passed to `install(action:)`.
    fileprivate func performAction() {
        action?()
    }

}

extension MasterSplitItemViewController {

    // MARK: - HOT KEY

    /**
     Registers the Command-Control-Option-C hot key that generates a click script for the UI element under the mouse pointer.

     The hot key is registered only once even if this method is called more than once. It is called from `viewDidLoad()` so that the hot key is installed as soon as UI Browser's main window has been loaded.
     */
    func installClickScriptHotKey() {
        ClickScriptHotKey.sharedInstance.install { [weak self] in
            guard let self = self else { return }
            self.showClickScriptForElementUnderMouse()
        }
    }

    /// Unregisters the Command-Control-Option-C hot key.
    func removeClickScriptHotKey() {
        ClickScriptHotKey.sharedInstance.uninstall()
    }

}
