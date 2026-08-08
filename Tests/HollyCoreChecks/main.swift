import HollyCore

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

@main
enum HollyCoreChecks {
    static func main() throws {
        try checkShortText()
        try checkLosslessChunking()
        try checkLongWord()
        try checkEnvelope()
        try checkSanitizer()
        print("Todos os testes do HollyCore passaram.")
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else { throw CheckFailure(description: message) }
    }

    private static func checkShortText() throws {
        try require(
            TextChunker.split("Texto curto", maxCharacters: 50)
                == [TextChunk(text: "Texto curto", separatorAfter: "")],
            "Um texto curto deveria permanecer em um único bloco."
        )
    }

    private static func checkLosslessChunking() throws {
        let original = "Primeira linha.\n\nSegunda linha com várias palavras.\nTerceira."
        let chunks = TextChunker.split(original, maxCharacters: 22)
        try require(
            chunks.allSatisfy { $0.text.count <= 22 },
            "Um bloco ultrapassou o limite configurado."
        )
        try require(
            TextChunker.reassemble(
                processedTexts: chunks.map(\.text),
                using: chunks
            ) == original,
            "A divisão alterou caracteres ou espaços do texto."
        )
    }

    private static func checkLongWord() throws {
        let original = String(repeating: "á", count: 31)
        let chunks = TextChunker.split(original, maxCharacters: 10)
        try require(
            chunks.map(\.text).map(\.count) == [10, 10, 10, 1],
            "Uma palavra longa não foi dividida nos tamanhos esperados."
        )
        try require(
            TextChunker.reassemble(
                processedTexts: chunks.map(\.text),
                using: chunks
            ) == original,
            "A divisão de uma palavra longa perdeu caracteres."
        )
    }

    private static func checkEnvelope() throws {
        let envelope = TextEnvelope(" \n  texto  \n")
        try require(envelope.content == "texto", "O conteúdo central foi alterado.")
        try require(
            envelope.wrapping("corrigido") == " \n  corrigido  \n",
            "Os espaços externos não foram preservados."
        )
    }

    private static func checkSanitizer() throws {
        try require(
            ResponseSanitizer.clean("\"Texto\"", original: "\"testo\"")
                == "\"Texto\"",
            "Aspas legítimas foram removidas."
        )
        try require(
            ResponseSanitizer.clean(
                "```\nconteúdo\n```",
                original: "```\nconteudo\n```"
            ) == "```\nconteúdo\n```",
            "Uma cerca de código legítima foi removida."
        )
        try require(
            ResponseSanitizer.clean(
                "===TEXTO===\nTexto corrigido\n===FIM===",
                original: "Testo"
            ) == "Texto corrigido",
            "Delimitadores adicionados pelo modelo não foram removidos."
        )
    }
}
