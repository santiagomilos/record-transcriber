import Testing
@testable import RecordTranscriber

private let helpWithRestricted = """
Usage: claude [options] [command] [prompt]

Options:
  -p, --print                 Print response and exit
      --restricted            Drop the tools that run code
      --strict-mcp-config     Only use MCP servers from --mcp-config
"""

private let helpWithoutRestricted = """
Usage: claude [options] [command] [prompt]

Options:
  -p, --print                 Print response and exit
      --strict-mcp-config     Only use MCP servers from --mcp-config
"""

@Test func isAvailableWhenTheHelpListsRestricted() {
    #expect(SummaryAvailability.evaluate(helpOutput: helpWithRestricted) == .available)
}

@Test func isUnsupportedWhenTheHelpLacksRestricted() {
    #expect(SummaryAvailability.evaluate(helpOutput: helpWithoutRestricted) == .restrictedUnsupported)
}

@Test func doesNotMistakeALongerFlagForRestricted() {
    let help = "      --restricted-mode       Something else"

    #expect(SummaryAvailability.evaluate(helpOutput: help) == .restrictedUnsupported)
}

@Test func isUnverifiableWhenTheHelpCouldNotBeRead() {
    #expect(SummaryAvailability.evaluate(helpOutput: nil) == .helpUnreadable)
}

@Test func explainsEveryReasonSummariesAreUnavailable() {
    #expect(SummaryAvailability.available.reason == nil)
    #expect(SummaryAvailability.checking.reason == nil)
    #expect(SummaryAvailability.claudeMissing.reason
        == "Los resúmenes no están disponibles: no se encontró Claude Code.")
    #expect(SummaryAvailability.restrictedUnsupported.reason
        == "Los resúmenes no están disponibles: esta versión de Claude Code no admite --restricted. Actualízala.")
    #expect(SummaryAvailability.helpUnreadable.reason
        == "No se pudo comprobar la versión de Claude Code (claude --help). Los resúmenes pueden fallar.")
}

@Test func blocksSummariesOnlyWhenTheyKnowinglyCannotWork() {
    #expect(SummaryAvailability.available.allowsSummaries)
    #expect(SummaryAvailability.checking.allowsSummaries)
    #expect(SummaryAvailability.helpUnreadable.allowsSummaries)
    #expect(!SummaryAvailability.claudeMissing.allowsSummaries)
    #expect(!SummaryAvailability.restrictedUnsupported.allowsSummaries)
}
