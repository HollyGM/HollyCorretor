import AppIntents
import Foundation
import HollyCore

// MARK: - Textos compartilhados com os metadados

/// Rótulos usados tanto pelas App Intents quanto pelos metadados que o
/// `AppIntentsMetadata` grava no pacote. O Xcode extrairia esses textos do
/// código ao compilar; o SwiftPM das Command Line Tools não, então os dois
/// lados leem daqui para não divergirem.
enum IntentTexts {
    static let acao: LocalizedStringResource = "Ação"
    static let acaoDescricao: LocalizedStringResource = "O que fazer com o texto."
    static let texto: LocalizedStringResource = "Texto"
    static let textoDescricao: LocalizedStringResource = "O texto que será processado."
    static let instrucao: LocalizedStringResource = "Instrução"
    static let instrucaoDescricao: LocalizedStringResource =
        "Usada pela ação Instrução personalizada. Ex.: “Traduza para o inglês”."

    static let resumoSelecao = "Aplicar ${acao} ao texto selecionado"
    static let resumoTexto = "Aplicar ${acao} a ${texto}"
}

// MARK: - Ações

/// As ações oferecidas à Siri e ao app Atalhos. O salvamento em Markdown fica
/// de fora porque depende de uma janela de salvamento, não do modelo.
enum AcaoDeTexto: String, AppEnum, CaseIterable {
    case revisar
    case reescrever
    case formalizar
    case simplificar
    case resumir
    case amigavel
    case profissional
    case conciso
    case pontosPrincipais
    case lista
    case tabela
    case personalizada

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Ação do HollyCorretor")
    }

    static var caseDisplayRepresentations: [AcaoDeTexto: DisplayRepresentation] {
        Dictionary(uniqueKeysWithValues: allCases.map { acao in
            (
                acao,
                DisplayRepresentation(
                    title: acao.titulo,
                    image: .init(systemName: acao.correctionAction.symbolName),
                    synonyms: acao.sinonimos
                )
            )
        })
    }

    /// Substantivos, para o resumo do app Atalhos ler bem:
    /// "Aplicar Revisão ao texto selecionado".
    var titulo: LocalizedStringResource {
        switch self {
        case .revisar: "Revisão"
        case .reescrever: "Reescrita"
        case .formalizar: "Formalização (juridiquês)"
        case .simplificar: "Simplificação para o cliente"
        case .resumir: "Resumo"
        case .amigavel: "Tom amigável"
        case .profissional: "Tom profissional"
        case .conciso: "Versão concisa"
        case .pontosPrincipais: "Pontos principais"
        case .lista: "Lista"
        case .tabela: "Tabela"
        case .personalizada: "Instrução personalizada"
        }
    }

    /// Outras formas de pedir a mesma ação, reconhecidas pela Siri.
    var sinonimos: [LocalizedStringResource] {
        switch self {
        case .revisar: ["Revisar", "Corrigir", "Correção ortográfica"]
        case .reescrever: ["Reescrever", "Melhorar o texto"]
        case .formalizar: ["Formalizar", "Linguagem jurídica"]
        case .simplificar: ["Simplificar", "Linguagem simples"]
        case .resumir: ["Resumir"]
        case .amigavel: ["Amigável"]
        case .profissional: ["Profissional"]
        case .conciso: ["Conciso", "Enxugar"]
        case .pontosPrincipais: ["Tópicos"]
        case .lista: ["Lista numerada"]
        case .tabela: ["Tabela em Markdown"]
        case .personalizada: ["Personalizada"]
        }
    }

    var correctionAction: CorrectionAction {
        switch self {
        case .revisar: .correct
        case .reescrever: .rewrite
        case .formalizar: .formalize
        case .simplificar: .simplify
        case .resumir: .summarize
        case .amigavel: .friendly
        case .profissional: .professional
        case .conciso: .concise
        case .pontosPrincipais: .keyPoints
        case .lista: .list
        case .tabela: .table
        case .personalizada: .custom
        }
    }
}

// MARK: - Erros

/// Mensagem que a Siri fala e o app Atalhos mostra quando a ação não acontece.
struct HollyIntentError: Error, CustomLocalizedStringResourceConvertible {
    let mensagem: String

    init(_ mensagem: String) {
        self.mensagem = mensagem
    }

    var localizedStringResource: LocalizedStringResource { "\(mensagem)" }
}

// MARK: - Ações sobre o texto selecionado

/// Liga as App Intents ao aplicativo em execução. A Siri e o app Atalhos rodam
/// a ação dentro do próprio HollyCorretor, que já está aberto na barra de menus
/// ou é aberto pelo sistema só para isso.
@MainActor
enum IntentBridge {
    static func aplicarNaSelecao(
        _ action: CorrectionAction,
        instrucao: String? = nil
    ) async throws {
        guard let app = HollyCorretorApp.shared else {
            throw HollyIntentError("O HollyCorretor ainda está abrindo. Tente de novo em instantes.")
        }
        let instrucao = instrucao?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await app.performFromIntent(
                action,
                customInstruction: instrucao?.isEmpty == false ? instrucao : nil
            )
        } catch {
            throw HollyIntentError("\(error.title). \(error.message)")
        }
    }
}

struct RevisarSelecaoIntent: AppIntent {
    static var title: LocalizedStringResource { "Revisar texto selecionado" }
    static var description: IntentDescription? {
        IntentDescription("Corrige ortografia, gramática, acentuação e pontuação do texto selecionado no aplicativo em uso.")
    }
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await IntentBridge.aplicarNaSelecao(.correct)
        return .result()
    }
}

struct ReescreverSelecaoIntent: AppIntent {
    static var title: LocalizedStringResource { "Reescrever texto selecionado" }
    static var description: IntentDescription? {
        IntentDescription("Reescreve o texto selecionado no aplicativo em uso com mais clareza e fluidez.")
    }
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await IntentBridge.aplicarNaSelecao(.rewrite)
        return .result()
    }
}

struct FormalizarSelecaoIntent: AppIntent {
    static var title: LocalizedStringResource { "Formalizar texto selecionado" }
    static var description: IntentDescription? {
        IntentDescription("Adapta o texto selecionado no aplicativo em uso para linguagem jurídica formal.")
    }
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await IntentBridge.aplicarNaSelecao(.formalize)
        return .result()
    }
}

struct SimplificarSelecaoIntent: AppIntent {
    static var title: LocalizedStringResource { "Simplificar texto selecionado" }
    static var description: IntentDescription? {
        IntentDescription("Torna o texto selecionado no aplicativo em uso acessível para quem não tem formação jurídica.")
    }
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await IntentBridge.aplicarNaSelecao(.simplify)
        return .result()
    }
}

struct ResumirSelecaoIntent: AppIntent {
    static var title: LocalizedStringResource { "Resumir texto selecionado" }
    static var description: IntentDescription? {
        IntentDescription("Gera um resumo executivo do texto selecionado no aplicativo em uso.")
    }
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await IntentBridge.aplicarNaSelecao(.summarize)
        return .result()
    }
}

/// Todas as ações num só bloco do app Atalhos, com a ação como parâmetro.
struct AplicarNaSelecaoIntent: AppIntent {
    static var title: LocalizedStringResource { "Aplicar ação ao texto selecionado" }
    static var description: IntentDescription? {
        IntentDescription("Aplica uma ação do HollyCorretor ao texto selecionado no aplicativo em uso, com a mesma conferência antes de substituir.")
    }
    static var supportedModes: IntentModes { .background }

    @Parameter(title: IntentTexts.acao, description: IntentTexts.acaoDescricao, default: .revisar)
    var acao: AcaoDeTexto

    @Parameter(title: IntentTexts.instrucao, description: IntentTexts.instrucaoDescricao)
    var instrucao: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Aplicar \(\.$acao) ao texto selecionado") {
            \.$instrucao
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await IntentBridge.aplicarNaSelecao(acao.correctionAction, instrucao: instrucao)
        return .result()
    }
}

// MARK: - Ação sobre um texto qualquer

/// Processa um texto recebido do app Atalhos e devolve o resultado, sem tocar
/// em documento nenhum. Serve para atalhos que leem a área de transferência,
/// um arquivo ou um texto ditado.
struct ProcessarTextoIntent: AppIntent {
    static var title: LocalizedStringResource { "Processar texto" }
    static var description: IntentDescription? {
        IntentDescription(
            "Revisa, reescreve, formaliza, simplifica ou resume um texto com a Apple Intelligence e devolve o resultado.",
            searchKeywords: ["corrigir", "revisar", "reescrever", "resumir", "formalizar"]
        )
    }
    static var supportedModes: IntentModes { .background }

    @Parameter(title: IntentTexts.acao, description: IntentTexts.acaoDescricao, default: .revisar)
    var acao: AcaoDeTexto

    @Parameter(
        title: IntentTexts.texto,
        description: IntentTexts.textoDescricao,
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var texto: String

    @Parameter(title: IntentTexts.instrucao, description: IntentTexts.instrucaoDescricao)
    var instrucao: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Aplicar \(\.$acao) a \(\.$texto)") {
            \.$instrucao
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let entrada = texto
        guard !entrada.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HollyIntentError("Informe um texto para processar.")
        }
        let action = acao.correctionAction
        let resultado: String
        do {
            resultado = try await TextProcessor().process(
                entrada,
                action: action,
                customInstruction: instrucao
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw HollyIntentError(error.localizedDescription)
        }
        await MainActor.run {
            if AppPreferences.shouldSaveHistory {
                HistoryStore.shared.add(actionTitle: action.title, processedText: resultado)
            }
        }
        return .result(value: resultado)
    }
}

// MARK: - Frases da Siri

/// Um App Shortcut: aparece pronto no app Atalhos e na Siri, sem a pessoa
/// precisar montar nada. Toda frase tem de conter `${applicationName}`, que a
/// Siri reconhece pelo nome do app e pelos nomes de `INAlternativeAppNames`.
struct AtalhoDaSiri: Sendable {
    typealias Fabrica<Intent: AppIntent> = @Sendable (
        _ frases: [AppShortcutPhrase<Intent>],
        _ tituloCurto: LocalizedStringResource
    ) -> AppShortcut

    let identificador: String
    let tituloCurto: LocalizedStringResource
    let simbolo: String
    let frases: [String]
    private let fabricar: @Sendable () -> AppShortcut

    /// `fabricar` existe porque o `systemImageName` da AppIntents só aceita um
    /// literal no ponto da chamada; o mesmo símbolo vai em `simbolo` para os
    /// metadados.
    init<Intent: AppIntent>(
        _ tipo: Intent.Type,
        tituloCurto: LocalizedStringResource,
        simbolo: String,
        frases: [String],
        fabricar: @escaping Fabrica<Intent>
    ) {
        self.identificador = String(describing: tipo)
        self.tituloCurto = tituloCurto
        self.simbolo = simbolo
        self.frases = frases
        self.fabricar = {
            fabricar(frases.map { AppShortcutPhrase<Intent>($0) }, tituloCurto)
        }
    }

    var appShortcut: AppShortcut { fabricar() }
}

enum CatalogoDaSiri {
    static let atalhos: [AtalhoDaSiri] = [
        AtalhoDaSiri(
            RevisarSelecaoIntent.self,
            tituloCurto: "Revisar seleção",
            simbolo: "text.magnifyingglass",
            frases: [
                "Revisar texto com o ${applicationName}",
                "Revisar com o ${applicationName}",
                "Revisar no ${applicationName}",
                "Corrigir texto com o ${applicationName}",
                "Corrigir com o ${applicationName}",
                "Corrigir no ${applicationName}"
            ]
        ) {
            AppShortcut(
                intent: RevisarSelecaoIntent(), phrases: $0, shortTitle: $1,
                systemImageName: "text.magnifyingglass"
            )
        },
        AtalhoDaSiri(
            ReescreverSelecaoIntent.self,
            tituloCurto: "Reescrever seleção",
            simbolo: "arrow.triangle.2.circlepath",
            frases: [
                "Reescrever texto com o ${applicationName}",
                "Reescrever com o ${applicationName}",
                "Reescrever no ${applicationName}"
            ]
        ) {
            AppShortcut(
                intent: ReescreverSelecaoIntent(), phrases: $0, shortTitle: $1,
                systemImageName: "arrow.triangle.2.circlepath"
            )
        },
        AtalhoDaSiri(
            FormalizarSelecaoIntent.self,
            tituloCurto: "Formalizar seleção",
            simbolo: "building.columns",
            frases: [
                "Formalizar texto com o ${applicationName}",
                "Formalizar com o ${applicationName}",
                "Formalizar no ${applicationName}"
            ]
        ) {
            AppShortcut(
                intent: FormalizarSelecaoIntent(), phrases: $0, shortTitle: $1,
                systemImageName: "building.columns"
            )
        },
        AtalhoDaSiri(
            SimplificarSelecaoIntent.self,
            tituloCurto: "Simplificar seleção",
            simbolo: "hand.raised",
            frases: [
                "Simplificar texto com o ${applicationName}",
                "Simplificar com o ${applicationName}",
                "Simplificar no ${applicationName}"
            ]
        ) {
            AppShortcut(
                intent: SimplificarSelecaoIntent(), phrases: $0, shortTitle: $1,
                systemImageName: "hand.raised"
            )
        },
        AtalhoDaSiri(
            ResumirSelecaoIntent.self,
            tituloCurto: "Resumir seleção",
            simbolo: "text.alignleft",
            frases: [
                "Resumir texto com o ${applicationName}",
                "Resumir com o ${applicationName}",
                "Resumir no ${applicationName}"
            ]
        ) {
            AppShortcut(
                intent: ResumirSelecaoIntent(), phrases: $0, shortTitle: $1,
                systemImageName: "text.alignleft"
            )
        }
    ]
}

struct AtalhosDaSiri: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        return CatalogoDaSiri.atalhos.map(\.appShortcut)
    }

    /// Laranja, como a identidade visual da suíte Holly.
    static var shortcutTileColor: ShortcutTileColor { .orange }
}
