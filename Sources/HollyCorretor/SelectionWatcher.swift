import AppKit
import ApplicationServices
import OSLog

/// Observa o mouse em todo o sistema e avisa quando o usuário acaba de
/// selecionar um texto, para o botão flutuante aparecer ao lado da seleção.
///
/// Por que o mouse e não notificações de acessibilidade: `kAXSelectedTextChanged`
/// só é publicado por aplicativos que implementam a árvore de acessibilidade
/// completa, o que exclui boa parte dos aplicativos feitos em Electron — que são
/// justamente os que a ferramenta da Apple não alcança. Soltar o botão do mouse
/// é um sinal que existe em qualquer aplicativo.
///
/// O tap é apenas ouvinte (`listenOnly`): não consome nem altera evento nenhum,
/// então nada do comportamento normal do sistema muda.
@MainActor
final class SelectionWatcher {
    struct Hit {
        let text: String
        let element: AXUIElement
        /// Retângulo da seleção na tela, em coordenadas do Cocoa.
        let anchor: NSRect
    }

    var onShow: ((Hit) -> Void)?
    var onHide: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var pending: Task<Void, Never>?
    private let logger = Logger(
        subsystem: "com.hollycorretor.app",
        category: "SelectionWatcher"
    )

    /// Aplicativos em que o botão não deve aparecer: o próprio HollyCorretor e
    /// telas onde uma seleção quase nunca é texto para reescrever.
    private let ignoredBundleIdentifiers: Set<String> = [
        "com.hollycorretor.app",
        "com.apple.loginwindow",
        "com.apple.SecurityAgent"
    ]

    var isRunning: Bool { tap != nil }

    // MARK: - Ciclo de vida

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        // Só eventos de mouse. Incluir teclado obrigaria a pedir também a
        // permissão de Monitoramento de Entrada, e o ganho não compensa.
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)

        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let watcher = Unmanaged<SelectionWatcher>
                    .fromOpaque(refcon)
                    .takeUnretainedValue()
                MainActor.assumeIsolated { watcher.handle(type) }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("Não foi possível criar o event tap. Verifique a permissão de Acessibilidade.")
            return false
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)

        tap = created
        source = runLoopSource
        logger.info("Vigia de seleção ativo.")
        return true
    }

    func stop() {
        pending?.cancel()
        pending = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        onHide?()
        logger.info("Vigia de seleção desligado.")
    }

    /// O sistema desliga o tap se ele demorar demais para responder. Religar é
    /// barato e evita que o recurso morra em silêncio.
    func reenableIfNeeded() {
        guard let tap, !CGEvent.tapIsEnabled(tap: tap) else { return }
        logger.info("O sistema desligou o event tap; religando.")
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: - Eventos

    private func handle(_ type: CGEventType) {
        switch type {
        case .leftMouseUp:
            scheduleCheck()
        case .leftMouseDown, .rightMouseDown, .scrollWheel:
            pending?.cancel()
            onHide?()
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            reenableIfNeeded()
        default:
            break
        }
    }

    /// A seleção só fica legível alguns milissegundos depois do clique, porque o
    /// aplicativo ainda está processando o próprio evento.
    private func scheduleCheck() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, let self else { return }
            self.check()
        }
    }

    private func check() {
        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundle = front.bundleIdentifier,
              !ignoredBundleIdentifiers.contains(bundle) else {
            onHide?()
            return
        }

        guard let element = focusedElement(),
              let text = selectedText(of: element),
              isWorthOffering(text) else {
            onHide?()
            return
        }

        let anchor = selectionRect(of: element) ?? cursorAnchor()
        onShow?(Hit(text: text, element: element, anchor: anchor))
    }

    /// Evita o botão pular na tela a cada clique que selecione uma palavra solta
    /// ou um espaço.
    private func isWorthOffering(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 12
    }

    // MARK: - Acessibilidade

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success,
            let focused,
            CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return (focused as! AXUIElement)
    }

    private func selectedText(of element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        ) == .success else { return nil }
        return value as? String
    }

    /// Retângulo da seleção convertido para as coordenadas do Cocoa. Nem todo
    /// aplicativo responde a esta consulta; quando não responde, o botão vai
    /// para junto do cursor.
    private func selectionRect(of element: AXUIElement) -> NSRect? {
        var range: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &range
        ) == .success, let range else { return nil }

        var bounds: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            range,
            &bounds
        ) == .success,
            let bounds,
            CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect),
              rect.width > 0 || rect.height > 0 else { return nil }

        return Self.cocoaRect(fromQuartz: rect)
    }

    private func cursorAnchor() -> NSRect {
        let point = NSEvent.mouseLocation
        return NSRect(x: point.x, y: point.y, width: 1, height: 1)
    }

    /// A acessibilidade devolve coordenadas com origem no topo da tela
    /// principal; as janelas do Cocoa usam origem embaixo.
    static func cocoaRect(fromQuartz rect: CGRect) -> NSRect {
        guard let primary = NSScreen.screens.first else { return rect }
        let flippedY = primary.frame.maxY - rect.origin.y - rect.height
        return NSRect(x: rect.origin.x, y: flippedY, width: rect.width, height: rect.height)
    }
}
