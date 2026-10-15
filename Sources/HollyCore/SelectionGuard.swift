import Foundation

/// Decide se a seleção capturada continua valendo no momento de aplicar o
/// resultado.
///
/// O caminho preferido do app confere o intervalo pela Acessibilidade. Editores
/// baseados no Chromium — os aplicativos feitos em Electron, entre eles — não
/// publicam `AXSelectedTextRange`, e ali aquela conferência é impossível.
/// Repetir o ⌘C e comparar com o texto capturado dá a mesma garantia por outro
/// caminho: se o editor devolve o mesmo texto, é porque a seleção continua onde
/// estava, e o ⌘V seguinte vai substituir exatamente o que o ⌘C acabou de ler.
public enum SelectionGuard {
    /// `true` quando os dois textos descrevem a mesma seleção.
    ///
    /// A comparação exige conteúdo idêntico; só o espaço das pontas é tolerado,
    /// porque alguns editores acrescentam uma quebra de linha ao copiar. Texto
    /// vazio nunca vale: sem seleção não há o que substituir.
    public static func holds(captured: String, recopied: String) -> Bool {
        if captured.isEmpty || recopied.isEmpty { return false }
        if captured == recopied { return true }

        let aparado = captured.trimmingCharacters(in: .whitespacesAndNewlines)
        let relido = recopied.trimmingCharacters(in: .whitespacesAndNewlines)
        return !aparado.isEmpty && aparado == relido
    }
}
