import Foundation

/// Conta alterações perceptíveis entre dois textos, aproximando o contador
/// exibido pelas Ferramentas de Escrita. Uma troca de palavra vale uma
/// alteração; inserções e remoções também valem uma cada.
public enum TextChangeCounter {
    public static func count(from original: String, to revised: String) -> Int {
        let before = tokens(in: original)
        let after = tokens(in: revised)

        guard before != after else { return 0 }
        guard !before.isEmpty else { return after.count }
        guard !after.isEmpty else { return before.count }

        // Distância de Levenshtein com apenas duas linhas para não multiplicar
        // o uso de memória em textos longos.
        var previous = Array(0...after.count)
        var current = Array(repeating: 0, count: after.count + 1)

        for (row, source) in before.enumerated() {
            current[0] = row + 1
            for (column, destination) in after.enumerated() {
                let replacement = previous[column] + (source == destination ? 0 : 1)
                let deletion = previous[column + 1] + 1
                let insertion = current[column] + 1
                current[column + 1] = min(replacement, deletion, insertion)
            }
            swap(&previous, &current)
        }

        return previous[after.count]
    }

    private static func tokens(in text: String) -> [String] {
        let pattern = #"[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)?|[^\p{L}\p{N}\s]"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return text.split(whereSeparator: \Character.isWhitespace).map(String.init)
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }
}
