import Foundation

public struct TextChunk: Equatable, Sendable {
    public let text: String
    public let separatorAfter: String

    public init(text: String, separatorAfter: String) {
        self.text = text
        self.separatorAfter = separatorAfter
    }
}

public enum TextChunker {
    /// Onde um bloco pode terminar, da fronteira mais desejável para a menos.
    /// Cortar num fim de parágrafo preserva muito mais sentido do que cortar no
    /// meio de uma frase, o que degrada reescrita e formalização.
    private enum Boundary: CaseIterable {
        case paragraph
        case line
        case sentence
        case whitespace
    }

    private static let sentenceTerminators: Set<Character> = [".", "!", "?", "…"]

    /// Caracteres que podem aparecer depois do ponto final e antes do espaço:
    /// `disse "acabou."` ou `(art. 5º)`.
    private static let closingMarks: Set<Character> = [
        "\"", "'", "”", "’", ")", "]", "}", "»", "*", "_"
    ]

    public static func split(_ text: String, maxCharacters: Int) -> [TextChunk] {
        precondition(maxCharacters > 0, "maxCharacters deve ser maior que zero")

        guard text.count > maxCharacters else {
            return [TextChunk(text: text, separatorAfter: "")]
        }

        var chunks: [TextChunk] = []
        var remaining = text[...]

        while remaining.count > maxCharacters {
            let limit = remaining.index(
                remaining.startIndex,
                offsetBy: maxCharacters
            )
            let candidate = remaining[..<limit]

            // Sem este piso, um único "\n" logo no começo do bloco geraria um
            // bloco minúsculo e desperdiçaria a janela de contexto inteira.
            let minimumFill = max(1, maxCharacters / 2)
            let earliestAccepted = candidate.index(
                candidate.startIndex,
                offsetBy: minimumFill
            )

            let boundary = Boundary.allCases.lazy
                .compactMap { lastBoundary($0, in: candidate, notBefore: earliestAccepted) }
                .first

            guard let boundary else {
                // Nenhuma fronteira utilizável: corta no limite. Acontece com
                // sequências longas sem espaço, como um hash ou uma URL enorme.
                chunks.append(TextChunk(text: String(candidate), separatorAfter: ""))
                remaining = remaining[limit...]
                continue
            }

            var nextStart = boundary
            while nextStart < remaining.endIndex, remaining[nextStart].isWhitespace {
                nextStart = remaining.index(after: nextStart)
            }

            chunks.append(
                TextChunk(
                    text: String(remaining[..<boundary]),
                    separatorAfter: String(remaining[boundary..<nextStart])
                )
            )
            remaining = remaining[nextStart...]
        }

        if !remaining.isEmpty {
            chunks.append(TextChunk(text: String(remaining), separatorAfter: ""))
        }

        return chunks
    }

    /// Índice do início do espaçamento que encerra o bloco, ou `nil` se não
    /// houver fronteira daquele tipo em posição aceitável.
    private static func lastBoundary(
        _ kind: Boundary,
        in candidate: Substring,
        notBefore earliest: Substring.Index
    ) -> Substring.Index? {
        var index = candidate.endIndex

        while index > candidate.startIndex {
            index = candidate.index(before: index)
            guard index >= earliest else { return nil }
            guard candidate[index].isWhitespace else { continue }

            // Recua até o começo da sequência de espaços, para que o separador
            // preservado inclua a quebra inteira.
            var runStart = index
            while runStart > candidate.startIndex {
                let previous = candidate.index(before: runStart)
                guard candidate[previous].isWhitespace else { break }
                runStart = previous
            }
            guard runStart >= earliest else { return nil }

            if matches(kind, at: runStart, upTo: index, in: candidate) {
                return runStart
            }

            index = runStart
        }

        return nil
    }

    private static func matches(
        _ kind: Boundary,
        at runStart: Substring.Index,
        upTo lastWhitespace: Substring.Index,
        in candidate: Substring
    ) -> Bool {
        switch kind {
        case .whitespace:
            return true

        case .line:
            return candidate[runStart...lastWhitespace].contains("\n")

        case .paragraph:
            return candidate[runStart...lastWhitespace].filter { $0 == "\n" }.count >= 2

        case .sentence:
            var index = runStart
            while index > candidate.startIndex {
                index = candidate.index(before: index)
                let character = candidate[index]
                if closingMarks.contains(character) { continue }
                return sentenceTerminators.contains(character)
            }
            return false
        }
    }

    public static func reassemble(
        processedTexts: [String],
        using chunks: [TextChunk]
    ) -> String {
        precondition(processedTexts.count == chunks.count)
        return zip(processedTexts, chunks)
            .map { processed, chunk in processed + chunk.separatorAfter }
            .joined()
    }
}

public struct TextEnvelope: Equatable, Sendable {
    public let leadingWhitespace: String
    public let content: String
    public let trailingWhitespace: String

    public init(_ text: String) {
        let firstContent = text.firstIndex(where: { !$0.isWhitespace })
        guard let firstContent else {
            leadingWhitespace = text
            content = ""
            trailingWhitespace = ""
            return
        }

        let lastContent = text.lastIndex(where: { !$0.isWhitespace })!
        let afterLastContent = text.index(after: lastContent)
        leadingWhitespace = String(text[..<firstContent])
        content = String(text[firstContent..<afterLastContent])
        trailingWhitespace = String(text[afterLastContent...])
    }

    public func wrapping(_ processedContent: String) -> String {
        leadingWhitespace + processedContent + trailingWhitespace
    }
}

public enum ResponseSanitizer {
    public static let openingDelimiter = "===TEXTO==="
    public static let closingDelimiter = "===FIM==="

    /// Frases com que o modelo às vezes apresenta o resultado em vez de
    /// devolver só o texto pedido.
    private static let preambles = [
        "aqui está o texto",
        "aqui esta o texto",
        "segue o texto",
        "texto corrigido:",
        "texto reescrito:",
        "texto formalizado:",
        "texto simplificado:",
        "resumo:",
        "claro!",
        "certo!"
    ]

    /// Limpa a resposta do modelo. Serve tanto para o texto final quanto para
    /// os pedaços que chegam durante o streaming, por isso cada artefato é
    /// tratado de forma independente: durante o streaming o delimitador de
    /// abertura já chegou, mas o de fechamento ainda não.
    public static func clean(_ response: String, original: String) -> String {
        var result = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalTrimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)

        if !originalTrimmed.hasPrefix(openingDelimiter), result.hasPrefix(openingDelimiter) {
            result.removeFirst(openingDelimiter.count)
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if !originalTrimmed.hasSuffix(closingDelimiter), result.hasSuffix(closingDelimiter) {
            result.removeLast(closingDelimiter.count)
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if !originalTrimmed.hasPrefix("<texto>"),
           result.lowercased().hasPrefix("<texto>") {
            result.removeFirst("<texto>".count)
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if !originalTrimmed.hasSuffix("</texto>"),
           result.lowercased().hasSuffix("</texto>") {
            result.removeLast("</texto>".count)
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if !originalTrimmed.hasPrefix("```"),
           result.hasPrefix("```"),
           result.hasSuffix("```") {
            var lines = result.components(separatedBy: "\n")
            if lines.count >= 2 {
                lines.removeFirst()
                lines.removeLast()
                result = lines.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return removePreamble(from: result, original: originalTrimmed)
    }

    /// Remove uma linha de apresentação só quando ela é a primeira de várias e
    /// não corresponde a nada que o usuário tenha escrito. Um texto de uma linha
    /// só nunca é tocado: seria o próprio conteúdo.
    ///
    /// A comparação não pode ser por prefixo exato. Se a pessoa escreveu
    /// "Segwe o texto para conferência:" e a correção devolveu
    /// "Segue o texto para conferência:", a linha corrigida passa a casar com a
    /// lista enquanto a original não casava — e a linha inteira do usuário seria
    /// apagada. Por isso o teste é de semelhança com a linha original.
    private static func removePreamble(from text: String, original: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else { return text }

        let first = lines[0].trimmingCharacters(in: .whitespaces)
        let firstKey = normalized(first)
        guard preambles.contains(where: { firstKey.hasPrefix($0) }) else { return text }

        let originalFirst = original
            .components(separatedBy: "\n")[0]
            .trimmingCharacters(in: .whitespaces)
        guard !isLikelyRevision(of: originalFirst, into: first) else { return text }

        lines.removeFirst()
        return lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Minúsculas e sem acento, para a comparação não tropeçar justamente nas
    /// diferenças que a correção existe para produzir.
    public static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    /// Verdadeiro quando `revised` parece ser apenas uma versão corrigida de
    /// `source`, e não uma linha nova acrescentada pelo modelo.
    public static func isLikelyRevision(of source: String, into revised: String) -> Bool {
        let a = normalized(source)
        let b = normalized(revised)
        guard !a.isEmpty, !b.isEmpty else { return false }

        // Uma revisão mexe em acentos, letras trocadas e pontuação; não reescreve
        // a linha inteira. Um terço de diferença é folga suficiente para erros
        // de digitação e apertada o bastante para não confundir com um texto novo.
        let limit = Int(Double(max(a.count, b.count)) * 0.34)
        return editDistance(a, b, ceiling: limit) <= limit
    }

    /// Distância de edição com corte: assim que passa do teto, para de calcular.
    private static func editDistance(_ a: String, _ b: String, ceiling: Int) -> Int {
        // Linhas muito longas não precisam de precisão: o custo cresce com o
        // quadrado do tamanho e a decisão já está tomada bem antes disso.
        let first = Array(a.prefix(240))
        let second = Array(b.prefix(240))
        if first.isEmpty { return second.count }
        if second.isEmpty { return first.count }
        if abs(first.count - second.count) > ceiling { return ceiling + 1 }

        var previous = Array(0...second.count)
        var current = [Int](repeating: 0, count: second.count + 1)

        for i in 1...first.count {
            current[0] = i
            var rowBest = current[0]
            for j in 1...second.count {
                let substitution = previous[j - 1] + (first[i - 1] == second[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
                rowBest = min(rowBest, current[j])
            }
            if rowBest > ceiling { return ceiling + 1 }
            swap(&previous, &current)
        }
        return previous[second.count]
    }
}
