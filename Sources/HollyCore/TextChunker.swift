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
            let boundary = candidate.lastIndex(of: "\n")
                ?? candidate.lastIndex(where: { $0.isWhitespace })

            guard let boundary, boundary != remaining.startIndex else {
                chunks.append(TextChunk(text: String(candidate), separatorAfter: ""))
                remaining = remaining[limit...]
                continue
            }

            var contentEnd = boundary
            var nextStart = boundary
            while nextStart < remaining.endIndex, remaining[nextStart].isWhitespace {
                nextStart = remaining.index(after: nextStart)
            }

            // Evita um bloco vazio quando o limite cai dentro de uma sequência de espaços.
            if contentEnd == remaining.startIndex {
                contentEnd = limit
                nextStart = limit
            }

            chunks.append(
                TextChunk(
                    text: String(remaining[..<contentEnd]),
                    separatorAfter: String(remaining[contentEnd..<nextStart])
                )
            )
            remaining = remaining[nextStart...]
        }

        if !remaining.isEmpty {
            chunks.append(TextChunk(text: String(remaining), separatorAfter: ""))
        }

        return chunks
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
    public static func clean(_ response: String, original: String) -> String {
        var result = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalTrimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)

        if result.hasPrefix("===TEXTO==="), result.hasSuffix("===FIM===") {
            result.removeFirst("===TEXTO===".count)
            result.removeLast("===FIM===".count)
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if !originalTrimmed.hasPrefix("<texto>"),
           result.lowercased().hasPrefix("<texto>"),
           result.lowercased().hasSuffix("</texto>") {
            result.removeFirst("<texto>".count)
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

        return result
    }
}
