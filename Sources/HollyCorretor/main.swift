import AppKit
import ApplicationServices
import Carbon.HIToolbox
import HollyCore
import OSLog
import ServiceManagement
import UniformTypeIdentifiers
@preconcurrency import KeyboardShortcuts

private struct ClipboardSnapshot: @unchecked Sendable {
    private let items: [NSPasteboardItem]

    init(pasteboard: NSPasteboard = .general) {
        self.items = pasteboard.pasteboardItems?.map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    func restoreIfUnchanged(
        since expectedChangeCount: Int?,
        to pasteboard: NSPasteboard = .general
    ) {
        guard let expectedChangeCount,
              pasteboard.changeCount == expectedChangeCount else { return }
        restore(to: pasteboard)
    }
}

/// O texto capturado e como ele foi obtido. Guardar o elemento de
/// Acessibilidade permite devolver o resultado escrevendo direto nele, sem
/// passar pela área de transferência nem simular teclas.
private struct CapturedSelection {
    let text: String
    let element: AXUIElement?
    let range: CFRange?
    let anchor: NSRect
    let clipboardChangeCount: Int?
}

private struct LocatedServiceSelection {
    let app: NSRunningApplication
    let element: AXUIElement
    let range: CFRange?
    let anchor: NSRect
    let distanceFromPointer: CGFloat
}

/// A janela de prévia também pode ser fechada por ⌘W, mesmo com o botão padrão
/// oculto. Centralizar esse caminho aqui garante que cancelar pelo teclado limpe
/// a operação exatamente como o botão Cancelar.
@MainActor
private final class PreviewPanel: NSPanel {
    var onClose: (() -> Void)?

    override func close() {
        let handler = onClose
        onClose = nil
        handler?()
        super.close()
    }
}

@MainActor
final class HollyCorretorApp: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let processor = TextProcessor()
    private let logger = Logger(
        subsystem: "com.hollycorretor.app",
        category: "HollyCorretor"
    )
    private var statusItem: NSStatusItem?
    private var settingsWindowController: NSWindowController?
    private var historyWindowController: NSWindowController?
    private var previewPanel: PreviewPanel?
    private var generationPanelWindow: FloatingPanel?
    private var resultPanelWindow: FloatingPanel?
    private var isProcessing = false
    private var currentTask: Task<Void, Never>?
    private var selectionWatcher: SelectionWatcher?
    private var selectionPill: SelectionPill?
    private var actionPanelWindow: FloatingPanel?
    private var actionPanelDismissAfter = Date.distantPast
    private var lastHit: SelectionWatcher.Hit?
    private var pillMenuItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?
    private var aiWarningItem: NSMenuItem?
    private var aiWarningSeparator: NSMenuItem?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppPreferences.prepare()
        HistoryStore.prepare()
        NSApp.setActivationPolicy(.accessory)
        buildMenu()
        setupShortcuts()
        refreshAIStatus()
        startSelectionWatcherIfEnabled()

        NotificationCenter.default.addObserver(
            forName: .hollySelectionPillPreferenceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if AppPreferences.showsSelectionPill {
                    if !self.startSelectionWatcherIfEnabled() {
                        self.requestAccessibilityPermission()
                    }
                } else {
                    self.stopSelectionWatcher()
                }
            }
        }
    }

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "HollyCorretor")
        icon?.isTemplate = true
        item.button?.image = icon
        item.button?.toolTip = "HollyCorretor"

        let menu = NSMenu()
        menu.delegate = self

        let warningItem = NSMenuItem(title: "⚠︎ Apple Intelligence indisponível — clique para detalhes", action: #selector(showAIStatus), keyEquivalent: "")
        warningItem.target = self
        warningItem.isHidden = true
        menu.addItem(warningItem)
        aiWarningItem = warningItem

        let warningSeparator = NSMenuItem.separator()
        warningSeparator.isHidden = true
        menu.addItem(warningSeparator)
        aiWarningSeparator = warningSeparator

        let correctItem = NSMenuItem(title: "Revisar texto selecionado", action: #selector(correctSelectedText), keyEquivalent: "")
        correctItem.target = self
        menu.addItem(correctItem)

        let rewriteItem = NSMenuItem(title: "Reescrever texto selecionado", action: #selector(rewriteSelectedText), keyEquivalent: "")
        rewriteItem.target = self
        menu.addItem(rewriteItem)

        let formalizeItem = NSMenuItem(title: "Formalizar (juridiquês)", action: #selector(formalizeSelectedText), keyEquivalent: "")
        formalizeItem.target = self
        menu.addItem(formalizeItem)

        let simplifyItem = NSMenuItem(title: "Simplificar para o cliente", action: #selector(simplifySelectedText), keyEquivalent: "")
        simplifyItem.target = self
        menu.addItem(simplifyItem)

        let summarizeItem = NSMenuItem(title: "Resumir texto selecionado", action: #selector(summarizeSelectedText), keyEquivalent: "")
        summarizeItem.target = self
        menu.addItem(summarizeItem)

        let customItem = NSMenuItem(title: "Ação personalizada", action: #selector(customSelectedText), keyEquivalent: "")
        customItem.target = self
        menu.addItem(customItem)

        let markdownItem = NSMenuItem(title: "Salvar como Markdown", action: #selector(markdownSelectedText), keyEquivalent: "")
        markdownItem.target = self
        menu.addItem(markdownItem)

        menu.addItem(.separator())
        
        let historyItem = NSMenuItem(title: "Ver histórico...", action: #selector(showHistory), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)
        
        menu.addItem(.separator())

        let pillItem = NSMenuItem(title: "Botão ao selecionar texto", action: #selector(toggleSelectionPill), keyEquivalent: "")
        pillItem.target = self
        pillItem.state = AppPreferences.showsSelectionPill ? .on : .off
        pillItem.toolTip = "Mostra a pastilha do HollyCorretor ao lado de qualquer texto selecionado, em qualquer aplicativo."
        menu.addItem(pillItem)
        pillMenuItem = pillItem

        let loginItem = NSMenuItem(title: "Iniciar com o Mac", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        launchAtLoginItem = loginItem

        let settingsItem = NSMenuItem(title: "Preferências...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let accessibilityItem = NSMenuItem(title: "Permissão de Acessibilidade...", action: #selector(requestAccessibilityPermission), keyEquivalent: "")
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Sair", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            launchAtLoginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
            // A permissão pode ter sido concedida depois da abertura; tenta de
            // novo em vez de exigir que a pessoa reabra o aplicativo.
            if AppPreferences.showsSelectionPill, selectionWatcher?.isRunning != true {
                startSelectionWatcherIfEnabled()
            }
            selectionWatcher?.reenableIfNeeded()
            refreshPillMenuItem()
            refreshAIStatus()
        }
    }

    private func setupShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .correct) { [weak self] in self?.handle(action: .correct) }
        KeyboardShortcuts.onKeyUp(for: .rewrite) { [weak self] in self?.handle(action: .rewrite) }
        KeyboardShortcuts.onKeyUp(for: .rewriteAlt) { [weak self] in self?.handle(action: .rewrite) }
        KeyboardShortcuts.onKeyUp(for: .formalize) { [weak self] in self?.handle(action: .formalize) }
        KeyboardShortcuts.onKeyUp(for: .simplify) { [weak self] in self?.handle(action: .simplify) }
        KeyboardShortcuts.onKeyUp(for: .summarize) { [weak self] in self?.handle(action: .summarize) }
        KeyboardShortcuts.onKeyUp(for: .custom) { [weak self] in self?.handle(action: .custom) }
        KeyboardShortcuts.onKeyUp(for: .markdown) { [weak self] in self?.handle(action: .markdown) }
    }

    @objc private func correctSelectedText() { handle(action: .correct) }
    @objc private func rewriteSelectedText() { handle(action: .rewrite) }
    @objc private func formalizeSelectedText() { handle(action: .formalize) }
    @objc private func simplifySelectedText() { handle(action: .simplify) }
    @objc private func summarizeSelectedText() { handle(action: .summarize) }
    @objc private func customSelectedText() { handle(action: .custom) }
    @objc private func markdownSelectedText() { handle(action: .markdown) }

    /// O macOS não permite que um Serviço crie um submenu próprio. Em vez de
    /// anunciar treze itens soltos, o HollyCorretor anuncia uma única entrada no
    /// clique direito e abre aqui o painel de ações, como as Ferramentas de
    /// Escrita da Apple.
    @objc(hollyService:userData:error:) dynamic
    func hollyService(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        logger.info("Serviço HollyCorretor recebido.")
        guard !isProcessing else {
            logger.info("Serviço recusado: já há operação em andamento.")
            revealCurrentOperation()
            return
        }
        guard checkAccessibilityPermission(prompt: true) else {
            logger.error("Serviço recusado: permissão de Acessibilidade ausente.")
            showAlert(title: "Permissão necessária", message: "Ative Acessibilidade para o HollyCorretor.")
            return
        }
        guard let serviceText = extractPlainText(from: pboard) else {
            logger.error("Serviço recusado: pasteboard sem texto legível.")
            showAlert(title: "Nenhum texto selecionado", message: "Selecione o texto e tente novamente.")
            return
        }

        let located = locateServiceSelection(matching: serviceText)
        let targetApp = located?.app ?? NSWorkspace.shared.frontmostApplication
        let selectedElement = located?.element
        let selection = CapturedSelection(
            text: serviceText,
            element: selectedElement,
            range: located?.range,
            anchor: located?.anchor ?? cursorAnchor(),
            clipboardChangeCount: nil
        )
        logger.info(
            "Abrindo painel do Serviço: \(serviceText.count, privacy: .public) caracteres; destino=\(targetApp?.bundleIdentifier ?? "nenhum", privacy: .public); elemento=\(selectedElement != nil, privacy: .public); intervalo=\(selection.range != nil, privacy: .public)."
        )
        processor.prewarm()
        showActionPanel(for: selection, targetApp: targetApp, anchor: selection.anchor)
    }

    /// Encaminha para o salvamento em Markdown (que não usa o modelo) ou para o
    /// processamento pela Apple Intelligence.
    private func start(
        _ action: CorrectionAction,
        selection: CapturedSelection,
        targetApp: NSRunningApplication?,
        clipboardSnapshot: ClipboardSnapshot,
        customInstruction: String? = nil
    ) {
        // "Redigir…" pede a instrução na hora. Sem isto ela só poderia ser
        // trocada abrindo as Preferências, o que não combina com uma ação
        // acionada em cima do texto.
        var instruction = customInstruction
        if action == .custom, instruction == nil {
            guard let escrita = promptForInstruction() else {
                isProcessing = false
                updateStatusIcon(processing: false)
                clipboardSnapshot.restoreIfUnchanged(
                    since: selection.clipboardChangeCount
                )
                return
            }
            instruction = escrita
        }

        if action == .markdown {
            saveAsMarkdownFile(
                selection.text,
                clipboardSnapshot: clipboardSnapshot,
                clipboardChangeCount: selection.clipboardChangeCount
            )
        } else {
            processText(
                selection,
                action: action,
                targetApp: targetApp,
                clipboardSnapshot: clipboardSnapshot,
                customInstruction: instruction
            )
        }
    }

    /// Caixa curta para a instrução do "Redigir…". Devolve `nil` se a pessoa
    /// cancelar ou deixar em branco.
    private func promptForInstruction() -> String? {
        let alert = NSAlert()
        alert.messageText = "O que fazer com o texto?"
        alert.informativeText = "Ex.: “Traduza para o inglês”, “Deixe em tópicos”, “Responda a esta mensagem”."
        alert.addButton(withTitle: "Aplicar")
        alert.addButton(withTitle: "Cancelar")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "Descreva sua alteração"
        field.stringValue = AppPreferences.customPrompt ?? ""
        alert.accessoryView = field

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let texto = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return texto.isEmpty ? nil : texto
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            let window = NSWindow(contentViewController: SettingsViewController())
            window.styleMask = [.titled, .closable]
            window.title = "Preferências"
            window.center()
            window.setFrameAutosaveName("SettingsWindow")
            window.isReleasedWhenClosed = false
            window.delegate = self
            settingsWindowController = NSWindowController(window: window)
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }
    
    @objc private func showHistory() {
        if historyWindowController == nil {
            let window = NSWindow(contentViewController: HistoryViewController())
            window.styleMask = [.titled, .closable, .resizable]
            window.title = "Histórico de Correções"
            window.center()
            window.setFrameAutosaveName("HistoryWindow")
            window.isReleasedWhenClosed = false
            window.delegate = self
            historyWindowController = NSWindowController(window: window)
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        historyWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            _ = NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc private func requestAccessibilityPermission() {
        if checkAccessibilityPermission(prompt: true) {
            startSelectionWatcherIfEnabled()
            return
        }
        // O pedido do sistema só aparece uma vez por versão do binário; abrir o
        // painel direto evita a pessoa procurar onde autorizar.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            showAlert(
                title: "Não foi possível alterar a inicialização automática",
                message: error.localizedDescription
            )
        }
        launchAtLoginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Text Handling (Async/Await)

    private func handle(action: CorrectionAction) {
        logger.info("Ação pedida: \(action.title, privacy: .public)")
        guard !isProcessing else {
            logger.info("Recusada: já há um processamento em andamento.")
            revealCurrentOperation()
            return
        }
        guard checkAccessibilityPermission(prompt: true) else {
            logger.error("Recusada: sem permissão de Acessibilidade.")
            showAlert(title: "Permissão necessária", message: "Ative Acessibilidade.")
            return
        }

        let targetApp = NSWorkspace.shared.frontmostApplication
        let snapshot = ClipboardSnapshot()

        // Manda o sistema carregar o modelo agora, em paralelo com a captura da
        // seleção, em vez de só quando o texto já estiver em mãos.
        if action != .markdown { processor.prewarm() }

        if let selection = selectedTextViaAccessibility() {
            logger.info("Seleção lida pela Acessibilidade: \(selection.text.count, privacy: .public) caracteres.")
            isProcessing = true
            updateStatusIcon(processing: true)
            start(action, selection: selection, targetApp: targetApp, clipboardSnapshot: snapshot)
            return
        }

        // A partir daqui é preciso simular ⌘C. Com a entrada protegida ativa o
        // sistema descarta eventos sintéticos sem avisar, e o app pareceria
        // travado esperando um clipboard que nunca muda.
        guard !IsSecureEventInputEnabled() else {
            showAlert(
                title: "Entrada protegida ativa",
                message: "Um campo seguro (como o de uma senha) está em foco. Saia dele e tente novamente."
            )
            return
        }

        let fallbackElement = focusedAccessibilityElement(in: targetApp)
        let fallbackRange = fallbackElement.flatMap { selectedTextRange(of: $0) }
        let fallbackAnchor = fallbackElement.flatMap { selectionRect(of: $0) } ?? cursorAnchor()

        isProcessing = true
        updateStatusIcon(processing: true)

        Task {
            await waitForModifiersReleased()
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let baseline = pasteboard.changeCount

            sendKeyboardShortcut(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
            let clipboardChanged = await waitForClipboardChange(
                pasteboard: pasteboard,
                baseline: baseline,
                maxAttempts: 15
            )

            logger.info("Área de transferência mudou após ⌘C: \(clipboardChanged, privacy: .public)")
            if clipboardChanged, let selectedText = extractPlainText(from: pasteboard) {
                let selection = CapturedSelection(
                    text: selectedText,
                    element: fallbackElement,
                    range: fallbackRange,
                    anchor: fallbackAnchor,
                    clipboardChangeCount: pasteboard.changeCount
                )
                start(action, selection: selection, targetApp: targetApp, clipboardSnapshot: snapshot)
                return
            }

            isProcessing = false
            updateStatusIcon(processing: false)
            snapshot.restoreIfUnchanged(since: pasteboard.changeCount)
            showAlert(
                title: "Nenhum texto selecionado",
                message: "Selecione um texto e tente novamente. O HollyCorretor não usa “Selecionar tudo” automaticamente para evitar alterações indesejadas."
            )
        }
    }

    private func waitForModifiersReleased() async {
        let held: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        for _ in 0..<30 {
            let current = CGEventSource.flagsState(.hidSystemState)
            if current.intersection(held).isEmpty { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func waitForClipboardChange(pasteboard: NSPasteboard, baseline: Int, maxAttempts: Int) async -> Bool {
        for _ in 0..<maxAttempts {
            if pasteboard.changeCount != baseline { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    private func selectedTextViaAccessibility() -> CapturedSelection? {
        guard let element = focusedAccessibilityElement(),
              let text = selectedText(of: element),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return CapturedSelection(
            text: text,
            element: element,
            range: selectedTextRange(of: element),
            anchor: selectionRect(of: element) ?? cursorAnchor(),
            clipboardChangeCount: nil
        )
    }

    private func focusedAccessibilityElement(in app: NSRunningApplication? = nil) -> AXUIElement? {
        let root = app.map { AXUIElementCreateApplication($0.processIdentifier) }
            ?? AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let focused = focusedElement,
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return (focused as! AXUIElement)
    }

    /// Um Serviço não informa diretamente qual aplicativo o chamou. Na maior
    /// parte dos casos ele ainda é o aplicativo em primeiro plano, mas menus e
    /// automações podem mudar isso entre o clique e o callback. Procurar o texto
    /// selecionado nos aplicativos visíveis e preferir a seleção mais próxima
    /// do ponteiro identifica o editor de origem sem depender dessa corrida.
    private func locateServiceSelection(matching text: String) -> LocatedServiceSelection? {
        let pointer = NSEvent.mouseLocation
        let ownBundle = Bundle.main.bundleIdentifier
        var apps = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular
                && !app.isTerminated
                && !app.isHidden
                && app.bundleIdentifier != ownBundle
        }

        if let frontmost = NSWorkspace.shared.frontmostApplication,
           let index = apps.firstIndex(where: { $0.processIdentifier == frontmost.processIdentifier }) {
            apps.insert(apps.remove(at: index), at: 0)
        }

        var best: LocatedServiceSelection?
        for app in apps {
            guard let element = focusedAccessibilityElement(in: app),
                  selectedText(of: element) == text else { continue }

            let anchor = selectionRect(of: element) ?? cursorAnchor()
            let distance = distance(from: pointer, to: anchor)
            logger.info(
                "Seleção do Serviço encontrada em \(app.bundleIdentifier ?? "desconhecido", privacy: .public), distância=\(distance, privacy: .public)."
            )
            let match = LocatedServiceSelection(
                app: app,
                element: element,
                range: selectedTextRange(of: element),
                anchor: anchor,
                distanceFromPointer: distance
            )
            if best == nil || distance < best!.distanceFromPointer {
                best = match
            }
        }
        return best
    }

    private func distance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(max(rect.minX - point.x, point.x - rect.maxX), 0)
        let dy = max(max(rect.minY - point.y, point.y - rect.maxY), 0)
        return hypot(dx, dy)
    }

    private func selectedText(of element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func selectedTextRange(of element: AXUIElement) -> CFRange? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        ) == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    private func selectionRect(of element: AXUIElement) -> NSRect? {
        var rangeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        ) == .success,
            let rangeValue else { return nil }

        var boundsValue: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        ) == .success,
            let boundsValue,
            CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }

        var quartzRect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &quartzRect),
              quartzRect.width > 0 || quartzRect.height > 0 else { return nil }

        let primaryTop = NSScreen.screens.first?.frame.maxY ?? quartzRect.maxY
        return NSRect(
            x: quartzRect.minX,
            y: primaryTop - quartzRect.maxY,
            width: quartzRect.width,
            height: quartzRect.height
        )
    }

    private func cursorAnchor() -> NSRect {
        let cursor = NSEvent.mouseLocation
        return NSRect(x: cursor.x, y: cursor.y, width: 1, height: 1)
    }

    /// Escreve o resultado direto no campo de onde o texto saiu. Só age se a
    /// seleção ainda for exatamente a que foi capturada — caso a pessoa tenha
    /// clicado em outro lugar, não há o que substituir com segurança.
    private func replaceSelection(
        in selection: CapturedSelection,
        expecting original: String,
        with text: String
    ) -> Bool {
        guard let element = selection.element else { return false }

        // Alguns aplicativos escondem ou recolhem a seleção quando o painel do
        // HollyCorretor recebe o foco. Reaplicar o intervalo capturado devolve a
        // seleção exata antes de escrever e evita colar o resultado no cursor.
        if selectedText(of: element) != original {
            guard let range = selection.range,
                  setSelectedTextRange(range, of: element),
                  selectedText(of: element) == original else { return false }
        }

        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }

        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        ) == .success
    }

    private func setSelectedTextRange(_ range: CFRange, of element: AXUIElement) -> Bool {
        var mutableRange = range
        guard let value = AXValueCreate(.cfRange, &mutableRange) else { return false }
        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            value
        ) == .success
    }

    private func rangeAfterReplacing(_ selection: CapturedSelection, with text: String) -> CFRange? {
        guard let range = selection.range else { return nil }
        return CFRange(location: range.location, length: (text as NSString).length)
    }

    private func extractPlainText(from pboard: NSPasteboard) -> String? {
        if let text = pboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        if let attributedStrings = pboard.readObjects(forClasses: [NSAttributedString.self], options: nil) as? [NSAttributedString],
           let text = attributedStrings.first?.string,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        if let strings = pboard.readObjects(forClasses: [NSString.self], options: nil) as? [String],
           let text = strings.first,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        return nil
    }

    private func saveAsMarkdownFile(
        _ text: String,
        clipboardSnapshot: ClipboardSnapshot,
        clipboardChangeCount: Int?
    ) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let savePanel = NSSavePanel()
        savePanel.title = "Salvar como Markdown"
        savePanel.nameFieldStringValue = "Anotacao_\(timestamp).md"
        savePanel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText
        ]
        savePanel.canCreateDirectories = true

        NSApp.activate()
        savePanel.begin { [weak self] response in
            guard let self else { return }
            defer {
                self.isProcessing = false
                self.updateStatusIcon(processing: false)
                clipboardSnapshot.restoreIfUnchanged(
                    since: clipboardChangeCount
                )
            }

            guard response == .OK, let fileURL = savePanel.url else { return }
            do {
                try text.write(to: fileURL, atomically: true, encoding: .utf8)
                self.showSuccessFeedback(playPop: false)
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            } catch {
                self.showAlert(
                    title: "Erro ao salvar",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func makePreviewPanel() -> PreviewPanel {
        let panel = PreviewPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 320),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.center()
        return panel
    }

    /// Mantém o processamento junto do texto de origem. Quando o editor oferece
    /// os atributos de acessibilidade necessários, o resultado é aplicado no
    /// próprio documento e uma barra compacta permite conferir ou reverter.
    /// Editores que não permitem uma troca segura continuam recebendo a prévia
    /// tradicional, sem nenhuma colagem às cegas.
    private func processText(
        _ selection: CapturedSelection,
        action: CorrectionAction,
        targetApp: NSRunningApplication?,
        clipboardSnapshot: ClipboardSnapshot,
        customInstruction: String? = nil
    ) {
        showGenerationPanel(
            title: action.title,
            anchor: selection.anchor,
            onCancel: { [weak self] in
                self?.cancelCurrentOperation(
                    selection: selection,
                    clipboardSnapshot: clipboardSnapshot
                )
            }
        )
        returnFocus(to: targetApp)

        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                self.logger.info("Iniciando geração para \(action.title, privacy: .public)")
                var finalText = ""
                for try await update in self.processor.stream(
                    selection.text,
                    action: action,
                    customInstruction: customInstruction
                ) {
                    switch update {
                    case .partial:
                        break
                    case .finished(let text):
                        finalText = text
                    }
                }

                // Ao cancelar, o laço termina sem lançar erro: a sequência é
                // encerrada em vez de falhar. Sem esta checagem o painel já
                // fechado receberia um resultado parcial como se fosse final.
                guard !Task.isCancelled else { return }

                self.currentTask = nil
                self.closeGenerationPanel()
                let revisedText = finalText.isEmpty ? selection.text : finalText
                self.logger.info("Geração concluída: \(finalText.count, privacy: .public) caracteres.")
                self.updateStatusIcon(processing: false)

                if await self.applyInlineIfPossible(
                    revisedText,
                    selection: selection,
                    targetApp: targetApp
                ) {
                    self.showAppliedResultPanel(
                        originalSelection: selection,
                        revisedText: revisedText,
                        action: action,
                        targetApp: targetApp,
                        clipboardSnapshot: clipboardSnapshot
                    )
                } else {
                    self.showFallbackPreview(
                        revisedText,
                        selection: selection,
                        action: action,
                        targetApp: targetApp,
                        clipboardSnapshot: clipboardSnapshot
                    )
                }
            } catch is CancellationError {
                self.closeGenerationPanel()
            } catch {
                guard !Task.isCancelled else { return }
                self.currentTask = nil
                self.closeGenerationPanel()
                self.updateStatusIcon(processing: false)
                self.isProcessing = false
                clipboardSnapshot.restoreIfUnchanged(
                    since: selection.clipboardChangeCount
                )
                self.logger.error("Falha ao processar: \(error.localizedDescription, privacy: .public)")
                self.showAlert(
                    title: "Falha ao processar",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func showGenerationPanel(
        title: String,
        anchor: NSRect,
        onCancel: @escaping () -> Void
    ) {
        closeGenerationPanel()
        let controller = GenerationPanelController(title: title, onCancel: onCancel)
        let panel = FloatingPanel(size: NSSize(width: 310, height: 58), acceptsKeyboard: false)
        panel.contentViewController = controller
        panel.setContentSize(controller.view.fittingSize)
        panel.position(near: anchor, preferAbove: true, gap: 6)
        panel.orderFrontRegardless()
        generationPanelWindow = panel
    }

    private func closeGenerationPanel() {
        generationPanelWindow?.orderOut(nil)
        generationPanelWindow = nil
    }

    private func cancelCurrentOperation(
        selection: CapturedSelection,
        clipboardSnapshot: ClipboardSnapshot
    ) {
        currentTask?.cancel()
        currentTask = nil
        closeGenerationPanel()
        clipboardSnapshot.restoreIfUnchanged(since: selection.clipboardChangeCount)
        isProcessing = false
        updateStatusIcon(processing: false)
    }

    private func returnFocus(to targetApp: NSRunningApplication?) {
        guard let targetApp else { return }
        NSApp.yieldActivation(to: targetApp)
        targetApp.activate()
    }

    private func applyInlineIfPossible(
        _ revisedText: String,
        selection: CapturedSelection,
        targetApp: NSRunningApplication?
    ) async -> Bool {
        if revisedText == selection.text { return true }
        guard let targetApp else { return false }

        returnFocus(to: targetApp)
        guard await waitForAppActive(targetApp, maxAttempts: 30) else { return false }
        guard replaceSelection(in: selection, expecting: selection.text, with: revisedText) else {
            logger.info("O editor não permitiu aplicar a revisão diretamente; exibindo a prévia.")
            return false
        }
        logger.info("Resultado aplicado no documento pela Acessibilidade.")
        return true
    }

    private func showAppliedResultPanel(
        originalSelection: CapturedSelection,
        revisedText: String,
        action: CorrectionAction,
        targetApp: NSRunningApplication?,
        clipboardSnapshot: ClipboardSnapshot
    ) {
        closeResultPanel()
        let revisedSelection = CapturedSelection(
            text: revisedText,
            element: originalSelection.element,
            range: rangeAfterReplacing(originalSelection, with: revisedText),
            anchor: originalSelection.anchor,
            clipboardChangeCount: originalSelection.clipboardChangeCount
        )
        var showingOriginal = revisedText == originalSelection.text

        let controller = AppliedResultPanelController(
            title: action.title,
            changeCount: TextChangeCounter.count(from: originalSelection.text, to: revisedText),
            onRevert: { [weak self] in
                guard let self else { return }
                if !showingOriginal && !self.replaceSelection(
                    in: revisedSelection,
                    expecting: revisedText,
                    with: originalSelection.text
                ) {
                    self.showAlert(
                        title: "O texto mudou enquanto você revisava",
                        message: "Nada foi sobrescrito. Use Desfazer no aplicativo de origem se ainda quiser voltar ao texto anterior."
                    )
                    return
                }
                self.closeResultPanel()
                self.finishOperation(
                    keeping: originalSelection,
                    text: originalSelection.text,
                    targetApp: targetApp,
                    clipboardSnapshot: clipboardSnapshot,
                    playFeedback: false
                )
            },
            onToggleOriginal: { [weak self] wantsOriginal in
                guard let self else { return false }
                let changed: Bool
                if wantsOriginal {
                    changed = self.replaceSelection(
                        in: revisedSelection,
                        expecting: revisedText,
                        with: originalSelection.text
                    )
                } else {
                    changed = self.replaceSelection(
                        in: originalSelection,
                        expecting: originalSelection.text,
                        with: revisedText
                    )
                }
                guard changed else {
                    self.showAlert(
                        title: "O texto mudou enquanto você revisava",
                        message: "A visualização não foi alternada para evitar sobrescrever sua edição."
                    )
                    return false
                }
                showingOriginal = wantsOriginal
                self.returnFocus(to: targetApp)
                return true
            },
            onConfirm: { [weak self] in
                guard let self else { return }
                if showingOriginal && revisedText != originalSelection.text {
                    guard self.replaceSelection(
                        in: originalSelection,
                        expecting: originalSelection.text,
                        with: revisedText
                    ) else {
                        self.showAlert(
                            title: "O texto mudou enquanto você revisava",
                            message: "A revisão não foi confirmada para evitar sobrescrever sua edição."
                        )
                        return
                    }
                }
                self.closeResultPanel()
                if AppPreferences.shouldSaveHistory {
                    HistoryStore.shared.add(actionTitle: action.title, processedText: revisedText)
                }
                self.finishOperation(
                    keeping: revisedSelection,
                    text: revisedText,
                    targetApp: targetApp,
                    clipboardSnapshot: clipboardSnapshot,
                    playFeedback: true
                )
            }
        )

        let panel = FloatingPanel(size: NSSize(width: 420, height: 58), acceptsKeyboard: false)
        panel.contentViewController = controller
        panel.setContentSize(controller.view.fittingSize)
        panel.position(near: originalSelection.anchor, preferAbove: true, gap: 6)
        panel.orderFrontRegardless()
        resultPanelWindow = panel
    }

    private func closeResultPanel() {
        resultPanelWindow?.orderOut(nil)
        resultPanelWindow = nil
    }

    private func finishOperation(
        keeping selection: CapturedSelection,
        text: String,
        targetApp: NSRunningApplication?,
        clipboardSnapshot: ClipboardSnapshot,
        playFeedback: Bool
    ) {
        if let element = selection.element,
           let range = rangeAfterReplacing(selection, with: text) {
            let caret = CFRange(location: range.location + range.length, length: 0)
            _ = setSelectedTextRange(caret, of: element)
        }
        clipboardSnapshot.restoreIfUnchanged(since: selection.clipboardChangeCount)
        isProcessing = false
        returnFocus(to: targetApp)
        if playFeedback { showSuccessFeedback(playPop: false) }
        else { updateStatusIcon(processing: false) }
    }

    private func showFallbackPreview(
        _ revisedText: String,
        selection: CapturedSelection,
        action: CorrectionAction,
        targetApp: NSRunningApplication?,
        clipboardSnapshot: ClipboardSnapshot
    ) {
        let panel = makePreviewPanel()
        let previewController = PreviewViewController(
            originalText: selection.text,
            title: action.title,
            onConfirm: { [weak self, weak panel] finalText in
                panel?.onClose = nil
                self?.previewPanel = nil
                panel?.close()
                if AppPreferences.shouldSaveHistory {
                    HistoryStore.shared.add(actionTitle: action.title, processedText: finalText)
                }
                Task {
                    await self?.injectText(
                        finalText,
                        selection: selection,
                        targetApp: targetApp,
                        clipboardSnapshot: clipboardSnapshot
                    )
                    self?.isProcessing = false
                }
            },
            onCancel: { [weak self, weak panel] in
                panel?.onClose = nil
                self?.previewPanel = nil
                panel?.close()
                clipboardSnapshot.restoreIfUnchanged(since: selection.clipboardChangeCount)
                self?.isProcessing = false
                self?.updateStatusIcon(processing: false)
            },
            onCopy: { [weak self, weak panel] finalText in
                panel?.onClose = nil
                self?.previewPanel = nil
                panel?.close()
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(finalText, forType: .string)
                self?.isProcessing = false
                self?.showSuccessFeedback(playPop: false)
            }
        )
        panel.contentViewController = previewController
        panel.onClose = { [weak self] in
            self?.previewPanel = nil
            self?.isProcessing = false
            self?.updateStatusIcon(processing: false)
            clipboardSnapshot.restoreIfUnchanged(since: selection.clipboardChangeCount)
        }
        previewPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        previewController.finishStreaming(with: revisedText)
    }

    /// Uma segunda tentativa não deve virar apenas o alerta sonoro padrão do
    /// sistema. Se a prévia ainda existe, ela volta para a frente; nos poucos
    /// instantes em que o resultado está sendo aplicado, uma mensagem explica o
    /// que está acontecendo.
    private func revealCurrentOperation() {
        if let panel = resultPanelWindow {
            panel.orderFrontRegardless()
            return
        }
        if let panel = generationPanelWindow {
            panel.orderFrontRegardless()
            return
        }
        if let panel = previewPanel {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }
        if let panel = actionPanelWindow {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }
        showAlert(
            title: "Uma correção já está em andamento",
            message: "Aguarde a aplicação do resultado e tente novamente."
        )
    }

    private func injectText(
        _ finalText: String,
        selection: CapturedSelection,
        targetApp: NSRunningApplication?,
        clipboardSnapshot: ClipboardSnapshot
    ) async {
        guard let targetApp else {
            clipboardSnapshot.restoreIfUnchanged(
                since: selection.clipboardChangeCount
            )
            showAlert(
                title: "Aplicativo de destino não encontrado",
                message: "Copie o resultado pela prévia e cole-o manualmente."
            )
            return
        }

        NSApp.yieldActivation(to: targetApp)
        targetApp.activate()

        guard await waitForAppActive(targetApp, maxAttempts: 30) else {
            clipboardSnapshot.restoreIfUnchanged(since: selection.clipboardChangeCount)
            showAlert(
                title: "Não foi possível voltar ao aplicativo anterior",
                message: "O texto não foi colado. Tente usar o botão “Copiar” na prévia."
            )
            return
        }

        // Caminho preferido: escrever direto no campo pela Acessibilidade. Não
        // mexe na área de transferência, não simula teclas e não depende de
        // espera nenhuma.
        if replaceSelection(in: selection, expecting: selection.text, with: finalText) {
            logger.info("Resultado aplicado pela Acessibilidade.")
            showSuccessFeedback(playPop: false)
            return
        }

        guard prepareSelectionForPaste(selection) else {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(finalText, forType: .string)
            showAlert(
                title: "Resultado copiado",
                message: "O editor desfez a seleção e o HollyCorretor não colou no cursor para evitar duplicar o texto. Use ⌘V para colar o resultado no local desejado."
            )
            return
        }

        // Retaguarda: área de transferência + ⌘V.
        guard !IsSecureEventInputEnabled() else {
            clipboardSnapshot.restoreIfUnchanged(since: selection.clipboardChangeCount)
            showAlert(
                title: "Entrada protegida ativa",
                message: "Um campo seguro está em foco e impede a colagem. Use o botão “Copiar” na prévia."
            )
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(finalText, forType: .string) else {
            clipboardSnapshot.restore()
            showAlert(
                title: "Falha ao preparar o texto",
                message: "Não foi possível usar a área de transferência."
            )
            return
        }
        let injectionChangeCount = pasteboard.changeCount

        sendKeyboardShortcut(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        showSuccessFeedback(playPop: false)

        try? await Task.sleep(nanoseconds: 2_000_000_000)
        clipboardSnapshot.restoreIfUnchanged(since: injectionChangeCount)
    }

    private func prepareSelectionForPaste(_ selection: CapturedSelection) -> Bool {
        guard let element = selection.element,
              let range = selection.range,
              setSelectedTextRange(range, of: element) else { return false }

        // Quando o editor publica o texto selecionado, ele precisa continuar
        // idêntico ao original. Alguns editores só publicam o intervalo; nesse
        // caso o sucesso ao restaurá-lo é a melhor garantia disponível.
        guard let current = selectedText(of: element) else { return true }
        return current == selection.text
    }

    private func waitForAppActive(_ app: NSRunningApplication, maxAttempts: Int) async -> Bool {
        for _ in 0..<maxAttempts {
            if app.isActive {
                try? await Task.sleep(nanoseconds: 150_000_000)
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    private func showSuccessFeedback(playPop: Bool) {
        let checkIcon = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Sucesso")
        checkIcon?.isTemplate = true
        statusItem?.button?.image = checkIcon
        if playPop { NSSound(named: .init("Pop"))?.play() }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.updateStatusIcon(processing: false)
        }
    }

    private func updateStatusIcon(processing: Bool) {
        if processing {
            let icon = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Processando...")
            icon?.isTemplate = true
            statusItem?.button?.image = icon
            statusItem?.button?.toolTip = "Processando..."
        } else {
            refreshAIStatus()
        }
    }

    private func refreshAIStatus() {
        let message = TextProcessor.availabilityMessage()
        let unavailable = (message != nil)
        aiWarningItem?.isHidden = !unavailable
        aiWarningSeparator?.isHidden = !unavailable

        let symbolName = unavailable ? "exclamationmark.triangle.fill" : "wand.and.stars"
        let icon = NSImage(systemSymbolName: symbolName, accessibilityDescription: "HollyCorretor")
        icon?.isTemplate = true
        statusItem?.button?.image = icon
        statusItem?.button?.toolTip = unavailable ? "HollyCorretor — \(message ?? "")" : "HollyCorretor"
    }

    @objc private func showAIStatus() {
        if let message = TextProcessor.availabilityMessage() {
            showAlert(title: "Apple Intelligence indisponível", message: message)
        } else {
            showAlert(title: "Apple Intelligence ativa", message: "Tudo certo — o modelo on-device está disponível.")
        }
    }

    // MARK: - Botão flutuante de seleção

    /// Liga o vigia que faz a pastilha do HollyCorretor aparecer ao lado de
    /// qualquer texto selecionado, em qualquer aplicativo. É o que a ferramenta
    /// do sistema não consegue fazer fora dos campos de texto nativos.
    @discardableResult
    private func startSelectionWatcherIfEnabled() -> Bool {
        guard AppPreferences.showsSelectionPill else {
            stopSelectionWatcher()
            return false
        }
        guard checkAccessibilityPermission(prompt: false) else {
            // Sem a permissão o recurso simplesmente não acontece. Antes isso
            // era silencioso; agora o menu mostra o que está faltando.
            logger.info("Botão flutuante aguardando a permissão de Acessibilidade.")
            stopSelectionWatcher()
            return false
        }

        let pill = selectionPill ?? SelectionPill { [weak self] in
            self?.pillActivated()
        }
        selectionPill = pill

        let watcher = selectionWatcher ?? SelectionWatcher()
        watcher.onShow = { [weak self] hit in
            self?.lastHit = hit
            guard self?.actionPanelWindow == nil, self?.isProcessing == false else { return }
            pill.show(at: hit.anchor)
        }
        watcher.onHide = { [weak self] in
            self?.lastHit = nil
            pill.hide()
            // Clicar fora é a forma mais natural de dizer "não quero"; sem isto
            // o painel ficava aberto até uma ação ser escolhida.
            guard let self, Date() >= self.actionPanelDismissAfter else { return }
            self.closeActionPanel()
        }
        watcher.shouldIgnoreClick = { [weak self] point in
            guard let self else { return false }
            if let frame = pill.frame, frame.contains(point) { return true }
            if let frame = self.actionPanelWindow?.frame, frame.contains(point) { return true }
            return false
        }
        selectionWatcher = watcher

        let started = watcher.start()
        if !started {
            showAlert(
                title: "Não foi possível ligar o botão flutuante",
                message: "O macOS recusou o monitoramento de eventos. Confirme a permissão em Ajustes do Sistema › Privacidade e Segurança › Acessibilidade e reabra o HollyCorretor."
            )
        }
        refreshPillMenuItem()
        return started
    }

    /// Deixa visível no menu quando o botão flutuante está ligado mas parado
    /// por falta de permissão — o caso mais comum logo depois de recompilar.
    private func refreshPillMenuItem() {
        guard let item = pillMenuItem else { return }
        let wanted = AppPreferences.showsSelectionPill
        let running = selectionWatcher?.isRunning ?? false

        item.state = wanted ? .on : .off
        if wanted && !running {
            item.title = "Botão ao selecionar texto — falta permissão"
            item.toolTip = "Autorize o HollyCorretor em Ajustes do Sistema › Privacidade e Segurança › Acessibilidade."
        } else {
            item.title = "Botão ao selecionar texto"
            item.toolTip = "Mostra a pastilha do HollyCorretor ao lado de qualquer texto selecionado, em qualquer aplicativo."
        }
    }

    private func stopSelectionWatcher() {
        selectionWatcher?.stop()
        selectionWatcher = nil
        selectionPill?.hide()
        lastHit = nil
        pillMenuItem?.state = .off
    }

    @objc private func toggleSelectionPill() {
        let novo = !AppPreferences.showsSelectionPill
        UserDefaults.standard.set(novo, forKey: AppPreferences.selectionPillKey)
        guard novo else {
            stopSelectionWatcher()
            refreshPillMenuItem()
            return
        }
        if !startSelectionWatcherIfEnabled() {
            requestAccessibilityPermission()
        }
    }

    /// A pastilha foi clicada: guarda a seleção e abre o painel de ações.
    private func pillActivated() {
        guard let hit = lastHit else {
            logger.error("Pastilha clicada sem seleção guardada.")
            return
        }
        guard !isProcessing else {
            logger.info("Pastilha clicada durante outro processamento.")
            revealCurrentOperation()
            return
        }
        logger.info("Pastilha acionada com \(hit.text.count, privacy: .public) caracteres.")
        selectionWatcher?.suspendSelectionVigil()

        // Precisa ser lido antes de o painel aparecer e tomar o foco.
        let targetApp = NSWorkspace.shared.frontmostApplication
        let selection = CapturedSelection(
            text: hit.text,
            element: hit.element,
            range: selectedTextRange(of: hit.element),
            anchor: hit.anchor,
            clipboardChangeCount: nil
        )
        processor.prewarm()
        showActionPanel(for: selection, targetApp: targetApp, anchor: hit.anchor)
    }

    private func showActionPanel(
        for selection: CapturedSelection,
        targetApp: NSRunningApplication?,
        anchor: NSRect
    ) {
        logger.info("Montando painel de ações junto da seleção.")
        closeActionPanel()

        let controller = ActionPanel(
            onAction: { [weak self] action, instruction in
                guard let self else { return }
                self.closeActionPanel()
                guard !self.isProcessing else {
                    self.revealCurrentOperation()
                    return
                }
                self.isProcessing = true
                self.updateStatusIcon(processing: true)
                self.start(
                    action,
                    selection: selection,
                    targetApp: targetApp,
                    clipboardSnapshot: ClipboardSnapshot(),
                    customInstruction: instruction
                )
            },
            onDismiss: { [weak self] in
                self?.closeActionPanel()
            }
        )

        let panel = FloatingPanel(size: NSSize(width: 244, height: 340), acceptsKeyboard: true)
        panel.contentViewController = controller
        panel.setContentSize(controller.view.fittingSize)
        panel.position(near: anchor)
        actionPanelWindow = panel
        actionPanelDismissAfter = Date().addingTimeInterval(0.8)
        logger.info(
            "Geometria do painel: x=\(panel.frame.minX, privacy: .public), y=\(panel.frame.minY, privacy: .public), largura=\(panel.frame.width, privacy: .public), altura=\(panel.frame.height, privacy: .public); âncora x=\(anchor.minX, privacy: .public), y=\(anchor.minY, privacy: .public)."
        )

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        logger.info("Painel de ações ordenado na tela.")

        // O retorno do callback do Serviço pode reativar o editor mesmo depois
        // de makeKeyAndOrderFront. Recuperar o foco uma vez, já fora do callback,
        // torna o campo de instrução realmente digitável.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak panel] in
            guard let self, let panel, self.actionPanelWindow === panel else { return }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }

        // Ao terminar um Serviço, o macOS devolve o foco ao editor uma vez. Se
        // o fechamento já estiver armado, o painel se encerra no mesmo quadro
        // em que nasce. Depois desse pequeno período, perder o foco volta a
        // significar normalmente que a pessoa clicou fora.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self, weak panel] in
            guard let self, let panel, self.actionPanelWindow === panel else { return }
            panel.onResignKey = { [weak self, weak panel] in
                guard let self, self.actionPanelWindow === panel else { return }
                self.closeActionPanel()
            }
        }
    }

    private func closeActionPanel() {
        guard let panel = actionPanelWindow else { return }
        logger.info("Fechando painel de ações.")
        actionPanelWindow = nil
        actionPanelDismissAfter = .distantPast
        panel.onResignKey = nil
        panel.orderOut(nil)
    }

    private func checkAccessibilityPermission(prompt: Bool) -> Bool {
        let key = "AXTrustedCheckOptionPrompt"
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func sendKeyboardShortcut(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = flags
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

let app = NSApplication.shared
let appDelegate = HollyCorretorApp()
app.delegate = appDelegate
app.run()
