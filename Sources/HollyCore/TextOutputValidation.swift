import Foundation

public enum TextOutputValidationError: LocalizedError {
    case incompleteResponse

    public var errorDescription: String? {
        "O modelo retornou apenas parte do texto. O resultado não foi aplicado. Tente novamente com um trecho menor."
    }
}

/// Ações que preservam o conteúdo não podem terminar aceitando uma resposta
/// truncada, mesmo quando o bloco já ficou pequeno demais para uma nova divisão.
public enum TextOutputValidation {
    public static func lostContent(
        output: String,
        input: String,
        action: CorrectionAction
    ) -> Bool {
        guard let floor = action.minimumOutputRatio else { return false }
        return Double(output.count) < Double(input.count) * floor
    }

    public static func validated(
        _ output: String,
        input: String,
        action: CorrectionAction
    ) throws -> String {
        guard !lostContent(output: output, input: input, action: action) else {
            throw TextOutputValidationError.incompleteResponse
        }
        return output
    }
}
