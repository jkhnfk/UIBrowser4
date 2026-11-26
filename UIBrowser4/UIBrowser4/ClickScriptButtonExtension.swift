//
//  ClickScriptButtonExtension.swift
//  UIBrowser4
//
//  Created by Bill Cheeseman on 2026-11-26.
//  Copyright © 2026 PFiddlesoft. All rights reserved.
//

import Cocoa
import PFAssistiveFramework4

/**
 The ClickScriptButtonExtension.swift file implements an extension on MasterSplitItemViewController dedicated to UI Browser's Generate Click Script feature.

 The feature captures the identity of a UI element and generates AppleScript and JavaScript for Automation (JXA) scripts that click the element through the System Events application. The generated scripts locate the element by its accessibility attributes instead of its screen coordinates, so they continue to work after the element's window is moved or resized.

 Two action methods generate a click script. `generateClickScriptForElementUnderMouse(_:)` is connected from the AppleScript menu's *Click Script for Element Under Mouse* menu item to First Responder in *Main.storyboard*, and it is also called by the Command-Control-Option-C hot key registered in *ClickScriptHotKeyExtension.swift*. `generateClickScriptForSelectedElement(_:)` is connected from the AppleScript menu's *Click Script for Selected Element* menu item and captures the element that the user has selected in UI Browser.

 The extension uses `ElementLocator` to capture the element's identity and `ClickScriptGenerator` to build the script. `ClickScriptWindowController` displays the script in a window where the user can copy or save it.
 */
extension MasterSplitItemViewController {

    // MARK: - ACTION METHODS

    /**
     Generates a click script for the UI element under the mouse pointer.

     - note: The equivalent UI Browser 2 method is `-[PFBrowserController clickScriptForElementUnderMouseAction:]`.

     - parameter sender: The menu item that sent the action.
     */
    @IBAction func generateClickScriptForElementUnderMouse(_ sender: NSMenuItem) {
        // Action method connected from the AppleScript > Click Script for Element Under Mouse menu item to First Responder in Main.storyboard.
        showClickScriptForElementUnderMouse()
    }

    /**
     Generates a click script for the UI element that the user has selected in UI Browser.

     - parameter sender: The menu item that sent the action.
     */
    @IBAction func generateClickScriptForSelectedElement(_ sender: NSMenuItem) {
        // Action method connected from the AppleScript > Click Script for Selected Element menu item to First Responder in Main.storyboard.
        showClickScriptForSelectedElement()
    }

    // MARK: - GENERATION

    /// Captures the element under the mouse pointer and displays the generated click script, or presents an alert describing why the element could not be captured. Called by the action method for the menu item and by the hot key handler.
    func showClickScriptForElementUnderMouse() {
        do {
            let anchor = try ElementLocator.sharedInstance.anchorAtMouseLocation()
            showClickScript(for: anchor)
        } catch let error as ElementLocatorError {
            presentClickScriptAlert(for: error)
        } catch {
            presentClickScriptAlert(for: .noElementAtMouseLocation)
        }
    }

    /// Captures the element that the user has selected in UI Browser and displays the generated click script, or presents an alert describing why the element could not be captured.
    func showClickScriptForSelectedElement() {
        guard let element = ElementDataModel.sharedInstance.currentElement else {
            presentClickScriptAlert(for: .noSelectedElement)
            return
        }
        do {
            let anchor = try ElementLocator.sharedInstance.anchor(forAccessibilityElement: element.axElement)
            showClickScript(for: anchor)
        } catch let error as ElementLocatorError {
            presentClickScriptAlert(for: error)
        } catch {
            presentClickScriptAlert(for: .notInAccessibilityHierarchy)
        }
    }

    /// Displays the window that contains the script generated for the specified anchor.
    private func showClickScript(for anchor: ElementAnchor) {
        ClickScriptWindowController.sharedInstance.showClickScript(for: anchor)
        // Show the description of the element to VoiceOver users and other users of assistive technology, because the window opens without the user having clicked anything in it.
        NSAccessibility.post(element: ClickScriptWindowController.sharedInstance.window!, notification: .focusedWindowChanged)
    }

    // MARK: - ALERTS

    /// Presents an alert that describes why a click script could not be generated.
    private func presentClickScriptAlert(for error: ElementLocatorError) {
        let alert = NSAlert()
        alert.alertStyle = NSAlert.Style.warning
        alert.messageText = NSLocalizedString("Couldn't generate the click script", comment: "Alert message text for failed to generate a click script")
        let failureReason = error.errorDescription ?? ""
        let recoverySuggestion = error.recoverySuggestion ?? ""
        alert.informativeText = failureReason + (recoverySuggestion.isEmpty ? "" : "\n\n" + recoverySuggestion)
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "Name of OK button"))

        // Present the alert as a sheet on UI Browser's main window, or as an application-modal dialog if the main window is not available, as when the hot key is used while UI Browser is hidden.
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

}
