import AppIntents
import Foundation

/// Gera o `Metadata.appintents` que o Xcode produziria ao compilar.
///
/// O macOS não examina o binário para descobrir as App Intents: ele lê esses
/// metadados dentro do pacote. O Xcode os extrai numa etapa própria
/// (`appintentsmetadataprocessor`), que não existe nas Command Line Tools. Sem
/// eles, as ações compilam, mas a Siri e o app Atalhos nunca as veem.
///
/// O formato segue o que o Xcode 27 grava nos aplicativos da Apple. Os nomes
/// de tipo vêm do próprio Swift (`_mangledTypeName`), e os títulos, das
/// próprias intents, para os metadados não divergirem do código.
enum AppIntentsMetadata {
    static let commandLineFlag = "--gerar-metadados-app-intents"

    static func write(to directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let options: JSONSerialization.WritingOptions = [
            .prettyPrinted, .sortedKeys, .withoutEscapingSlashes
        ]
        try JSONSerialization.data(withJSONObject: document(), options: options)
            .write(to: directory.appendingPathComponent("extract.actionsdata"))
        // "*" indica um gerador que não é a versão do Xcode, como fazem outros
        // aplicativos que montam os metadados fora dele.
        try JSONSerialization.data(
            withJSONObject: ["toolsVersion": "*", "version": "3.0"],
            options: options
        ).write(to: directory.appendingPathComponent("version.json"))
    }

    // MARK: - Documento

    static func document() -> [String: Any] {
        let actions: [[String: Any]] = [
            action(RevisarSelecaoIntent.self),
            action(ReescreverSelecaoIntent.self),
            action(FormalizarSelecaoIntent.self),
            action(SimplificarSelecaoIntent.self),
            action(ResumirSelecaoIntent.self),
            action(
                AplicarNaSelecaoIntent.self,
                parameters: [acaoParameter, instrucaoParameter],
                summary: summary(
                    IntentTexts.resumoSelecao,
                    parameters: ["acao"],
                    others: ["instrucao"]
                )
            ),
            action(
                ProcessarTextoIntent.self,
                parameters: [acaoParameter, textoParameter, instrucaoParameter],
                outputType: stringType,
                summary: summary(
                    IntentTexts.resumoTexto,
                    parameters: ["acao", "texto"],
                    others: ["instrucao"]
                )
            )
        ]

        return [
            "actions": Dictionary(
                uniqueKeysWithValues: actions.map { ($0["identifier"] as! String, $0) }
            ),
            "assistantEntities": [],
            "assistantIntentNegativePhrases": [],
            "assistantIntents": [],
            "autoShortcutProviderMangledName": mangledName(AtalhosDaSiri.self),
            "autoShortcuts": CatalogoDaSiri.atalhos.map(autoShortcut),
            "entities": [String: Any](),
            "enums": [acaoEnum()],
            "generator": ["name": "xcode-tools", "version": "*"],
            "negativePhrases": [],
            "queries": [String: Any](),
            "shortcutTileColor": tileColorIndex(AtalhosDaSiri.shortcutTileColor),
            "version": 1
        ]
    }

    // MARK: - Ações

    private static func action<Intent: AppIntent>(
        _ type: Intent.Type,
        parameters: [[String: Any]] = [],
        outputType: [String: Any]? = nil,
        summary: [String: Any]? = nil
    ) -> [String: Any] {
        let mangled = mangledName(type)
        var action: [String: Any] = [
            "assistantDefinedSchemaTraits": [],
            "assistantDefinedSchemas": [],
            "authenticationPolicy": 0,
            "availabilityAnnotations": anyPlatform,
            "effectiveBundleIdentifiers": [],
            "fullyQualifiedTypeName": String(reflecting: type),
            "identifier": String(describing: type),
            "isAuthPolExplicit": false,
            "isDiscoverable": Intent.isDiscoverable,
            "mangledTypeName": mangled,
            "mangledTypeNameByBundleIdentifier": [String: Any](),
            "mangledTypeNameByBundleIdentifierV2": [String: Any](),
            "mangledTypeNameV2": mangled,
            "openAppWhenRun": false,
            "outputFlags": 0,
            "parameters": parameters,
            "presentationStyle": 0,
            "requiredCapabilities": [],
            "supportedModes": Intent.supportedModes.rawValue,
            "systemProtocolMetadata": [],
            "systemProtocolMetadataV2": [],
            "systemProtocols": [],
            "title": localized(Intent.title),
            "typeSpecificMetadata": [],
            "visibilityMetadata": [
                "assistantOnly": false,
                "isDiscoverable": Intent.isDiscoverable
            ]
        ]
        if let description = Intent.description {
            action["descriptionMetadata"] = [
                "descriptionText": localized(description.descriptionText),
                "searchKeywords": description.searchKeywords.map(localized)
            ]
        }
        if let outputType { action["outputType"] = outputType }
        if let summary {
            action["actionConfiguration"] = ["actionSummary": ["wrapper": summary]]
        }
        return action
    }

    private static func summary(
        _ format: String,
        parameters: [String],
        others: [String]
    ) -> [String: Any] {
        [
            "otherParameterIdentifiers": others,
            "summaryString": [
                "formatString": format,
                "parameterIdentifiers": parameters
            ]
        ]
    }

    // MARK: - Parâmetros

    private static var acaoParameter: [String: Any] {
        parameter(
            name: "acao",
            title: IntentTexts.acao,
            description: IntentTexts.acaoDescricao,
            valueType: ["linkEnumeration": ["wrapper": ["identifier": enumIdentifier]]],
            resolvableInputTypes: [],
            defaultValue: AcaoDeTexto.revisar.rawValue
        )
    }

    private static var textoParameter: [String: Any] {
        parameter(
            name: "texto",
            title: IntentTexts.texto,
            description: IntentTexts.textoDescricao,
            valueType: stringType,
            resolvableInputTypes: stringResolvableInputTypes,
            connectsToPreviousResult: true
        )
    }

    private static var instrucaoParameter: [String: Any] {
        parameter(
            name: "instrucao",
            title: IntentTexts.instrucao,
            description: IntentTexts.instrucaoDescricao,
            valueType: stringType,
            resolvableInputTypes: stringResolvableInputTypes,
            isOptional: true
        )
    }

    private static func parameter(
        name: String,
        title: LocalizedStringResource,
        description: LocalizedStringResource,
        valueType: [String: Any],
        resolvableInputTypes: [[String: Any]],
        isOptional: Bool = false,
        defaultValue: String? = nil,
        connectsToPreviousResult: Bool = false
    ) -> [String: Any] {
        var typeSpecificMetadata: [Any] = []
        if let defaultValue {
            typeSpecificMetadata = [
                "LNValueTypeSpecificMetadataKeyDefaultValue",
                ["string": ["wrapper": defaultValue]]
            ]
        }
        return [
            "capabilities": defaultValue == nil ? 0 : 1,
            "dynamicOptionsSupport": 0,
            "inputConnectionBehavior": connectsToPreviousResult ? 2 : 0,
            "isInput": connectsToPreviousResult,
            "isOptional": isOptional,
            "name": name,
            "parameterDescription": localized(description),
            "resolvableInputTypes": resolvableInputTypes,
            "title": localized(title),
            "typeSpecificMetadata": typeSpecificMetadata,
            "valueType": valueType
        ]
    }

    private static var stringType: [String: Any] { primitive(0) }

    /// Os tipos a partir dos quais o sistema converte um valor para texto,
    /// na mesma ordem que o Xcode grava para parâmetros `String`.
    private static var stringResolvableInputTypes: [[String: Any]] {
        [
            ["kindValue": 0, "valueType": primitive(0)],
            ["kindValue": 0, "valueType": primitive(2)],
            [
                "kindValue": 0,
                "valueType": [
                    "array": ["wrapper": ["capabilities": 3, "memberValueType": primitive(2)]]
                ]
            ]
        ]
    }

    private static func primitive(_ typeIdentifier: Int) -> [String: Any] {
        ["primitive": ["wrapper": ["typeIdentifier": typeIdentifier]]]
    }

    // MARK: - Enumeração

    private static let enumIdentifier = String(describing: AcaoDeTexto.self)

    private static func acaoEnum() -> [String: Any] {
        let representations = AcaoDeTexto.caseDisplayRepresentations
        let cases: [[String: Any]] = AcaoDeTexto.allCases.map { acao in
            var display: [String: Any] = [
                "title": localized(representations[acao]?.title ?? acao.titulo)
            ]
            let synonyms = representations[acao]?.synonyms ?? acao.sinonimos
            if !synonyms.isEmpty { display["synonyms"] = synonyms.map(localized) }
            let image: [String: Any] = [
                "systemImageName": ["_0": acao.correctionAction.symbolName]
            ]
            display["image"] = image
            display["imageV2"] = image
            return ["displayRepresentation": display, "identifier": acao.rawValue]
        }
        return [
            "assistantDefinedSchemas": [],
            "availabilityAnnotations": anyPlatform,
            "cases": cases,
            "displayTypeName": localized(AcaoDeTexto.typeDisplayRepresentation.name),
            "effectiveBundleIdentifiers": [],
            "fullyQualifiedTypeName": String(reflecting: AcaoDeTexto.self),
            "identifier": enumIdentifier,
            "isSystem": false,
            "mangledTypeName": mangledName(AcaoDeTexto.self),
            "mangledTypeNameByBundleIdentifier": [String: Any](),
            "systemProtocolMetadata": [],
            "visibilityMetadata": ["assistantOnly": false, "isDiscoverable": true]
        ]
    }

    // MARK: - Frases da Siri

    private static func autoShortcut(_ atalho: AtalhoDaSiri) -> [String: Any] {
        [
            "actionIdentifier": atalho.identificador,
            "availabilityAnnotations": anyPlatform,
            "phraseTemplates": atalho.frases.map(localized),
            "shortTitle": localized(atalho.tituloCurto),
            "systemImageName": atalho.simbolo
        ]
    }

    // MARK: - Auxiliares

    private static var anyPlatform: [String: Any] {
        ["LNPlatformNameWildcard": ["introducedVersion": "*"]]
    }

    private static func localized(_ resource: LocalizedStringResource) -> [String: Any] {
        var value: [String: Any] = ["alternatives": [], "key": resource.key]
        if let table = resource.table { value["table"] = table }
        return value
    }

    private static func localized(_ key: String) -> [String: Any] {
        ["alternatives": [], "key": key]
    }

    /// O sistema localiza o tipo no binário por este nome. Um nome errado não
    /// falha na compilação: a ação aparece, mas não roda. Por isso vem do
    /// compilador, e não é escrito à mão.
    ///
    /// Duas conferências protegem contra erros silenciosos: o nome precisa
    /// levar de volta ao mesmo tipo, e não pode usar a forma comprimida que o
    /// compilador adota quando uma palavra do módulo se repete no nome do tipo
    /// (`AcaoHolly` viraria `04AcaoA0`). Os metadados da Apple nunca trazem
    /// essa forma, então ela não é um risco que valha correr.
    private static func mangledName(_ type: Any.Type) -> String {
        guard let name = _mangledTypeName(type) else {
            fatalError("Sem nome de tipo para \(type).")
        }
        guard let resolved = _typeByName(name),
              ObjectIdentifier(resolved) == ObjectIdentifier(type) else {
            fatalError("O nome \(name) não leva de volta a \(type).")
        }
        let module = String(reflecting: type).prefix { $0 != "." }
        let plain = "\(module.count)\(module)"
        let typeName = String(describing: type)
        guard name.hasPrefix(plain), name.contains("\(typeName.count)\(typeName)") else {
            fatalError("O nome de \(type) foi comprimido (\(name)); evite repetir palavras do módulo no nome do tipo.")
        }
        return name
    }

    /// Posição da cor na enumeração, que é como os metadados a registram
    /// (os aplicativos da Apple confirmam: Notas, amarelo, grava 3).
    private static func tileColorIndex(_ color: ShortcutTileColor) -> Int {
        let order: [ShortcutTileColor] = [
            .red, .orange, .tangerine, .yellow, .lime, .teal, .lightBlue, .blue,
            .navy, .grape, .purple, .pink, .grayBlue, .grayGreen, .grayBrown
        ]
        return order.firstIndex(of: color) ?? 14
    }
}
