import AppKit
import ApplicationServices
import OSLog

/// Observa o mouse em todo o sistema e avisa quando há um texto selecionado
/// que o HollyCorretor pode oferecer-se para trabalhar: ao soltar o botão
/// depois de arrastar, ou ao clicar com o botão direito sobre a seleção.
///
/// Por que o mouse e não notificações de acessibilidade: `kAXSelectedTextChanged`
/// só é publicado por aplicativos que implementam a árvore de acessibilidade
/// completa, o que exclui boa parte dos aplicativos feitos em Electron — que são
/// justamente os que a ferramenta da Apple não alcança. Soltar o botão do mouse
/// e clicar com o botão direito são sinais que existem em qualquer aplicativo.
///
/// Por que o clique direito: o item do menu Serviços só existe nos menus de
/// contexto nativos do macOS. Os aplicativos em Electron montam os próprios
/// menus, sem Serviços. Fazer a pastilha aparecer ao lado do menu que o
/// aplicativo abriu dá ao clique direito o mesmo resultado em todos.
///
/// O tap é apenas ouvinte (`listenOnly`): não consome nem altera evento nenhum,
/// então nada do comportamento normal do sistema muda.
@MainActor
final class SelectionWatcher {
    /// O gesto que revelou a seleção. Define o tamanho mínimo que vale a pena
    /// oferecer e onde a pastilha aparece.
    enum Trigger: Sendable {
        /// A pessoa arrastou o mouse e soltou o botão.
        case drag
        /// A pessoa clicou com o botão direito (ou Control + clique) sobre a
        /// seleção. O aplicativo abriu o próprio menu de contexto nesse ponto.
        case rightClick
    }

    struct Hit {
        let text: String
        let element: AXUIElement
        let app: NSRunningApplication
        let range: CFRange?
        /// Retângulo da seleção na tela, em coordenadas do Cocoa.
        let anchor: NSRect
        let trigger: Trigger
        /// Onde estava o ponteiro no gesto, em coordenadas do Cocoa.
        let pointer: NSPoint
    }

    var onShow: ((Hit) -> Void)?
    /// A pastilha deixou de fazer sentido: a seleção sumiu, mudou, ou o
    /// aplicativo da frente passou a ser um dos ignorados. Diz respeito só à
    /// pastilha — não significa que a pessoa tenha desistido do painel.
    var onHide: (() -> Void)?
    /// A pessoa clicou ou rolou fora da interface do HollyCorretor. É o único
    /// sinal que significa desistência, e por isso o único que pode encerrar um
    /// painel já aberto. Mantê-lo separado de `onHide` evita que o painel se
    /// feche sozinho só porque a seleção deixou de existir quando ele tomou o
    /// foco — que é justamente o que acontece assim que ele aparece.
    var onDismissOutside: (() -> Void)?

    /// Responde se um clique caiu sobre a interface do próprio HollyCorretor.
    /// Sem isto, o clique na pastilha seria tratado como "o usuário clicou fora"
    /// e desfaria a seleção antes de a ação chegar a rodar.
    var shouldIgnoreClick: ((NSPoint) -> Bool)?

    /// Um clique caiu sobre a interface do HollyCorretor. Enquanto um menu de
    /// contexto de outro aplicativo está aberto, o sistema entrega o clique ao
    /// menu — que apenas se fecha — e a pastilha nunca o recebe. O tap vê o
    /// clique de qualquer forma; avisar por aqui faz o primeiro clique bastar.
    var onInterfaceClick: ((NSPoint) -> Void)?

    /// Oferecer a pastilha ao soltar o mouse depois de arrastar.
    var respondsToDrag = true
    /// Oferecer a pastilha ao clicar com o botão direito sobre a seleção.
    var respondsToRightClick = true {
        didSet { probesRightClicks = respondsToRightClick }
    }

    /// O que havia sob o ponteiro e com o foco no instante do clique direito,
    /// lido dentro do próprio callback do tap — antes, portanto, de o
    /// aplicativo receber o clique e abrir o menu de contexto. Depois de
    /// aberto, o menu cobre o ponto clicado e passa a ser o elemento sob o
    /// ponteiro, e o foco do aplicativo vai para o próprio menu enquanto ele
    /// dura; qualquer sondagem feita depois só encontraria o menu. A seleção,
    /// essa só é lida mais tarde, quando o aplicativo já a ajustou ao clique.
    ///
    /// Os elementos são referências imutáveis a objetos de outro processo;
    /// atravessam para o ator sem estado compartilhado.
    private struct RightClickProbe: @unchecked Sendable {
        let under: AXUIElement?
        let focused: AXUIElement?
        let pid: pid_t?
    }

    /// Espelho de `respondsToRightClick` legível pelo callback em C, que não
    /// pode consultar o ator. Só decide se a sondagem é feita.
    nonisolated(unsafe) private var probesRightClicks = true

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// A referência que o tap leva como `refcon`, para ser devolvida em
    /// `stop()`. Ver o porquê em `start()`.
    private var tapOwner: Unmanaged<SelectionWatcher>?
    private var pending: Task<Void, Never>?
    private var vigil: Task<Void, Never>?
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

    /// Prazo curto para as consultas de Acessibilidade feitas logo após o
    /// clique. Um aplicativo travado responderia só depois do prazo padrão, de
    /// vários segundos, e congelaria o HollyCorretor junto. Os elementos
    /// escolhidos voltam ao prazo padrão antes de serem entregues, porque é com
    /// eles que o resultado será escrito.
    private let probeTimeout: Float = 0.5

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

        // O tap leva uma referência contada a este objeto. Enquanto o tap
        // existir, o objeto existe — o callback em C não tem como saber que
        // quem criou o vigia já o soltou, e um ponteiro solto ali seria acesso
        // a memória liberada a cada clique do sistema. `stop()` devolve a
        // referência, e é ele que permite este objeto morrer.
        let owner = Unmanaged.passRetained(self)

        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                // Este callback é uma função em C, chamada por uma fonte do run
                // loop principal: a thread é a principal, mas não há tarefa nem
                // executor do Swift em curso. Por isso ele não toca em nada
                // isolado — tira do evento apenas valores e entrega o resto a
                // `deliver`, que entra no MainActor pela fila do próprio ator.
                //
                // A exceção é a sondagem do clique direito, feita aqui mesmo:
                // o evento só segue para o aplicativo clicado depois que este
                // callback devolve, e é a única chance de ver o que está sob
                // o ponteiro antes de o menu de contexto cobri-lo. São
                // chamadas de Acessibilidade com prazo curto, sem nada do ator.
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let flags = event.flags
                let location = event.location
                var probe: RightClickProbe?
                let watcher = Unmanaged<SelectionWatcher>.fromOpaque(refcon).takeUnretainedValue()
                if watcher.probesRightClicks,
                   type == .rightMouseDown || (type == .leftMouseDown && flags.contains(.maskControl)) {
                    probe = SelectionWatcher.probeRightClick(at: location)
                }
                SelectionWatcher.deliver(type, at: location, flags: flags, probe: probe, from: refcon)
                return Unmanaged.passUnretained(event)
            },
            userInfo: owner.toOpaque()
        ) else {
            owner.release()
            logger.error("Não foi possível criar o event tap. Verifique a permissão de Acessibilidade.")
            return false
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)

        tap = created
        source = runLoopSource
        tapOwner = owner
        logger.info("Vigia de seleção ativo.")
        return true
    }

    func stop() {
        pending?.cancel()
        pending = nil
        vigil?.cancel()
        vigil = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        // Só depois de o tap estar invalidado e fora do run loop: enquanto ele
        // estiver de pé, o callback ainda pode chegar e precisa do objeto.
        tapOwner?.release()
        tapOwner = nil
        onHide?()
        logger.info("Vigia de seleção desligado.")
    }

    /// Encerra a conferência periódica da seleção. Deve ser chamado quando o
    /// painel de ações assume: dali em diante o texto já foi capturado, e o
    /// próprio painel toma o foco — a seleção original deixa de existir, o que
    /// faria a conferência fechar o painel recém-aberto.
    func suspendSelectionVigil() {
        vigil?.cancel()
        vigil = nil
    }

    /// O sistema desliga o tap se ele demorar demais para responder. Religar é
    /// barato e evita que o recurso morra em silêncio.
    func reenableIfNeeded() {
        guard let tap, !CGEvent.tapIsEnabled(tap: tap) else { return }
        logger.info("O sistema desligou o event tap; religando.")
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: - Eventos

    /// Ponte entre o callback em C do event tap e este objeto, que é isolado ao
    /// MainActor.
    ///
    /// Fica fora de todo isolamento de propósito, e por isso não lê nem escreve
    /// nada do objeto: desembrulha o ponteiro e enfileira o trabalho, que só
    /// então roda isolado. Era a conferência de isolamento, e não o trabalho,
    /// que derrubava o app a partir daqui: `MainActor.assumeIsolated` obriga o
    /// runtime a comparar o executor em curso com o do MainActor e, num callback
    /// em C, não há executor em curso nenhum para comparar — em 15/10/2026 essa
    /// comparação travou dentro do próprio runtime
    /// (`swift_task_isCurrentExecutorWithFlags`), com a thread principal
    /// correta e tudo. Uma tarefa `@MainActor` não compara nada: ela é
    /// enfileirada no ator e já acorda isolada.
    ///
    /// A tarefa passa a segurar o objeto no instante em que é criada, então o
    /// vigia não pode morrer entre o clique e o tratamento dele.
    nonisolated private static func deliver(
        _ type: CGEventType,
        at location: CGPoint,
        flags: CGEventFlags,
        probe: RightClickProbe?,
        from refcon: UnsafeMutableRawPointer
    ) {
        let watcher = Unmanaged<SelectionWatcher>.fromOpaque(refcon).takeUnretainedValue()
        Task { @MainActor in watcher.handle(type, at: location, flags: flags, probe: probe) }
    }

    /// Lê o elemento sob o ponteiro e o campo com foco do aplicativo dono
    /// dele. Roda no callback do tap, antes de o clique chegar ao aplicativo.
    /// Prazo curto em tudo: um aplicativo travado não pode segurar o tap, que
    /// o sistema desligaria por demora.
    nonisolated private static func probeRightClick(at location: CGPoint) -> RightClickProbe {
        let timeout: Float = 0.3
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, timeout)

        var under: AXUIElement?
        AXUIElementCopyElementAtPosition(systemWide, Float(location.x), Float(location.y), &under)

        var owner: pid_t?
        var pid: pid_t = 0
        if let under, AXUIElementGetPid(under, &pid) == .success, pid > 0 {
            owner = pid
        }

        var focused: AXUIElement?
        let root = owner.map { AXUIElementCreateApplication($0) } ?? systemWide
        AXUIElementSetMessagingTimeout(root, timeout)
        var value: AnyObject?
        if AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &value) == .success,
           let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
            focused = (value as! AXUIElement)
            if owner == nil, AXUIElementGetPid(focused!, &pid) == .success, pid > 0 {
                owner = pid
            }
        }
        return RightClickProbe(under: under, focused: focused, pid: owner)
    }

    private func handle(
        _ type: CGEventType,
        at location: CGPoint,
        flags: CGEventFlags,
        probe: RightClickProbe?
    ) {
        switch type {
        case .leftMouseUp:
            guard !isOnOwnInterface(location) else { return }
            // Control + clique abre o menu de contexto como o botão direito; o
            // soltar que vem depois não é o fim de um arrastar.
            guard respondsToDrag, !flags.contains(.maskControl) else { return }
            vigil?.cancel()
            scheduleCheck(trigger: .drag, at: location)
        case .leftMouseDown:
            // O clique na própria pastilha não pode ser lido como "clicou fora".
            // E, com um menu de contexto de outro aplicativo aberto, é só por
            // aqui que ele chega: o menu consome o clique e apenas se fecha.
            if isOnOwnInterface(location) {
                onInterfaceClick?(Self.cocoaPoint(fromQuartz: location))
                return
            }
            pending?.cancel()
            vigil?.cancel()
            onHide?()
            onDismissOutside?()
            if flags.contains(.maskControl), respondsToRightClick, let probe {
                scheduleCheck(trigger: .rightClick, at: location, probe: probe)
            }
        case .rightMouseDown:
            guard !isOnOwnInterface(location) else { return }
            pending?.cancel()
            vigil?.cancel()
            onHide?()
            onDismissOutside?()
            if respondsToRightClick, let probe {
                scheduleCheck(trigger: .rightClick, at: location, probe: probe)
            }
        case .scrollWheel:
            pending?.cancel()
            vigil?.cancel()
            onHide?()
            onDismissOutside?()
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            reenableIfNeeded()
        default:
            break
        }
    }

    /// A seleção só fica legível alguns milissegundos depois do clique, porque o
    /// aplicativo ainda está processando o próprio evento. No clique direito a
    /// espera é um pouco maior: o aplicativo pode mover a seleção para a
    /// palavra clicada e ainda está abrindo o menu de contexto.
    private func scheduleCheck(
        trigger: Trigger,
        at location: CGPoint,
        probe: RightClickProbe? = nil
    ) {
        pending?.cancel()
        let delay: UInt64 = trigger == .drag ? 120_000_000 : 160_000_000
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self else { return }
            self.check(trigger: trigger, at: location, probe: probe)
        }
    }

    private func check(trigger: Trigger, at location: CGPoint, probe: RightClickProbe?) {
        guard let found = findSelection(trigger: trigger, at: location, probe: probe) else {
            onHide?()
            return
        }
        let (element, text, app) = found
        guard let bundle = app.bundleIdentifier, !ignoredBundleIdentifiers.contains(bundle) else {
            onHide?()
            return
        }
        guard isWorthOffering(text, trigger: trigger) else {
            onHide?()
            return
        }

        // O elemento volta ao prazo padrão: é por ele que o resultado será
        // escrito, e um prazo curto faria a escrita falhar num editor lento.
        AXUIElementSetMessagingTimeout(element, 0)

        let hit = Hit(
            text: text,
            element: element,
            app: app,
            range: selectedTextRange(of: element),
            anchor: selectionRect(of: element) ?? cursorAnchor(),
            trigger: trigger,
            pointer: Self.cocoaPoint(fromQuartz: location)
        )
        logger.info(
            "Seleção encontrada por \(trigger == .drag ? "arrastar" : "clique direito", privacy: .public) em \(bundle, privacy: .public): \(text.count, privacy: .public) caracteres."
        )
        onShow?(hit)
        watchUntilSelectionEnds(hit)
    }

    /// Localiza o elemento com a seleção e o aplicativo dono dele.
    ///
    /// Ao arrastar, basta o elemento com foco do sistema: a pessoa acabou de
    /// soltar o mouse nele. No clique direito o foco engana — num aplicativo
    /// em Electron, o campo de digitação pode continuar com o foco enquanto a
    /// seleção está no texto da conversa —, então a busca começa no elemento
    /// que estava sob o ponteiro no instante do clique e sobe pelos
    /// ancestrais até achar quem publica a seleção; só depois recorre ao
    /// campo que tinha o foco. Os dois vêm da sondagem feita no clique: a esta
    /// altura o menu de contexto já cobre o ponto clicado e tem o foco.
    private func findSelection(
        trigger: Trigger,
        at location: CGPoint,
        probe: RightClickProbe?
    ) -> (AXUIElement, String, NSRunningApplication)? {
        switch trigger {
        case .drag:
            guard let front = NSWorkspace.shared.frontmostApplication,
                  let element = focusedElement(),
                  let text = selectedText(of: element) else { return nil }
            return (element, text, front)

        case .rightClick:
            var candidates: [AXUIElement] = []
            var current = probe?.under
            var depth = 0
            while let element = current, depth < 12 {
                // Se a sondagem chegou tarde e já pegou o menu, ele não leva a
                // nada: a seleção está no campo que tinha o foco.
                if isMenuElement(element) { break }
                candidates.append(element)
                current = parent(of: element)
                depth += 1
            }
            if let focused = probe?.focused, !isMenuElement(focused) {
                candidates.append(focused)
            }
            let clickedApp = probe?.pid.flatMap { NSRunningApplication(processIdentifier: $0) }
            for element in candidates {
                AXUIElementSetMessagingTimeout(element, probeTimeout)
                if let text = selectedText(of: element),
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let app = clickedApp ?? application(owning: element) {
                    return (element, text, app)
                }
            }
            return nil
        }
    }

    private func isMenuElement(_ element: AXUIElement) -> Bool {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success,
              let role = value as? String else { return false }
        return role == kAXMenuRole || role == kAXMenuItemRole
            || role == kAXMenuBarRole || role == kAXMenuBarItemRole
    }

    /// Trocar de aplicativo com ⌘Tab não produz um evento de mouse. O texto pode
    /// continuar selecionado no editor anterior, mas a pastilha já não pertence
    /// ao aplicativo da frente. Confere também o campo e o intervalo original.
    ///
    /// O elemento guardado é consultado primeiro: é nele que o resultado será
    /// escrito. Os editores baseados no Chromium entregam um objeto novo para
    /// o mesmo campo a cada consulta, então a identidade não serve de critério;
    /// o que vale é o mesmo texto continuar selecionado, no mesmo intervalo.
    func isCurrent(_ hit: Hit) -> Bool {
        drift(of: hit) == nil
    }

    /// Por que a seleção guardada deixou de valer, ou `nil` se ainda vale. O
    /// motivo vai para o log quando a pastilha some, porque cada editor
    /// publica a seleção de um jeito e é isso que explica um sumiço.
    private func drift(of hit: Hit) -> String? {
        guard !hit.app.isTerminated else { return "o aplicativo encerrou" }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == hit.app.processIdentifier else {
            return "outro aplicativo veio para a frente"
        }

        if let text = selectedText(of: hit.element) {
            guard text == hit.text else {
                return "o elemento passou a ter \(text.count) caracteres selecionados"
            }
            guard rangesMatch(hit.range, selectedTextRange(of: hit.element)) else {
                return "o intervalo do elemento mudou"
            }
            return nil
        }
        guard let focused = focusedElement() else { return "o elemento não responde e nada tem foco" }
        guard let text = selectedText(of: focused) else {
            return "o elemento não responde e o campo com foco não publica seleção"
        }
        guard text == hit.text else {
            return "o elemento não responde e o campo com foco tem \(text.count) caracteres selecionados"
        }
        guard rangesMatch(hit.range, selectedTextRange(of: focused)) else {
            return "o elemento não responde e o intervalo do campo com foco difere"
        }
        return nil
    }

    /// Dois intervalos conhecidos precisam coincidir. Quando um dos lados não
    /// publica intervalo — editores como o Word respondem por elementos
    /// diferentes a cada consulta, nem todos com `AXSelectedTextRange` —, o
    /// texto igual basta: a pastilha é só um convite, e quem escreve confere
    /// o intervalo de novo antes de tocar no documento.
    private func rangesMatch(_ original: CFRange?, _ current: CFRange?) -> Bool {
        guard let original, let current else { return true }
        return original.location == current.location && original.length == current.length
    }

    /// Enquanto a pastilha está à mostra, confere de vez em quando se a seleção
    /// ainda existe. Sem isto ela ficaria na tela depois de a pessoa começar a
    /// digitar — e escutar o teclado exigiria a permissão de Monitoramento de
    /// Entrada, que este recurso não precisa para nada mais.
    private func watchUntilSelectionEnds(_ hit: Hit) {
        vigil?.cancel()
        vigil = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled, let self else { return }
                if let reason = self.drift(of: hit) {
                    self.logger.info("Pastilha recolhida: \(reason, privacy: .public).")
                    self.onHide?()
                    return
                }
            }
        }
    }

    /// Ao arrastar, evita o botão pular na tela a cada clique que selecione uma
    /// palavra solta ou um espaço. No clique direito a intenção é explícita, e
    /// uma palavra só já vale: é o caso de corrigir um termo.
    private func isWorthOffering(_ text: String, trigger: Trigger) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trigger {
        case .drag: return trimmed.count >= 12
        case .rightClick: return !trimmed.isEmpty
        }
    }

    // MARK: - Acessibilidade

    private func focusedElement() -> AXUIElement? {
        focusedElement(of: AXUIElementCreateSystemWide())
    }

    private func focusedElement(of root: AXUIElement) -> AXUIElement? {
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(
            root,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success,
            let focused,
            CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return (focused as! AXUIElement)
    }

    /// O elemento sob um ponto da tela, em coordenadas do Quartz (origem no
    /// topo), que é como o evento as entrega.
    private func elementAtPosition(_ location: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, probeTimeout)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWide,
            Float(location.x),
            Float(location.y),
            &element
        ) == .success else { return nil }
        return element
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXParentAttribute as CFString,
            &value
        ) == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func application(owning element: AXUIElement) -> NSRunningApplication? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0 else { return nil }
        return NSRunningApplication(processIdentifier: pid)
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

    private func selectedTextRange(of element: AXUIElement) -> CFRange? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        ) == .success, let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
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

    private func isOnOwnInterface(_ location: CGPoint) -> Bool {
        guard let shouldIgnoreClick else { return false }
        let point = Self.cocoaPoint(fromQuartz: location)
        return shouldIgnoreClick(point)
    }

    static func cocoaPoint(fromQuartz point: CGPoint) -> NSPoint {
        guard let primary = NSScreen.screens.first else { return point }
        return NSPoint(x: point.x, y: primary.frame.maxY - point.y)
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
