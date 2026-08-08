@preconcurrency import KeyboardShortcuts

@MainActor
extension KeyboardShortcuts.Name {
    static let correct = Self("correct", default: .init(.c, modifiers: [.control, .option, .command]))
    static let rewrite = Self("rewrite", default: .init(.k, modifiers: [.control, .option, .command]))
    static let rewriteAlt = Self("rewriteAlt", default: .init(.r, modifiers: [.control, .option, .command]))
    static let formalize = Self("formalize", default: .init(.f, modifiers: [.control, .option, .command]))
    static let simplify = Self("simplify", default: .init(.s, modifiers: [.control, .option, .command]))
    static let summarize = Self("summarize", default: .init(.z, modifiers: [.control, .option, .command]))
    static let custom = Self("custom", default: .init(.p, modifiers: [.control, .option, .command]))
    static let markdown = Self("markdown", default: .init(.m, modifiers: [.control, .option, .command]))
}
