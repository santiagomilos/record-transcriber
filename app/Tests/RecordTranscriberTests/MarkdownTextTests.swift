import AppKit
import Testing
@testable import RecordTranscriber

/// Offsets into the rendered sample: "propuesta" 21–30, "Pendientes" 47–57,
/// "Texto final" 58–69.
private let markdown = """
# Acuerdos

- Enviar la **propuesta**
1. Llamar a Ana

## Pendientes

Texto final
"""

private func font(at location: Int, in rendered: NSAttributedString) -> NSFont? {
    rendered.attribute(.font, at: location, effectiveRange: nil) as? NSFont
}

/// The rendered string is what saved highlights point into, so its exact
/// contents are pinned here.
@Test func rendersTheSummaryAsOneStringOfBlocks() {
    let rendered = MarkdownText.attributedString(markdown: markdown, fontSize: 12)

    #expect(rendered.string == "Acuerdos\n•\tEnviar la propuesta\n1.\tLlamar a Ana\nPendientes\nTexto final")
}

@Test func scalesHeadingsWithTheBodySize() {
    let rendered = MarkdownText.attributedString(markdown: markdown, fontSize: 18)

    #expect(font(at: 0, in: rendered)?.pointSize == 25.5)
    #expect(font(at: 47, in: rendered)?.pointSize == 21)
    #expect(font(at: 58, in: rendered)?.pointSize == 18)
}

@Test func rendersStrongEmphasisInABoldFont() throws {
    let rendered = MarkdownText.attributedString(markdown: markdown, fontSize: 12)

    let bold = try #require(font(at: 21, in: rendered))
    let plain = try #require(font(at: 11, in: rendered))
    #expect(NSFontManager.shared.traits(of: bold).contains(.boldFontMask))
    #expect(!NSFontManager.shared.traits(of: plain).contains(.boldFontMask))
}
