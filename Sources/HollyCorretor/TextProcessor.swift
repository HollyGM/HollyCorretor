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

/// O que o processamento informa enquanto trabalha. `partial` traz o texto
/// acumulado até agora, para exibição; `finished` traz o resultado definitivo.
enum ProcessingUpdate: Sendable {
    case partial(String)
    case finished(String)
}

final class TextProcessor: Sendable {
    /// Guardrails de transformação em vez dos padrão. O app revisa texto que a
    /// pessoa já tem em mãos — peças criminais inclusive — e não gera conteúdo
    /// novo. Com os guardrails padrão, um trecho sobre crime sexual é recusado
    /// com "May contain unsafe content", o que inviabiliza o uso jurídico.
    private static let onDeviceModel = SystemLanguageModel(
        guardrails: .permissiveContentTransformations
    )

    /// Usado só se a contagem real de tokens não estiver disponível.
    private static let fallbackMaxCharsPerChunk = 4_000

    /// Português do Brasil mede ~3,56 caracteres por token neste modelo.
    /// Uso 3,2 para subestimar e errar sempre para o lado seguro.
    private static let charactersPerToken = 3.2

    /// Espaço guardado para os delimitadores, o enquadramento da conversa e
    /// uma margem de erro da estimativa.
    private static let contextReserve = 256

    /// Teto medido, e não deduzido da janela de contexto: numa única resposta o
    /// modelo local não escreve mais que ~2.400 caracteres. Acima disso ele
    /// condensa o texto em vez de transformá-lo por inteiro. Medido em pt-BR —
    /// entradas de 2.506 caracteres voltam completas (razão 1,00) e de 3.067 já
    /// voltam com 78%, com a saída travando em torno de 2.382 caracteres.
    /// A janela de 8.192 tokens comporta muito mais, mas quem manda é a saída.
    private static let outputCeilingCharacters = 2_400

    /// Nenhum bloco passa disto, por mais que a ação encurte o texto: entradas
    /// muito grandes fazem o modelo ignorar trechos do meio.
    private static let absoluteMaxCharacters = 8_000

    private static let minimumChunkCharacters = 900

    // MARK: - Disponibilidade

    static func availabilityMessage() -> String? {
        switch onDeviceModel.availability {
        case .available:
            break
        case .unavailable(let reason):
            return message(for: reason)
        }

        guard onDeviceModel.supportsLocale(Locale(identifier: "pt_BR")) else {
            return "Este modelo da Apple Intelligence não tem suporte a português do Brasil nesta versão do macOS."
        }
        return nil
    }

    /// Manda o sistema carregar o modelo enquanto o app ainda está capturando a
    /// seleção. Economiza cerca de meio segundo no primeiro uso depois de ligar
    /// o Mac; nas vezes seguintes o modelo já está na memória.
    func prewarm() {
        guard case .available = Self.onDeviceModel.availability else { return }
        let session = LanguageModelSession(model: Self.onDeviceModel)
        session.prewarm()
    }

    // MARK: - Processamento

    /// `customInstruction` vem do campo livre do painel flutuante. Quando é
    /// `nil`, vale a instrução gravada nas Preferências.
    func stream(
        _ text: String,
        action: CorrectionAction,
        customInstruction: String? = nil
    ) -> AsyncThrowingStream<ProcessingUpdate, Error> {
        AsyncThrowingStream { continuation in
            let work = Task {
                do {
                    try await self.run(
                        text,
                        action: action,
                        customInstruction: customInstruction
                    ) { update in
                        continuation.yield(update)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    private func run(
        _ text: String,
        action: CorrectionAction,
        customInstruction: String?,
        emit: @Sendable (ProcessingUpdate) -> Void
    ) async throws {
        if let unavailable = Self.availabilityMessage() {
            throw ProcessingError.unavailable(unavailable)
        }

        let envelope = TextEnvelope(text)
        guard !envelope.content.isEmpty else {
            emit(.finished(text))
            return
        }

        let instructions = action.prompt(
            customInstruction: customInstruction ?? AppPreferences.customPrompt
        )
        let plan = await Self.plan(
            for: envelope.content,
            action: action,
            instructions: instructions
        )
        let chunks = TextChunker.split(
            envelope.content,
            maxCharacters: plan.maxCharactersPerChunk
        )

        // Resumo, pontos, lista e tabela produzem uma estrutura única. Fatiar e
        // concatenar geraria várias listas soltas, então aqui o texto é
        // processado por partes e depois consolidado numa só.
        if chunks.count > 1, action.reformatsWholeText {
            let condensed = try await condense(
                chunks,
                action: action,
                instructions: instructions,
                plan: plan,
                envelope: envelope,
                emit: emit
            )
            emit(.finished(envelope.wrapping(condensed)))
            return
        }

        var completed: [String] = []
        for chunk in chunks {
            try Task.checkCancellation()
            let result = try await process(
                chunk.text,
                action: action,
                instructions: instructions,
                plan: plan
            ) { partial in
                emit(.partial(envelope.wrapping(
                    Self.join(completed: completed, current: partial, chunks: chunks)
                )))
            }
            completed.append(result)
        }

        emit(.finished(envelope.wrapping(
            TextChunker.reassemble(processedTexts: completed, using: chunks)
        )))
    }

    /// Duas etapas: processa cada bloco e depois consolida os resultados
    /// parciais, se eles couberem numa passada só.
    private func condense(
        _ chunks: [TextChunk],
        action: CorrectionAction,
        instructions: String,
        plan: Plan,
        envelope: TextEnvelope,
        emit: @Sendable (ProcessingUpdate) -> Void
    ) async throws -> String {
        var partials: [String] = []
        for chunk in chunks {
            try Task.checkCancellation()
            let result = try await process(
                chunk.text,
                action: action,
                instructions: instructions,
                plan: plan
            ) { partial in
                emit(.partial(envelope.wrapping(
                    (partials + [partial]).joined(separator: "\n\n")
                )))
            }
            partials.append(result)
        }

        let combined = partials.joined(separator: "\n\n")
        guard combined.count <= plan.maxCharactersPerChunk else { return combined }

        try Task.checkCancellation()
        do {
            return try await process(
                combined,
                action: action,
                instructions: instructions,
                plan: plan
            ) { partial in
                emit(.partial(envelope.wrapping(partial)))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return combined
        }
    }

    /// Envia um bloco ao modelo em streaming. Cria sessão nova por bloco para
    /// não acumular contexto entre textos diferentes. Divide e refaz o bloco em
    /// dois casos: se a janela de contexto estourar, e se o modelo devolver
    /// menos texto do que recebeu numa ação que deveria preservar o conteúdo.
    private func process(
        _ chunk: String,
        action: CorrectionAction,
        instructions: String,
        plan: Plan,
        onPartial: (String) -> Void
    ) async throws -> String {
        let result: String
        do {
            result = try await respond(
                to: chunk,
                action: action,
                instructions: instructions,
                plan: plan,
                onPartial: onPartial
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard Self.isContextOverflow(error),
                  let retried = try await splitAndRetry(
                      chunk,
                      action: action,
                      instructions: instructions,
                      plan: plan,
                      onPartial: onPartial
                  ) else {
                throw ProcessingError.generationFailed(Self.message(for: error))
            }
            return retried
        }

        guard Self.lostContent(output: result, input: chunk, action: action) else {
            return result
        }
        return try await splitAndRetry(
            chunk,
            action: action,
            instructions: instructions,
            plan: plan,
            onPartial: onPartial
        ) ?? result
    }

    /// Divide o bloco ao meio e processa cada metade. Devolve `nil` quando não
    /// há como dividir mais, para o chamador decidir o que fazer.
    private func splitAndRetry(
        _ chunk: String,
        action: CorrectionAction,
        instructions: String,
        plan: Plan,
        onPartial: (String) -> Void
    ) async throws -> String? {
        guard chunk.count > Self.minimumChunkCharacters else { return nil }

        let halves = TextChunker.split(
            chunk,
            maxCharacters: max(Self.minimumChunkCharacters, chunk.count / 2)
        )
        guard halves.count > 1 else { return nil }

        var results: [String] = []
        for half in halves {
            try Task.checkCancellation()
            let result = try await process(
                half.text,
                action: action,
                instructions: instructions,
                plan: plan
            ) { partial in
                onPartial(Self.join(completed: results, current: partial, chunks: halves))
            }
            results.append(result)
        }
        return TextChunker.reassemble(processedTexts: results, using: halves)
    }

    /// Acima de um certo tamanho o modelo local deixa de transformar o texto
    /// inteiro e passa a condensá-lo, devolvendo bem menos do que recebeu. O
    /// tamanho de bloco já evita isso, mas o ponto de virada muda conforme o
    /// texto e a versão do sistema, então o resultado é sempre conferido.
    private static func lostContent(
        output: String,
        input: String,
        action: CorrectionAction
    ) -> Bool {
        guard let floor = action.minimumOutputRatio else { return false }
        return Double(output.count) < Double(input.count) * floor
    }

    private func respond(
        to chunk: String,
        action: CorrectionAction,
        instructions: String,
        plan: Plan,
        onPartial: (String) -> Void
    ) async throws -> String {
        let session = Self.makeSession(instructions: instructions, plan: plan)

        // Delimitadores explícitos deixam claro onde começa e termina o texto
        // da pessoa, para o modelo não confundi-lo com instruções.
        let promptInput = """
        \(ResponseSanitizer.openingDelimiter)
        \(chunk)
        \(ResponseSanitizer.closingDelimiter)
        """

        var content = ""
        for try await partial in session.streamResponse(
            to: promptInput,
            options: Self.options(for: action, chunk: chunk, plan: plan)
        ) {
            try Task.checkCancellation()
            content = ResponseSanitizer.clean(partial.content, original: chunk)
            onPartial(content)
        }

        guard !content.isEmpty else { throw ProcessingError.emptyResponse }
        return content
    }

    private static func makeSession(
        instructions: String,
        plan: Plan
    ) -> LanguageModelSession {
        // O Private Cloud Compute não aceita configuração de guardrails, então
        // ele fica restrito aos textos longos que o modelo local não comporta,
        // e só quando a pessoa liga a opção explicitamente.
        if plan.usesPrivateCloudCompute, #available(macOS 27.0, *) {
            let cloud = PrivateCloudComputeLanguageModel()
            if case .available = cloud.availability {
                return LanguageModelSession(model: cloud, instructions: instructions)
            }
        }
        return LanguageModelSession(model: onDeviceModel, instructions: instructions)
    }

    private static func options(
        for action: CorrectionAction,
        chunk: String,
        plan: Plan
    ) -> GenerationOptions {
        let estimatedInput = Int(Double(chunk.count) / charactersPerToken)
        let headroom = plan.contextSize - plan.instructionTokens - estimatedInput - 128
        let responseCap = max(256, headroom)

        if action.prefersDeterministicOutput {
            return GenerationOptions(
                samplingMode: .greedy,
                maximumResponseTokens: responseCap
            )
        }
        return GenerationOptions(
            temperature: action.temperature,
            maximumResponseTokens: responseCap
        )
    }

    // MARK: - Orçamento de contexto

    /// Tamanho de bloco e limites derivados da janela real do modelo, em vez de
    /// um número fixo de caracteres. A janela local tem 8.192 tokens, não os
    /// ~1.100 que o limite antigo de 4.000 caracteres supunha.
    private struct Plan: Sendable {
        let maxCharactersPerChunk: Int
        let contextSize: Int
        let instructionTokens: Int
        let usesPrivateCloudCompute: Bool
    }

    private static func plan(
        for content: String,
        action: CorrectionAction,
        instructions: String
    ) async -> Plan {
        let localContext = onDeviceModel.contextSize
        let instructionTokens = await tokenCount(
            of: instructions,
            fallbackCharacters: instructions.count
        )
        let localBudget = characters(
            context: localContext,
            instructionTokens: instructionTokens,
            action: action
        )

        guard AppPreferences.usesPrivateCloudCompute,
              content.count > localBudget,
              #available(macOS 27.0, *) else {
            return Plan(
                maxCharactersPerChunk: localBudget,
                contextSize: localContext,
                instructionTokens: instructionTokens,
                usesPrivateCloudCompute: false
            )
        }

        let cloud = PrivateCloudComputeLanguageModel()
        guard case .available = cloud.availability,
              let cloudContext = try? await cloud.contextSize else {
            return Plan(
                maxCharactersPerChunk: localBudget,
                contextSize: localContext,
                instructionTokens: instructionTokens,
                usesPrivateCloudCompute: false
            )
        }

        return Plan(
            maxCharactersPerChunk: characters(
                context: cloudContext,
                instructionTokens: instructionTokens,
                action: action
            ),
            contextSize: cloudContext,
            instructionTokens: instructionTokens,
            usesPrivateCloudCompute: true
        )
    }

    private static func characters(
        context: Int,
        instructionTokens: Int,
        action: CorrectionAction
    ) -> Int {
        // Dois tetos independentes. O primeiro é a fidelidade da saída, que foi
        // medida: como o modelo não escreve mais que ~2.400 caracteres por
        // resposta, a entrada que cabe depende de quanto a ação alonga o texto.
        // Corrigir quase não alonga, então aceita bloco maior; formalizar
        // alonga bastante, então aceita menos.
        let byOutput = Int(Double(outputCeilingCharacters) / action.expectedOutputRatio)

        // O segundo é a janela de contexto, que é aritmética: entrada, saída e
        // instruções precisam caber juntas.
        let usable = context - instructionTokens - contextReserve
        let byContext = usable > 0
            ? Int((Double(usable) / (1 + action.expectedOutputRatio)) * charactersPerToken)
            : fallbackMaxCharsPerChunk

        let budget = min(byOutput, byContext, absoluteMaxCharacters)
        return max(minimumChunkCharacters, budget)
    }

    private static func tokenCount(
        of text: String,
        fallbackCharacters: Int
    ) async -> Int {
        if #available(macOS 26.4, *) {
            if let count = try? await onDeviceModel.tokenCount(for: Instructions(text)) {
                return count
            }
        }
        return Int(Double(fallbackCharacters) / charactersPerToken)
    }

    // MARK: - Erros

    /// O macOS 27 substituiu `GenerationError` por `LanguageModelError`. Como o
    /// app tem alvo macOS 26, o compilador não avisa da troca, e capturar só o
    /// tipo antigo faz todo o tratamento de erro parar de funcionar em silêncio.
    private static func isContextOverflow(_ error: Error) -> Bool {
        if #available(macOS 27.0, *), let novo = error as? LanguageModelError {
            if case .contextSizeExceeded = novo { return true }
        }
        if let antigo = error as? LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = antigo { return true }
        }
        return false
    }

    private static func message(for error: Error) -> String {
        if let processing = error as? ProcessingError {
            return processing.errorDescription ?? error.localizedDescription
        }

        if #available(macOS 27.0, *), let novo = error as? LanguageModelError {
            return message(for: novo)
        }
        if let antigo = error as? LanguageModelSession.GenerationError {
            return message(for: antigo)
        }
        return error.localizedDescription
    }

    @available(macOS 27.0, *)
    private static func message(for error: LanguageModelError) -> String {
        switch error {
        case .contextSizeExceeded:
            return "O texto é longo demais para o modelo processar de uma vez. Selecione um trecho menor e tente novamente."
        case .guardrailViolation:
            return "O filtro de segurança da Apple Intelligence bloqueou este conteúdo. Ajuste o texto e tente novamente."
        case .refusal:
            return "O modelo recusou-se a processar este conteúdo. Ajuste o texto e tente novamente."
        case .rateLimited:
            return "Muitas solicitações em sequência. Aguarde alguns segundos e tente novamente."
        case .timeout:
            return "O modelo demorou demais para responder. Tente novamente com um trecho menor."
        case .unsupportedLanguageOrLocale:
            return "O modelo não tem suporte ao idioma deste texto."
        case .unsupportedCapability, .unsupportedGenerationGuide, .unsupportedTranscriptContent:
            return "Esta versão da Apple Intelligence não comporta esta operação."
        @unknown default:
            return error.localizedDescription
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

    private static func message(
        for reason: SystemLanguageModel.Availability.UnavailableReason
    ) -> String {
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

    // MARK: - Auxiliares

    private static func join(
        completed: [String],
        current: String,
        chunks: [TextChunk]
    ) -> String {
        var result = ""
        for (index, text) in completed.enumerated() where index < chunks.count {
            result += text + chunks[index].separatorAfter
        }
        return result + current
    }
}
