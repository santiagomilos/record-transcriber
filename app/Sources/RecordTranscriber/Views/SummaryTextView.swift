import AppKit
import SwiftUI

/// SummaryTextView shows a summary in an AppKit text view, where the user can
/// select text and mark it from the context menu.
///
/// It is AppKit because the app targets macOS 14.4: a SwiftUI `Text` with text
/// selection enabled never reports what is selected, and a highlight is made
/// on the selected range.
struct SummaryTextView: NSViewRepresentable {
    let markdown: String
    let fontSize: Double
    let highlights: SummaryHighlights
    /// onChange receives the marks after the user adds or removes one. Saving
    /// them is the caller's job.
    let onChange: (SummaryHighlights) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        // The panel's palette is dark whatever the system appearance is, and the
        // scroller and the context menu follow this rather than the palette.
        scrollView.appearance = NSAppearance(named: .darkAqua)
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: Theme.Space.lg, right: 0)

        // TextKit 1 explicitly: the scroll position is kept through the layout
        // manager, and asking a TextKit 2 view for it switches it over anyway.
        let textView = HighlightingTextView(usingTextLayoutManager: false)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: Theme.panelPadding + Theme.Space.sm, height: 0)
        textView.selectedTextAttributes = [.backgroundColor: NSColor(Theme.selection)]
        textView.linkTextAttributes = [
            .foregroundColor: NSColor(Theme.accent),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]

        let coordinator = context.coordinator
        textView.onApply = { [weak textView] color, range in
            guard let textView else { return }
            coordinator.edit { $0.apply(color, to: range, in: textView.string) }
        }
        textView.onRemove = { [weak textView] range in
            guard let textView else { return }
            coordinator.edit { $0.remove(in: range, rendered: textView.string) }
        }

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? HighlightingTextView,
              let storage = textView.textStorage
        else { return }
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        textView.highlights = highlights

        let textChanged = coordinator.markdown != markdown || coordinator.fontSize != fontSize
        guard textChanged || coordinator.highlights != highlights else { return }

        if textChanged {
            // A new size keeps the reader on the line they were reading; a
            // different summary starts from the top.
            let anchor = coordinator.markdown == markdown ? firstVisibleCharacter(in: textView) : nil
            storage.setAttributedString(MarkdownText.attributedString(markdown: markdown,
                                                                      fontSize: fontSize))
            paint(highlights, in: storage)
            scroll(textView, toCharacter: anchor ?? 0)
        } else {
            storage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: storage.length))
            paint(highlights, in: storage)
        }

        coordinator.markdown = markdown
        coordinator.fontSize = fontSize
        coordinator.highlights = highlights
    }

    private func paint(_ highlights: SummaryHighlights, in storage: NSTextStorage) {
        for highlight in highlights.highlights where highlight.end <= storage.length {
            storage.addAttribute(.backgroundColor,
                                 value: NSColor(Theme.highlight(highlight.color)),
                                 range: NSRange(location: highlight.location, length: highlight.length))
        }
    }

    private func firstVisibleCharacter(in textView: NSTextView) -> Int? {
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer,
              textView.textStorage?.length ?? 0 > 0
        else { return nil }
        var point = textView.visibleRect.origin
        point.y -= textView.textContainerInset.height
        let glyph = layoutManager.glyphIndex(for: point, in: container)
        return layoutManager.characterIndexForGlyph(at: glyph)
    }

    private func scroll(_ textView: NSTextView, toCharacter index: Int) {
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer
        else { return }
        layoutManager.ensureLayout(for: container)
        guard index > 0, index < layoutManager.numberOfGlyphs else {
            textView.scroll(.zero)
            return
        }
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: 1),
                                              actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
        textView.scroll(NSPoint(x: 0, y: rect.minY + textView.textContainerInset.height))
    }

    final class Coordinator {
        var markdown: String?
        var fontSize: Double?
        var highlights: SummaryHighlights?
        var onChange: ((SummaryHighlights) -> Void)?

        /// edit changes the marks last handed to the view and reports the result;
        /// the view repaints when they come back through `updateNSView`.
        func edit(_ change: (inout SummaryHighlights) -> Void) {
            guard var updated = highlights else { return }
            change(&updated)
            guard updated != highlights else { return }
            onChange?(updated)
        }
    }
}

/// HighlightingTextView adds the highlighter to the text view's context menu.
final class HighlightingTextView: NSTextView {
    var highlights: SummaryHighlights?
    var onApply: ((HighlightColor, NSRange) -> Void)?
    var onRemove: ((NSRange) -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let selection = selectedRange()
        guard selection.length > 0 else { return menu }

        var items: [NSMenuItem] = []
        let colors = NSMenu()
        for color in HighlightColor.allCases {
            let item = NSMenuItem(title: color.name, action: #selector(applyHighlight(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = color.rawValue
            item.image = swatch(for: color)
            colors.addItem(item)
        }
        let highlight = NSMenuItem(title: "Resaltar", action: nil, keyEquivalent: "")
        highlight.submenu = colors
        items.append(highlight)

        if highlights?.touches(selection) == true {
            let remove = NSMenuItem(title: "Quitar resaltado", action: #selector(removeHighlight(_:)),
                                    keyEquivalent: "")
            remove.target = self
            items.append(remove)
        }
        items.append(.separator())

        for (index, item) in items.enumerated() {
            menu.insertItem(item, at: index)
        }
        return menu
    }

    @objc private func applyHighlight(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let color = HighlightColor(rawValue: raw)
        else { return }
        onApply?(color, selectedRange())
    }

    @objc private func removeHighlight(_ sender: NSMenuItem) {
        onRemove?(selectedRange())
    }

    /// swatch draws the color at full opacity: the translucent ink the text
    /// sits on is too faint to tell apart at menu-icon size.
    private func swatch(for color: HighlightColor) -> NSImage {
        let fill = NSColor(Theme.highlight(color)).withAlphaComponent(1)
        return NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            fill.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }
}
