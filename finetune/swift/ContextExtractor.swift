// ContextExtractor.swift
// SuperPaste local-model context extractor (spec + working sketch).
//
// Produces the <context> block defined in SCHEMA.md. This MUST stay in
// lockstep with generate_dataset.py: same field order, same truncation,
// same reading order. Treat SCHEMA.md as the contract between the Swift
// runtime and the Python training pipeline.
//
// Replaces the screenshot upload path when "Local model" is enabled:
// the screenshot goes to Vision OCR on-device and is never written to disk.

import AppKit
import Vision
import ApplicationServices

struct WindowContext {
    var app: String
    var window: String
    var focusedField: String
    var fieldPlaceholder: String
    var fieldContent: String
    var selectedText: String
    var screenText: String

    /// Serialization consumed by the SLM. Field order is load-bearing.
    var prompt: String {
        """
        <context>
        app: \(app)
        window: \(window)
        focused_field: \(focusedField)
        field_placeholder: \(fieldPlaceholder)
        field_content: \(fieldContent.isEmpty ? "(empty)" : fieldContent)
        selected_text: \(selectedText.isEmpty ? "(none)" : selectedText)
        screen_text:
        \(screenText)
        [cursor is in the \(focusedField)]
        </context>
        """
    }
}

enum ContextExtractor {

    static let maxScreenTextChars = 3000
    static let maxFieldContentChars = 1000

    /// Entry point: call with the CGImage you already capture on Option+V.
    static func extract(from screenshot: CGImage, completion: @escaping (WindowContext) -> Void) {
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        let ax = accessibilitySnapshot()

        recognizeText(in: screenshot) { screenText in
            completion(WindowContext(
                app: app,
                window: ax.windowTitle,
                focusedField: ax.focusedFieldDescription,
                fieldPlaceholder: ax.placeholder,
                fieldContent: ax.fieldContent,
                selectedText: ax.selectedText,
                screenText: screenText
            ))
        }
    }

    // MARK: - Vision OCR

    private static func recognizeText(in image: CGImage, completion: @escaping (String) -> Void) {
        let request = VNRecognizeTextRequest { req, _ in
            let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
            // Reading order: sort by top-to-bottom, then left-to-right.
            // Vision's normalized coords have origin bottom-left, so invert Y.
            let lines = observations
                .compactMap { obs -> (y: CGFloat, x: CGFloat, text: String)? in
                    guard let top = obs.topCandidates(1).first else { return nil }
                    return (1 - obs.boundingBox.midY, obs.boundingBox.minX, top.string)
                }
                .sorted { a, b in
                    // Group into rows with a small vertical tolerance
                    abs(a.y - b.y) > 0.012 ? a.y < b.y : a.x < b.x
                }
                .map(\.text)

            var text = lines.joined(separator: "\n")
            // Truncate from the TOP: bottom-of-window content is most recent
            // in chats/terminals and matters most. Mirror of training rule.
            if text.count > maxScreenTextChars {
                text = "…" + String(text.suffix(maxScreenTextChars))
            }
            completion(text)
        }
        request.recognitionLevel = .accurate       // .fast if latency budget demands
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        DispatchQueue.global(qos: .userInitiated).async {
            try? VNImageRequestHandler(cgImage: image).perform([request])
        }
    }

    // MARK: - Accessibility snapshot

    private struct AXSnapshot {
        var windowTitle = ""
        var focusedFieldDescription = "text field"
        var placeholder = ""
        var fieldContent = ""
        var selectedText = ""
    }

    private static func accessibilitySnapshot() -> AXSnapshot {
        var snap = AXSnapshot()
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return snap }
        let appEl = AXUIElementCreateApplication(pid)

        var winRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
           let win = winRef, CFGetTypeID(win) == AXUIElementGetTypeID() {
            snap.windowTitle = stringAttr(win as! AXUIElement, kAXTitleAttribute) ?? ""
        }

        var focusRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &focusRef) == .success,
           let focusAny = focusRef, CFGetTypeID(focusAny) == AXUIElementGetTypeID() {
            let focus = focusAny as! AXUIElement
            let role = stringAttr(focus, kAXRoleDescriptionAttribute)
                ?? stringAttr(focus, kAXRoleAttribute) ?? "text field"
            let label = stringAttr(focus, kAXDescriptionAttribute)
                ?? stringAttr(focus, kAXTitleAttribute)
            snap.focusedFieldDescription = label.map { "\($0) (\(role))" } ?? role
            snap.placeholder = stringAttr(focus, kAXPlaceholderValueAttribute) ?? ""
            // Draft already typed in the field. Password fields report a
            // secure role; never read those.
            let role = stringAttr(focus, kAXRoleAttribute) ?? ""
            if role != (kAXSecureTextFieldRole as String) {
                var content = stringAttr(focus, kAXValueAttribute) ?? ""
                if content.count > maxFieldContentChars {
                    content = "…" + String(content.suffix(maxFieldContentChars))
                }
                snap.fieldContent = content
            }
            snap.selectedText = stringAttr(focus, kAXSelectedTextAttribute) ?? ""
        }
        return snap
    }

    private static func stringAttr(_ el: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
}
