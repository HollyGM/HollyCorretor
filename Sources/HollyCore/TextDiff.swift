import Foundation

/// Uma palavra ou sinal de pontuação e a posição em que aparece no texto.
struct TextToken: Equatable {
    let text: String
    let range: Range<String.Index>
}

/// Divide um texto nas unidades que se percebem como "uma alteração":
/// palavras (com apóstrofo interno) e sinais de pontuação. Os espaços ficam de
/// fora, porque trocar um espaço por dois não é uma correção que valha
/// destacar nem contar.
enum TextTokenizer {
    static func tokens(in text: String) -> [TextToken] {
        let pattern = #"[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)?|[^\p{L}\p{N}\s]"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return wordsSeparatedByWhitespace(in: text)
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return TextToken(text: String(text[swiftRange]), range: swiftRange)
        }
    }

    private static func wordsSeparatedByWhitespace(in text: String) -> [TextToken] {
        var tokens: [TextToken] = []
        var index = text.startIndex
        while index < text.endIndex {
            if text[index].isWhitespace {
                index = text.index(after: index)
                continue
            }
            var end = index
            while end < text.endIndex, !text[end].isWhitespace {
                end = text.index(after: end)
            }
            tokens.append(TextToken(text: String(text[index..<end]), range: index..<end))
            index = end
        }
        return tokens
    }
}

/// Onde um texto revisado difere do original, em trechos prontos para serem
/// destacados na prévia: o que saiu do original e o que entrou no revisado.
///
/// Os trechos são medidos em palavras e sinais, não em caracteres: "forum"
/// virando "fórum" destaca a palavra inteira, que é como a pessoa a procura.
/// Palavras alteradas em sequência formam um só trecho, com os espaços entre
/// elas, para o destaque não ficar picotado.
public struct TextDiff: Equatable, Sendable {
    /// Trechos do original que foram removidos ou substituídos.
    public let removed: [Range<String.Index>]
    /// Trechos do revisado que foram acrescentados ou que substituem algo.
    public let inserted: [Range<String.Index>]

    public static let none = TextDiff(removed: [], inserted: [])

    public var isEmpty: Bool { removed.isEmpty && inserted.isEmpty }

    /// Acima disto a matriz de alinhamento não compensa. O miolo que difere é
    /// destacado por inteiro nos dois lados, o que continua correto — só menos
    /// preciso — e mantém a prévia instantânea em textos muito longos e muito
    /// reescritos.
    static let maximumAlignmentCells = 1_000_000

    public static func compare(_ original: String, _ revised: String) -> TextDiff {
        let before = TextTokenizer.tokens(in: original)
        let after = TextTokenizer.tokens(in: revised)

        // As bordas iguais saem da comparação, como no contador de alterações:
        // é o que torna barato destacar poucas palavras num documento longo.
        var start = 0
        var beforeEnd = before.count
        var afterEnd = after.count
        while start < beforeEnd, start < afterEnd,
              before[start].text == after[start].text {
            start += 1
        }
        while beforeEnd > start, afterEnd > start,
              before[beforeEnd - 1].text == after[afterEnd - 1].text {
            beforeEnd -= 1
            afterEnd -= 1
        }

        let middleBefore = before[start..<beforeEnd].map(\.text)
        let middleAfter = after[start..<afterEnd].map(\.text)
        guard !middleBefore.isEmpty || !middleAfter.isEmpty else { return .none }

        let removedIndices: [Int]
        let insertedIndices: [Int]
        if middleBefore.isEmpty {
            removedIndices = []
            insertedIndices = Array(start..<afterEnd)
        } else if middleAfter.isEmpty {
            removedIndices = Array(start..<beforeEnd)
            insertedIndices = []
        } else if middleBefore.count * middleAfter.count > maximumAlignmentCells {
            removedIndices = Array(start..<beforeEnd)
            insertedIndices = Array(start..<afterEnd)
        } else {
            (removedIndices, insertedIndices) = align(
                middleBefore,
                middleAfter,
                offset: start
            )
        }

        return TextDiff(
            removed: merge(removedIndices, of: before),
            inserted: merge(insertedIndices, of: after)
        )
    }

    /// Alinha os dois miolos pela distância de edição e refaz o caminho para
    /// saber quais palavras foram trocadas, removidas ou acrescentadas. É a
    /// mesma distância que `TextChangeCounter` conta, agora com a matriz
    /// inteira, porque o caminho de volta precisa dela.
    private static func align(
        _ before: [String],
        _ after: [String],
        offset: Int
    ) -> (removed: [Int], inserted: [Int]) {
        let rows = before.count + 1
        let columns = after.count + 1
        var distance = [Int32](repeating: 0, count: rows * columns)
        for row in 0..<rows { distance[row * columns] = Int32(row) }
        for column in 0..<columns { distance[column] = Int32(column) }

        for row in 1..<rows {
            for column in 1..<columns {
                let same = before[row - 1] == after[column - 1]
                let replacement = distance[(row - 1) * columns + (column - 1)] + (same ? 0 : 1)
                let deletion = distance[(row - 1) * columns + column] + 1
                let insertion = distance[row * columns + (column - 1)] + 1
                distance[row * columns + column] = min(replacement, deletion, insertion)
            }
        }

        var removed: [Int] = []
        var inserted: [Int] = []
        var row = before.count
        var column = after.count
        while row > 0 || column > 0 {
            let current = distance[row * columns + column]
            if row > 0, column > 0, before[row - 1] == after[column - 1],
               distance[(row - 1) * columns + (column - 1)] == current {
                row -= 1
                column -= 1
                continue
            }
            if row > 0, column > 0,
               distance[(row - 1) * columns + (column - 1)] + 1 == current {
                removed.append(offset + row - 1)
                inserted.append(offset + column - 1)
                row -= 1
                column -= 1
                continue
            }
            if row > 0, distance[(row - 1) * columns + column] + 1 == current {
                removed.append(offset + row - 1)
                row -= 1
                continue
            }
            inserted.append(offset + column - 1)
            column -= 1
        }
        return (removed.reversed(), inserted.reversed())
    }

    /// Converte índices de palavras em trechos do texto, juntando as palavras
    /// vizinhas num trecho só.
    private static func merge(_ indices: [Int], of tokens: [TextToken]) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var runStart: Int?
        var runEnd = 0
        for index in indices {
            if runStart != nil, index == runEnd + 1 {
                runEnd = index
                continue
            }
            if let start = runStart {
                ranges.append(tokens[start].range.lowerBound..<tokens[runEnd].range.upperBound)
            }
            runStart = index
            runEnd = index
        }
        if let start = runStart {
            ranges.append(tokens[start].range.lowerBound..<tokens[runEnd].range.upperBound)
        }
        return ranges
    }
}
