import Foundation
import FoundationModels
import HollyCore

enum ProcessingError: LocalizedError {
    case unavailable(String)
    case emptyResponse
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        case .emptyResponse:
            return "O modelo retornou uma resposta vazia. Tente novamente ou ajuste o texto."
        case .generationFailed(let message):
            return message
        }
    }
}

final class TextProcessor: Sendable {
    /// Limite de caracteres por bloco enviado ao modelo. Acima disso o texto é
    /// dividido (chunking): o modelo on-device tem janela de contexto pequena e
    /// falha com textos longos (`exceededContextWindowSize`). Como a saída de
    /// tarefas de transformação tem tamanho parecido com a entrada, o bloco fica
    /// bem abaixo do teto para caber entrada + instruções + saída.
    private static let maxCharsPerChunk = 4000

    func process(_ text: String, action: CorrectionAction) async throws -> String {
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(let reason):
            throw ProcessingError.unavailable(Self.message(for: reason))
        }

        let envelope = TextEnvelope(text)
        guard !envelope.content.isEmpty else { return text }
        let chunks = TextChunker.split(
            envelope.content,
            maxCharacters: Self.maxCharsPerChunk
        )

        let processedContent: String
        if chunks.count <= 1 {
            processedContent = try await processChunkWithFallback(
                envelope.content,
                action: action
            )
        } else if action == .summarize {
            processedContent = try await summarizeChunks(chunks)
        } else {
            var results: [String] = []
            for chunk in chunks {
                results.append(
                    try await processChunkWithFallback(chunk.text, action: action)
                )
            }
            processedContent = TextChunker.reassemble(
                processedTexts: results,
                using: chunks
            )
        }

        return envelope.wrapping(processedContent)
    }

    /// Envia um único bloco ao modelo. Cria uma sessão nova por requisição:
    /// evita acumular contexto entre textos diferentes e garante que as
    /// instruções da ação vigente valem.
    private func respond(to chunk: String, action: CorrectionAction) async throws -> String {
        let session = LanguageModelSession(
            instructions: action.prompt(
                customInstruction: AppPreferences.customPrompt
            )
        )

        // Envolve o texto de entrada em delimitadores claros e distintos
        // para que a IA saiba exatamente onde começa e termina o texto do usuário,
        // sem confundir com tags XML que ela poderia repetir na saída.
        let promptInput = "===TEXTO===\n\(chunk)\n===FIM==="

        let response = try await session.respond(
            to: promptInput,
            options: GenerationOptions(temperature: action.temperature)
        )
        let content = ResponseSanitizer.clean(response.content, original: chunk)
        guard !content.isEmpty else {
            throw ProcessingError.emptyResponse
        }
        return content
    }

    /// Processa um bloco e, se mesmo assim estourar a janela de contexto,
    /// divide-o ao meio e tenta de novo recursivamente até caber.
    private func processChunkWithFallback(_ chunk: String, action: CorrectionAction) async throws -> String {
        do {
            return try await respond(to: chunk, action: action)
        } catch let error as LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = error, chunk.count > Self.maxCharsPerChunk / 4 {
                let halves = TextChunker.split(
                    chunk,
                    maxCharacters: max(500, chunk.count / 2)
                )
                if halves.count > 1 {
                    var results: [String] = []
                    for half in halves {
                        results.append(
                            try await processChunkWithFallback(half.text, action: action)
                        )
                    }
                    return TextChunker.reassemble(
                        processedTexts: results,
                        using: halves
                    )
                }
            }
            throw ProcessingError.generationFailed(Self.message(for: error))
        }
    }

    /// Resumo de texto longo em duas etapas (map-reduce): resume cada bloco e,
    /// se os resumos parciais couberem de uma vez, consolida-os num resumo
    /// único; caso contrário, devolve os parciais concatenados.
    private func summarizeChunks(_ chunks: [TextChunk]) async throws -> String {
        var partials: [String] = []
        for chunk in chunks {
            partials.append(
                try await processChunkWithFallback(chunk.text, action: .summarize)
            )
        }
        let combined = partials.joined(separator: "\n\n")
        guard combined.count <= Self.maxCharsPerChunk else {
            return combined
        }
        do {
            return try await respond(to: combined, action: .summarize)
        } catch {
            return combined
        }
    }

    /// Retorna `nil` se a Apple Intelligence está disponível, ou uma mensagem
    /// explicativa caso contrário. Usado para avisar o usuário na abertura do
    /// app, antes de qualquer tentativa de processamento.
    static func availabilityMessage() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            return message(for: reason)
        }
    }

    private static func message(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "Este Mac não é compatível com a Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            return "A Apple Intelligence está desativada. Ative-a em Ajustes do Sistema > Apple Intelligence e Siri."
        case .modelNotReady:
            return "O modelo da Apple Intelligence ainda está sendo preparado (download em andamento). Tente novamente em alguns minutos."
        @unknown default:
            return "A Apple Intelligence está indisponível neste momento."
        }
    }

    private static func message(for error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .exceededContextWindowSize:
            return "O texto é longo demais para o modelo processar de uma vez. Selecione um trecho menor e tente novamente."
        case .guardrailViolation:
            return "O filtro de segurança da Apple Intelligence bloqueou este conteúdo. Ajuste o texto e tente novamente."
        case .assetsUnavailable:
            return "Os recursos do modelo não estão disponíveis. Verifique se a Apple Intelligence terminou de ser baixada em Ajustes do Sistema."
        case .rateLimited:
            return "Muitas solicitações em sequência. Aguarde alguns segundos e tente novamente."
        default:
            return error.localizedDescription
        }
    }

}
