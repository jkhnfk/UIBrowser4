//
//  ClickScriptMakerAppDelegate.swift
//  ClickScriptMaker
//
//  Created by Bill Cheeseman on 2026-11-26.
//  Copyright © 2026 PFiddlesoft. All rights reserved.
//

import Cocoa

/**
 The ClickScriptMakerAppDelegate.swift file creates the application's menu bar and its only window, and it installs the Command-Control-Option-C hot key.

 The menu bar is created in code because the application has no main nib file. The Edit menu is needed by the script text view, which supports the standard Cut, Copy, Paste and Select All commands through the responder chain.
 */
final class ClickScriptMakerAppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - APPLICATION LIFETIME

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()

        // Install the hot key before showing the window so that the user can capture an element while another application is active. The hot key calls the same method as the Capture Element Under Mouse button.
        CaptureHotKey.sharedInstance.install {
            CaptureWindowController.sharedInstance.captureElementUnderMouse()
        }

        CaptureWindowController.sharedInstance.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Ask for the Accessibility permission the first time the application runs. The permission is required by the accessibility API function that returns the UI element at a screen location.
        CaptureWindowController.sharedInstance.promptForAccessibilityIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // The application does not quit when the user closes its window, because the Command-Control-Option-C hot key and the Dock icon must continue to work. The user quits the application explicitly with the Quit menu item.
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Clicking the Dock icon reopens the window after the user has closed it.
        if !flag {
            CaptureWindowController.sharedInstance.showWindow(nil)
        }
        return true
    }

    /// Shows the application's window. The method is called by the Click Script Maker item in the Window menu.
    @objc func showCaptureWindow(_ sender: Any?) {
        CaptureWindowController.sharedInstance.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Captures the element under the mouse pointer. The method is called by the Capture Element Under Mouse item in the Window menu.
    @objc func captureElementUnderMouse(_ sender: Any?) {
        CaptureWindowController.sharedInstance.captureElementUnderMouse()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        // The application does not restore any state, but AppKit requires this declaration to enable secure coding for the state that it saves.
        return true
    }

    // MARK: - MENUS

    /// Builds the application's menu bar.
    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // The application menu. Its title is replaced by the application's name when the menu bar is displayed.
        let applicationMenuItem = NSMenuItem()
        mainMenu.addItem(applicationMenuItem)
        let applicationMenu = NSMenu()
        applicationMenuItem.submenu = applicationMenu
        applicationMenu.addItem(withTitle: NSLocalizedString("About Click Script Maker", comment: "Name of the About menu item"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        applicationMenu.addItem(NSMenuItem.separator())
        applicationMenu.addItem(withTitle: NSLocalizedString("Hide Click Script Maker", comment: "Name of the Hide menu item"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = applicationMenu.addItem(withTitle: NSLocalizedString("Hide Others", comment: "Name of the Hide Others menu item"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        applicationMenu.addItem(withTitle: NSLocalizedString("Show All", comment: "Name of the Show All menu item"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        applicationMenu.addItem(NSMenuItem.separator())
        applicationMenu.addItem(withTitle: NSLocalizedString("Quit Click Script Maker", comment: "Name of the Quit menu item"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // The Edit menu, which the script text view uses for copying a portion of a script.
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: NSLocalizedString("Edit", comment: "Name of the Edit menu"))
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: NSLocalizedString("Cut", comment: "Name of the Cut menu item"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: NSLocalizedString("Copy", comment: "Name of the Copy menu item"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: NSLocalizedString("Paste", comment: "Name of the Paste menu item"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: NSLocalizedString("Select All", comment: "Name of the Select All menu item"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // The Window menu.
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: NSLocalizedString("Window", comment: "Name of the Window menu"))
        windowMenuItem.submenu = windowMenu
        let showWindowItem = windowMenu.addItem(withTitle: NSLocalizedString("Click Script Maker", comment: "Name of the menu item that shows the application's window"), action: #selector(showCaptureWindow(_:)), keyEquivalent: "0")
        showWindowItem.target = self
        let captureItem = windowMenu.addItem(withTitle: NSLocalizedString("Capture Element Under Mouse", comment: "Name of the menu item that captures the element under the mouse pointer"), action: #selector(captureElementUnderMouse(_:)), keyEquivalent: "")
        captureItem.target = self
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: NSLocalizedString("Minimize", comment: "Name of the Minimize menu item"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: NSLocalizedString("Close", comment: "Name of the Close menu item"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApplication.shared.windowsMenu = windowMenu

        NSApplication.shared.mainMenu = mainMenu
    }

}
