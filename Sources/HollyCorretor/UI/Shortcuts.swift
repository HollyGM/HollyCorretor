@preconcurrency import KeyboardShortcuts

@MainActor
extension KeyboardShortcuts.Name {
    static let correct = Self("correct", initial: .init(.c, modifiers: [.control, .option, .command]))
    static let rewrite = Self("rewrite", initial: .init(.k, modifiers: [.control, .option, .command]))
    static let rewriteAlt = Self("rewriteAlt", initial: .init(.r, modifiers: [.control, .option, .command]))
    static let formalize = Self("formalize", initial: .init(.f, modifiers: [.control, .option, .command]))
    static let simplify = Self("simplify", initial: .init(.s, modifiers: [.control, .option, .command]))
    static let summarize = Self("summarize", initial: .init(.z, modifiers: [.control, .option, .command]))
    static let custom = Self("custom", initial: .init(.p, modifiers: [.control, .option, .command]))
    static let markdown = Self("markdown", initial: .init(.m, modifiers: [.control, .option, .command]))
}
