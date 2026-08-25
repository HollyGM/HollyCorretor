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
        try checkPreferredBoundaries()
        try checkPartialDelimiters()
        try checkPreambleRemoval()
        try checkChangeCounter()
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
        try require(
            ResponseSanitizer.clean(
                "===Era só essa questão do certificado.===",
                original: "Era só essa questão do certificado."
            ) == "Era só essa questão do certificado.",
            "O envelope abreviado de sinais de igual não foi removido."
        )
        try require(
            ResponseSanitizer.clean(
                "===termo jurídico===",
                original: "===termo juridico==="
            ) == "===termo jurídico===",
            "Sinais de igual legítimos do texto original foram removidos."
        )
        try require(
            ResponseSanitizer.clean(
                "Av. Prudente de Morais, 6842 – Natal – RN. ===FIM",
                original: "Av. Prudente de Morais, 6842 - Natal - RN."
            ) == "Av. Prudente de Morais, 6842 – Natal – RN.",
            "O marcador de fechamento truncado da resposta não foi removido."
        )
        try require(
            ResponseSanitizer.clean(
                "===TEXTO==\nTexto corrigido\n===FIM=",
                original: "Testo corrigido"
            ) == "Texto corrigido",
            "Variantes truncadas dos dois delimitadores não foram removidas."
        )
        try require(
            ResponseSanitizer.clean(
                "A expressão termina em ===FIM",
                original: "A expressão termina em ===FIM"
            ) == "A expressão termina em ===FIM",
            "Um marcador truncado legítimo do texto original foi removido."
        )
        try require(
            ResponseSanitizer.clean(
                "A expressão termina em ===FIM===",
                original: "A expressão termina em ===FIM==="
            ) == "A expressão termina em ===FIM===",
            "Um marcador completo legítimo do texto original foi removido."
        )
    }

    /// O modelo com frequência devolve só o delimitador de abertura, sem
    /// fechar. A versão anterior exigia os dois e deixava o `===TEXTO===`
    /// vazar para dentro do texto do usuário.
    private static func checkPartialDelimiters() throws {
        try require(
            ResponseSanitizer.clean(
                "===TEXTO===\nPrezado doutor,\n\nSegue a petição.",
                original: "Prezado doutor,\n\nSegue a peticao."
            ) == "Prezado doutor,\n\nSegue a petição.",
            "Um delimitador de abertura sem fechamento não foi removido."
        )
        try require(
            ResponseSanitizer.clean(
                "Texto corrigido\n===FIM===",
                original: "Testo corrigido"
            ) == "Texto corrigido",
            "Um delimitador de fechamento sem abertura não foi removido."
        )
        try require(
            ResponseSanitizer.clean(
                "===TEXTO=== continua sendo o nome do marcador",
                original: "===TEXTO=== continua sendo o nome do marcador"
            ) == "===TEXTO=== continua sendo o nome do marcador",
            "Um delimitador legítimo do próprio usuário foi removido."
        )
    }

    private static func checkPreambleRemoval() throws {
        try require(
            ResponseSanitizer.clean(
                "Aqui está o texto corrigido:\nO réu não compareceu.",
                original: "O reu nao compareceu."
            ) == "O réu não compareceu.",
            "A frase de apresentação do modelo não foi removida."
        )
        try require(
            ResponseSanitizer.clean(
                "Segue o texto que combinamos.",
                original: "Segue o texto que combinamos."
            ) == "Segue o texto que combinamos.",
            "Uma única linha do usuário foi confundida com apresentação."
        )
        try require(
            ResponseSanitizer.clean(
                "Segue o texto para conferência:\nvalor de R$ 10,00.",
                original: "Segue o texto para conferencia:\nvalor de R$ 10,00."
            ) == "Segue o texto para conferência:\nvalor de R$ 10,00.",
            "Uma abertura legítima do usuário foi removida."
        )

        // A correção pode transformar a linha do usuário em algo que casa com a
        // lista de apresentações, sem que a linha original casasse. Comparar por
        // prefixo exato apagaria o conteúdo dela.
        try require(
            ResponseSanitizer.clean(
                "Segue o texto para conferência:\nvalor de R$ 10,00.",
                original: "Segwe o texto para conferencia:\nvalor de R$ 10,00."
            ) == "Segue o texto para conferência:\nvalor de R$ 10,00.",
            "Uma linha do usuário corrigida foi confundida com apresentação do modelo."
        )
        try require(
            ResponseSanitizer.clean(
                "Aqui está o texto corrigido:\nO réu não compareceu à audiência.",
                original: "O reu nao compareceu a audiencia."
            ) == "O réu não compareceu à audiência.",
            "Uma apresentação de fato acrescentada pelo modelo não foi removida."
        )
        try require(
            ResponseSanitizer.isLikelyRevision(
                of: "Segwe o texto para conferencia:",
                into: "Segue o texto para conferência:"
            ),
            "Uma diferença de uma letra e acentos não foi reconhecida como revisão."
        )
        try require(
            !ResponseSanitizer.isLikelyRevision(
                of: "O reu nao compareceu a audiencia.",
                into: "Aqui está o texto corrigido:"
            ),
            "Duas linhas sem relação foram tomadas por revisão uma da outra."
        )
    }

    private static func checkChangeCounter() throws {
        try require(
            TextChangeCounter.count(
                from: "Esse testo tem algun erro.",
                to: "Esse texto tem algum erro."
            ) == 2,
            "Duas palavras corrigidas deveriam contar como duas alterações."
        )
        try require(
            TextChangeCounter.count(from: "Texto correto.", to: "Texto correto.") == 0,
            "Textos idênticos não deveriam registrar alterações."
        )
        try require(
            TextChangeCounter.count(from: "Uma frase.", to: "Uma frase mais clara!") == 3,
            "Inserções e uma troca de pontuação não foram contadas corretamente."
        )
    }

    /// A divisão deve preferir fim de parágrafo, depois quebra de linha,
    /// depois fim de frase, e só então qualquer espaço.
    private static func checkPreferredBoundaries() throws {
        let paragraphs = "Primeiro parágrafo aqui.\n\nSegundo parágrafo aqui."
        let byParagraph = TextChunker.split(paragraphs, maxCharacters: 30)
        try require(
            byParagraph.map(\.text) == ["Primeiro parágrafo aqui.", "Segundo parágrafo aqui."],
            "A divisão não preferiu a fronteira de parágrafo."
        )
        try require(
            byParagraph.first?.separatorAfter == "\n\n",
            "A quebra dupla de linha não foi preservada no separador."
        )

        let sentences = "Primeira frase completa. Segunda frase completa. Terceira."
        let bySentence = TextChunker.split(sentences, maxCharacters: 40)
        try require(
            bySentence.allSatisfy { $0.text.hasSuffix(".") },
            "Um bloco terminou no meio de uma frase havendo fim de frase disponível."
        )
        try require(
            TextChunker.reassemble(
                processedTexts: bySentence.map(\.text),
                using: bySentence
            ) == sentences,
            "A divisão por frases alterou o texto."
        )

        // Aspas e parênteses depois do ponto ainda encerram a frase.
        let quoted = "Ele disse \"acabou.\" Depois saiu da sala imediatamente."
        let byQuoted = TextChunker.split(quoted, maxCharacters: 34)
        try require(
            byQuoted.first?.text == "Ele disse \"acabou.\"",
            "Um ponto final antes de aspas não foi reconhecido como fim de frase."
        )

        // Um parágrafo curtíssimo logo no início não pode gerar um bloco minúsculo.
        let unbalanced = "Ok.\n\n" + String(repeating: "palavra ", count: 20)
        let chunks = TextChunker.split(unbalanced, maxCharacters: 60)
        try require(
            chunks[0].text.count >= 30,
            "Uma fronteira muito no início gerou um bloco pequeno demais."
        )
        try require(
            TextChunker.reassemble(
                processedTexts: chunks.map(\.text),
                using: chunks
            ) == unbalanced,
            "A divisão com piso de preenchimento alterou o texto."
        )
    }
}
