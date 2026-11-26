//
//  ElementLocator.swift
//  UIBrowser4
//
//  Created by Bill Cheeseman on 2026-11-26.
//  Copyright © 2026 PFiddlesoft. All rights reserved.
//

import Cocoa

/**
 The ElementLocator.swift file implements the capture of a UI element's identity independently of its screen position.

 UI Browser's Generate Click Script feature produces AppleScript and JavaScript (JXA) statements that click a UI element. A script that clicks a UI element by referencing the element's screen coordinates breaks as soon as the window is moved, resized, or restored to a different position. The scripts generated here instead locate the element by its accessibility attributes--role, subrole, title, accessibility description, identifier, help, placeholder value and, for static text, value--and by its ordinal among the matching siblings in the accessibility hierarchy.

 `ElementAnchor` is a value-type model of the captured identity: the owning application's name and bundle identifier, and an array of `ElementAnchor.Node` values representing the ancestor chain from the element's outermost ancestor (usually a window, but a menu bar, sheet or pop over for elements in those containers) down to the element itself.

 `ElementLocator` is a singleton that captures the anchor in two ways: for the UI element under the mouse pointer, using the `AXUIElementCopyElementAtPosition(_:_:_:_:)` function with the system-wide accessibility element, and for an accessibility element that the caller has already obtained, using `anchor(forAccessibilityElement:)`. UI Browser, for example, calls the second method with the element that the user has selected in the browser, outline or list view.

The file depends only on Cocoa and the accessibility API, so that the same source file can be compiled into both UI Browser and the standalone Click Script Maker application.

 The capture code works directly with `AXUIElement` objects instead of `AccessibleElement` objects for the elements in the ancestor chain and their siblings, because it does not need to observe the destruction of these temporary objects, and because capturing a single anchor may visit dozens of sibling elements of which only a few are wrapped in `AccessibleElement` objects by the data model.
 */
struct ElementAnchor {

    /// The accessibility attributes of one element in the ancestor chain of the element to be clicked.
    struct Node {

        /// Roles whose `AXValue` attribute contains textual content that identifies the element, such as the displayed string of a static text element.
        static let rolesWithIdentifyingValue: Set<String> = ["AXStaticText", "AXHeading", "AXLink"]

        /// The element's accessibility role, e.g. `AXButton`.
        var role: String

        /// The element's accessibility subrole, e.g. `AXStandardWindow`.
        var subrole: String?

        /// The element's title attribute, e.g. "Reload this page".
        var title: String?

        /// The element's `AXDescription` attribute.
        var accessibilityDescription: String?

        /// The element's `AXIdentifier` attribute.
        var identifier: String?

        /// The element's `AXHelp` attribute.
        var help: String?

        /// The element's `AXPlaceholderValue` attribute, which identifies text fields that have no title.
        var placeholder: String?

        /// The element's `AXValue` attribute, captured only for the roles in `rolesWithIdentifyingValue` because the value of most elements changes as the user works.
        var value: String?

        /// The number of sibling elements that match every non-`nil` identity attribute above, including this element.
        var matchCount: Int

        /// The zero-based position of this element among the matching siblings. The generated scripts use `matchIndex + 1` as a one-based index.
        var matchIndex: Int

        /// `true` if none of the identity attributes identify the element, so that the generated scripts must fall back on the element's ordinal position among its siblings.
        var hasNoIdentityAttributes: Bool {
            return subrole == nil && title == nil && accessibilityDescription == nil && identifier == nil && help == nil && placeholder == nil && value == nil
        }

        /// `true` if more than one sibling element shares the element's identity attributes.
        var isAmbiguous: Bool {
            return matchCount > 1
        }

        /// The AppleScript class name used by System Events for the element's role, e.g. "button", or the raw accessibility role for roles that System Events does not implement.
        var roleName: String {
            return AppleScriptRoleNames.shared.name(forRole: role)
        }

        /// The accessibility attributes that identify the element and their expected values, used by `ClickScriptGenerator` to generate the statements that find the element. The role is always included, and the remaining attributes are included only when they have a value.
        var identityCriteria: [(attributeName: String, value: String)] {
            var criteria: [(attributeName: String, value: String)] = [(kAXRoleAttribute, role)]
            if let subrole = subrole {
                criteria.append((kAXSubroleAttribute, subrole))
            }
            if let title = title {
                criteria.append((kAXTitleAttribute, title))
            }
            if let identifier = identifier {
                criteria.append((kAXIdentifierAttribute, identifier))
            }
            if let accessibilityDescription = accessibilityDescription {
                criteria.append((kAXDescriptionAttribute, accessibilityDescription))
            }
            if let placeholder = placeholder {
                criteria.append((kAXPlaceholderValueAttribute, placeholder))
            }
            if let help = help {
                criteria.append((kAXHelpAttribute, help))
            }
            if let value = value {
                criteria.append((kAXValueAttribute, value))
            }
            return criteria
        }

        /// A short, human-readable description of the element, e.g. `button "Reload this page"`.
        var identityDescription: String {
            let name = roleName
            if let title = title, !title.isEmpty {
                return "\(name) \"\(title)\""
            }
            if let accessibilityDescription = accessibilityDescription, !accessibilityDescription.isEmpty {
                return "\(name) with accessibility description \"\(accessibilityDescription)\""
            }
            if let identifier = identifier, !identifier.isEmpty {
                return "\(name) with identifier \"\(identifier)\""
            }
            if let placeholder = placeholder, !placeholder.isEmpty {
                return "\(name) with placeholder \"\(placeholder)\""
            }
            if let help = help, !help.isEmpty {
                return "\(name) with help \"\(help)\""
            }
            if let value = value, !value.isEmpty {
                return "\(name) with value \"\(value)\""
            }
            return "\(name) number \(matchIndex + 1)"
        }

    }

    /// The user-visible name of the application or other process that owns the element, e.g. "Safari".
    var applicationName: String

    /// The bundle identifier of the application that owns the element, e.g. "com.apple.Safari", or `nil` for processes that were not launched from an application file.
    var bundleIdentifier: String?

    /// The process identifier of the application or other process that owns the element.
    var processIdentifier: pid_t

    /// The ancestor chain of the element to be clicked, from the outermost ancestor to the element itself.
    var nodes: [Node]

    /// The element to be clicked, which is the last element of the ancestor chain.
    var target: Node {
        return nodes[nodes.count - 1]
    }

    /// A short, human-readable description of the element to be clicked, e.g. `button "Reload this page"`.
    var targetDescription: String {
        return target.identityDescription
    }

    /// A human-readable description of the ancestor chain, e.g. `window "Documents" > group "Toolbar" > button "Reload this page"`.
    var pathDescription: String {
        return nodes.map({ $0.identityDescription }).joined(separator: " > ")
    }

}

/**
 Errors reported by `ElementLocator` when it cannot capture the identity of a UI element.
 */
enum ElementLocatorError: Error, LocalizedError {

    /// UI Browser has not been granted access to the accessibility API.
    case accessibilityNotEnabled

    /// The user has not selected a UI element in UI Browser.
    case noSelectedElement

    /// The accessibility API reported no element at the mouse location.
    case noElementAtMouseLocation

    /// The `AXUIElementCopyElementAtPosition(_:_:_:_:)` function failed.
    case elementAtPositionFailed(AXError)

    /// The ancestor chain of the element does not end at an application element.
    case notInAccessibilityHierarchy

    /// The process that owns the element cannot be identified.
    case applicationUnavailable

    /// The element is the application element itself, which cannot be clicked.
    case elementIsApplication

    /// An element in the ancestor chain has no accessibility role.
    case missingRole

    var errorDescription: String? {
        switch self {
        case .accessibilityNotEnabled:
            return "This application is not authorized to use the accessibility features of macOS."
        case .noSelectedElement:
            return "No UI element is selected in UI Browser."
        case .noElementAtMouseLocation:
            return "No accessible UI element was found under the mouse pointer."
        case .elementAtPositionFailed(let error):
            return "The accessibility API could not determine the UI element under the mouse pointer (error \(error.rawValue))."
        case .notInAccessibilityHierarchy:
            return "The UI element is not part of an accessibility hierarchy."
        case .applicationUnavailable:
            return "The application that owns the UI element could not be identified."
        case .elementIsApplication:
            return "The UI element under the mouse pointer is an application, which cannot be clicked."
        case .missingRole:
            return "A UI element in the hierarchy of the element to be clicked has no accessibility role."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .accessibilityNotEnabled:
            return "Turn on the checkbox for this application in the Accessibility list of the Privacy & Security pane of System Settings, then try again."
        case .elementAtPositionFailed(let error):
            if error == .apiDisabled {
                return "Turn on the checkbox for this application in the Accessibility list of the Privacy & Security pane of System Settings, then try again."
            }
            return "Move the mouse pointer over the UI element and try again."
        case .noSelectedElement:
            return "Select a UI element in UI Browser's Browser, Outline or List view, or use the Click Script for Element Under Mouse menu item or the Command-Control-Option-C hot key."
        default:
            return "Move the mouse pointer over the UI element and try again."
        }
    }

}

/**
 A singleton that captures the identity of a UI element independently of its screen position.

 See the documentation of `ElementAnchor` for a discussion of the model and the reason for working directly with accessibility API objects.
 */
final class ElementLocator {

    // MARK: - PROPERTIES

    /// The singleton instance of `ElementLocator`.
    static let sharedInstance = ElementLocator()

    /// The maximum number of elements in an ancestor chain. Accessibility hierarchies are never this deep; the limit simply protects against a cycle in the parent chain.
    private static let maximumHierarchyDepth = 128

    /// The maximum length of an identity attribute value. Longer values are not used to identify elements because they usually contain document content that changes as the user works.
    private static let maximumIdentityLength = 512

    // MARK: - INITIALIZATION

    private init() {}

    // MARK: - CAPTURE

    /// The location of the mouse pointer in the top-left origin coordinate space used by the accessibility API.
    static var mouseLocation: CGPoint {
        // CGEvent's location property uses the global display coordinate space, whose origin is the top-left corner of the main display. NSEvent.mouseLocation uses a bottom-left origin and cannot be passed directly to accessibility API functions.
        return CGEvent(source: nil)?.location ?? .zero
    }

    /**
     Captures the identity of the UI element under the mouse pointer.

     - returns: An `ElementAnchor` describing the element and its ancestor chain.

     - throws: An `ElementLocatorError` if the element cannot be captured.
     */
    func anchorAtMouseLocation() throws -> ElementAnchor {
        return try anchor(forAccessibilityElement: try accessibilityElement(at: ElementLocator.mouseLocation))
    }

    /**
     Captures the identity of a UI element that the caller has already obtained, such as the UI element that the user has selected in UI Browser.

     - parameter element: The `AXUIElement` of the element to capture.

     - returns: An `ElementAnchor` describing the element and its ancestor chain.

     - throws: An `ElementLocatorError` if the element cannot be captured.
     */
    func anchor(forAccessibilityElement element: AXUIElement) throws -> ElementAnchor {
        return try buildAnchor(for: element)
    }

    // MARK: - CAPTURE SUPPORT

    /// Returns the accessibility element under the specified point, or throws an error describing why the element is not available.
    private func accessibilityElement(at point: CGPoint) throws -> AXUIElement {
        guard AXIsProcessTrusted() else {
            throw ElementLocatorError.accessibilityNotEnabled
        }
        let systemWideElement = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(systemWideElement, Float(point.x), Float(point.y), &element)
        guard error == .success else {
            throw ElementLocatorError.elementAtPositionFailed(error)
        }
        guard let accessibleElement = element else {
            throw ElementLocatorError.noElementAtMouseLocation
        }
        return accessibleElement
    }

    /// Builds an anchor for the specified accessibility element by walking its parent chain up to the application element and then describing every element in the chain.
    private func buildAnchor(for element: AXUIElement) throws -> ElementAnchor {
        // Walk up the parent chain until the application element is reached. The chain is stored with the element itself first and the application element last.
        var chain: [AXUIElement] = []
        var currentElement: AXUIElement? = element
        var depth = 0
        while let thisElement = currentElement, depth < ElementLocator.maximumHierarchyDepth {
            chain.append(thisElement)
            if stringAttribute(kAXRoleAttribute, of: thisElement) == kAXApplicationRole {
                break
            }
            currentElement = elementAttribute(kAXParentAttribute, of: thisElement)
            depth += 1
        }
        guard let applicationElement = chain.last, stringAttribute(kAXRoleAttribute, of: applicationElement) == kAXApplicationRole else {
            throw ElementLocatorError.notInAccessibilityHierarchy
        }

        // Collect the elements to be located by the generated scripts, from the outermost ancestor to the element to be clicked.
        let interfaceElements = Array(chain.dropLast().reversed())
        guard !interfaceElements.isEmpty else {
            throw ElementLocatorError.elementIsApplication
        }

        // Identify the application or other process that owns the element.
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(applicationElement, &processIdentifier) == .success, processIdentifier > 0 else {
            throw ElementLocatorError.applicationUnavailable
        }
        let runningApplication = NSRunningApplication(processIdentifier: processIdentifier)
        let applicationName = runningApplication?.localizedName ?? stringAttribute(kAXTitleAttribute, of: applicationElement) ?? String(processIdentifier)

        // Describe every element in the chain. The siblings of each element are the children of its parent in the chain, which is the application element for the outermost ancestor.
        var nodes: [ElementAnchor.Node] = []
        var parentElement = applicationElement
        for interfaceElement in interfaceElements {
            nodes.append(try node(for: interfaceElement, parent: parentElement))
            parentElement = interfaceElement
        }

        return ElementAnchor(applicationName: applicationName, bundleIdentifier: runningApplication?.bundleIdentifier, processIdentifier: processIdentifier, nodes: nodes)
    }

    /// Builds a node for the specified element, counting how many of its siblings have the same identity attributes.
    private func node(for element: AXUIElement, parent: AXUIElement) throws -> ElementAnchor.Node {
        guard let role = stringAttribute(kAXRoleAttribute, of: element) else {
            throw ElementLocatorError.missingRole
        }
        var node = ElementAnchor.Node(
            role: role,
            subrole: identityText(stringAttribute(kAXSubroleAttribute, of: element)),
            title: identityText(stringAttribute(kAXTitleAttribute, of: element)),
            accessibilityDescription: identityText(stringAttribute(kAXDescriptionAttribute, of: element)),
            identifier: identityText(stringAttribute(kAXIdentifierAttribute, of: element)),
            help: identityText(stringAttribute(kAXHelpAttribute, of: element)),
            placeholder: identityText(stringAttribute("AXPlaceholderValue", of: element)),
            value: ElementAnchor.Node.rolesWithIdentifyingValue.contains(role) ? identityText(stringAttribute(kAXValueAttribute, of: element)) : nil,
            matchCount: 1,
            matchIndex: 0)

        // Count the siblings that the generated scripts will match, and find this element's position among them. The generated scripts iterate the children of the parent element and compare only the identity attributes that are not missing value, so the count and index computed here are exactly what the scripts will see.
        var matchCount = 0
        var matchIndex = 0
        for sibling in children(of: parent) where siblingMatchesIdentity(node, sibling) {
            if CFEqual(sibling, element) {
                matchIndex = matchCount
            }
            matchCount += 1
        }
        node.matchCount = max(matchCount, 1)
        node.matchIndex = matchIndex
        return node
    }

    /// Returns `true` if the candidate element has the same identity attributes as the identity element, ignoring attributes that are `nil` in the identity element.
    private func siblingMatchesIdentity(_ identity: ElementAnchor.Node, _ candidate: AXUIElement) -> Bool {
        guard stringAttribute(kAXRoleAttribute, of: candidate) == identity.role else {
            return false
        }
        if let subrole = identity.subrole, identityText(stringAttribute(kAXSubroleAttribute, of: candidate)) != subrole {
            return false
        }
        if let title = identity.title, identityText(stringAttribute(kAXTitleAttribute, of: candidate)) != title {
            return false
        }
        if let accessibilityDescription = identity.accessibilityDescription, identityText(stringAttribute(kAXDescriptionAttribute, of: candidate)) != accessibilityDescription {
            return false
        }
        if let identifier = identity.identifier, identityText(stringAttribute(kAXIdentifierAttribute, of: candidate)) != identifier {
            return false
        }
        if let help = identity.help, identityText(stringAttribute(kAXHelpAttribute, of: candidate)) != help {
            return false
        }
        if let placeholder = identity.placeholder, identityText(stringAttribute("AXPlaceholderValue", of: candidate)) != placeholder {
            return false
        }
        if let value = identity.value, identityText(stringAttribute(kAXValueAttribute, of: candidate)) != value {
            return false
        }
        return true
    }

    // MARK: - ACCESSIBILITY SUPPORT

    /// Returns the string value of the specified attribute of the element, or `nil` if the attribute is not supported or its value is not a string.
    private func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    /// Returns the accessibility element value of the specified attribute of the element, such as the value of `AXParent`.
    private func elementAttribute(_ name: String, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let attributeValue = value else {
            return nil
        }
        guard CFGetTypeID(attributeValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return (attributeValue as! AXUIElement)
    }

    /// Returns the children of the element, in the order used by System Events when it enumerates the element's UI elements.
    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success, let attributeValue = value else {
            return []
        }
        return attributeValue as? [AXUIElement] ?? []
    }

    /// Returns the attribute value as identity text, or `nil` if the value is empty, too long to be a stable identifier, or contains a line break that cannot be embedded in a script string literal.
    private func identityText(_ text: String?) -> String? {
        guard let text = text, !text.isEmpty, text.count <= ElementLocator.maximumIdentityLength else {
            return nil
        }
        guard !text.contains(where: { $0.isNewline }) else {
            return nil
        }
        return text
    }

}

