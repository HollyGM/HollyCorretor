import Foundation

/// Mantém entrada, saída e instruções dentro da janela do modelo, com um teto
/// adicional para a quantidade de texto que ele consegue transformar por vez.
public enum TextProcessingBudget {
    public static let charactersPerToken = 3.2
    public static let minimumChunkCharacters = 900

    public static func maximumCharacters(
        context: Int,
        instructionTokens: Int,
        action: CorrectionAction,
        outputCeiling: Int
    ) -> Int {
        // `.max` representa uma saída sem teto próprio no modelo da nuvem.
        // Dividi-lo por razões menores que 1 e converter imediatamente para
        // Int ultrapassaria Int.max. A conversão só ocorre depois dos limites.
        let unlimitedOutput = outputCeiling == .max
        let byOutput = unlimitedOutput
            ? Double.infinity
            : Double(outputCeiling) / action.expectedOutputRatio

        // A subtração em Double também evita overflow se o sistema informar
        // tamanhos extremos. Para janelas usuais, os inteiros são exatos.
        let usable = Double(context) - Double(instructionTokens) - 256
        let byContext = usable > 0
            ? usable / (1 + action.expectedOutputRatio) * charactersPerToken
            : 4_000
        let ceiling = unlimitedOutput ? 40_000.0 : 8_000.0
        let budget = max(
            Double(minimumChunkCharacters),
            min(byOutput, byContext, ceiling)
        )
        return Int(budget)
    }
}
