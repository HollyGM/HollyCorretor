/// Marcações para o texto que o HollyCorretor coloca na área de transferência
/// apenas para colar no documento (e não porque a pessoa pediu para copiar).
///
/// Os tipos seguem a convenção de nspasteboard.org: gerenciadores de área de
/// transferência que a respeitam (Raycast, Paste, Alfred, Maccy e outros) não
/// guardam esse conteúdo no histórico. A parte "só neste Mac" — que impede a
/// Área de Transferência Universal de levar o texto ao iPhone ou ao iPad — é
/// feita no app, com `NSPasteboard.prepareForNewContents(with: .currentHostOnly)`.
public enum ClipboardPrivacy {
    /// Conteúdo de vida curta, que não deve ir para o histórico.
    public static let transientType = "org.nspasteboard.TransientType"
    /// Conteúdo confidencial, que não deve ser exibido nem guardado.
    public static let concealedType = "org.nspasteboard.ConcealedType"

    /// Tipos acrescentados, sem dados, a todo texto colocado só para colar.
    public static let markerTypes = [transientType, concealedType]
}
