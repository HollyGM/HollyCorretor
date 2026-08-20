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
    let clipboardChangeCount: Int?
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
    private var isProcessing = false
    private var currentTask: Task<Void, Never>?
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

        let correctItem = NSMenuItem(title: "Corrigir texto selecionado", action: #selector(correctSelectedText), keyEquivalent: "")
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

    @objc(correctService:userData:error:) dynamic
    func correctService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        handleServiceRequest(pboard: pboard, action: .correct)
    }

    @objc(rewriteService:userData:error:) dynamic
    func rewriteService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        handleServiceRequest(pboard: pboard, action: .rewrite)
    }

    @objc(formalizeService:userData:error:) dynamic
    func formalizeService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        handleServiceRequest(pboard: pboard, action: .formalize)
    }

    @objc(simplifyService:userData:error:) dynamic
    func simplifyService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        handleServiceRequest(pboard: pboard, action: .simplify)
    }

    @objc(summarizeService:userData:error:) dynamic
    func summarizeService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        handleServiceRequest(pboard: pboard, action: .summarize)
    }

    @objc(customService:userData:error:) dynamic
    func customService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        handleServiceRequest(pboard: pboard, action: .custom)
    }

    @objc(markdownService:userData:error:) dynamic
    func markdownService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        handleServiceRequest(pboard: pboard, action: .markdown)
    }

    private func handleServiceRequest(pboard: NSPasteboard, action: CorrectionAction) {
        logger.info("Serviço recebido: \(action.title, privacy: .public)")
        guard !isProcessing else {
            NSSound.beep()
            return
        }
        guard checkAccessibilityPermission(prompt: true) else {
            showAlert(title: "Permissão necessária", message: "Ative Acessibilidade para o HollyCorretor.")
            return
        }
        guard let selectedText = extractPlainText(from: pboard) else {
            showAlert(title: "Nenhum texto selecionado", message: "Selecione o texto e tente novamente.")
            return
        }

        let targetApp = NSWorkspace.shared.frontmostApplication
        let snapshot = ClipboardSnapshot()
        let selection = CapturedSelection(
            text: selectedText,
            element: nil,
            clipboardChangeCount: nil
        )
        isProcessing = true
        updateStatusIcon(processing: true)

        start(action, selection: selection, targetApp: targetApp, clipboardSnapshot: snapshot)
    }

    /// Encaminha para o salvamento em Markdown (que não usa o modelo) ou para o
    /// processamento pela Apple Intelligence.
    private func start(
        _ action: CorrectionAction,
        selection: CapturedSelection,
        targetApp: NSRunningApplication?,
        clipboardSnapshot: ClipboardSnapshot
    ) {
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
                clipboardSnapshot: clipboardSnapshot
            )
        }
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

    @objc private func requestAccessibilityPermission() { _ = checkAccessibilityPermission(prompt: true) }

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
        guard !isProcessing else {
            NSSound.beep()
            return
        }
        guard checkAccessibilityPermission(prompt: true) else {
            showAlert(title: "Permissão necessária", message: "Ative Acessibilidade.")
            return
        }

        let targetApp = NSWorkspace.shared.frontmostApplication
        let snapshot = ClipboardSnapshot()

        // Manda o sistema carregar o modelo agora, em paralelo com a captura da
        // seleção, em vez de só quando o texto já estiver em mãos.
        if action != .markdown { processor.prewarm() }

        if let selection = selectedTextViaAccessibility() {
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

            if clipboardChanged, let selectedText = extractPlainText(from: pasteboard) {
                let selection = CapturedSelection(
                    text: selectedText,
                    element: nil,
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
        return CapturedSelection(text: text, element: element, clipboardChangeCount: nil)
    }

    private func focusedAccessibilityElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let focused = focusedElement,
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return (focused as! AXUIElement)
    }

    private func selectedText(of element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    /// Escreve o resultado direto no campo de onde o texto saiu. Só age se a
    /// seleção ainda for exatamente a que foi capturada — caso a pessoa tenha
    /// clicado em outro lugar, não há o que substituir com segurança.
    private func replaceSelection(
        of element: AXUIElement,
        expecting original: String,
        with text: String
    ) -> Bool {
        guard selectedText(of: element) == original else { return false }

        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }

        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        ) == .success
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
                self.showSuccessFeedback(playPop: true)
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            } catch {
                self.showAlert(
                    title: "Erro ao salvar",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func makePreviewPanel() -> NSPanel {
        let panel = NSPanel(
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

    /// Abre a prévia imediatamente e vai preenchendo-a conforme o modelo
    /// escreve. Antes disso o app ficava até 25 s sem sinal nenhum, e não havia
    /// como desistir no meio.
    private func processText(
        _ selection: CapturedSelection,
        action: CorrectionAction,
        targetApp: NSRunningApplication?,
        clipboardSnapshot: ClipboardSnapshot
    ) {
        let panel = makePreviewPanel()

        let previewController = PreviewViewController(
            originalText: selection.text,
            title: action.title,
            onConfirm: { [weak self, weak panel] finalText in
                panel?.close()
                if AppPreferences.shouldSaveHistory {
                    HistoryStore.shared.add(
                        actionTitle: action.title,
                        processedText: finalText
                    )
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
                self?.currentTask?.cancel()
                self?.currentTask = nil
                panel?.close()
                clipboardSnapshot.restoreIfUnchanged(
                    since: selection.clipboardChangeCount
                )
                self?.isProcessing = false
                self?.updateStatusIcon(processing: false)
            },
            onCopy: { [weak self, weak panel] finalText in
                panel?.close()
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(finalText, forType: .string)
                self?.isProcessing = false
                self?.showSuccessFeedback(playPop: true)
            }
        )
        panel.contentViewController = previewController
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)

        currentTask = Task { [weak self, weak panel, weak previewController] in
            guard let self else { return }
            do {
                var finalText = ""
                for try await update in self.processor.stream(selection.text, action: action) {
                    switch update {
                    case .partial(let text):
                        previewController?.updateStreamingText(text)
                    case .finished(let text):
                        finalText = text
                    }
                }

                // Ao cancelar, o laço termina sem lançar erro: a sequência é
                // encerrada em vez de falhar. Sem esta checagem o painel já
                // fechado receberia um resultado parcial como se fosse final.
                guard !Task.isCancelled else { return }

                self.currentTask = nil
                self.updateStatusIcon(processing: false)
                previewController?.finishStreaming(
                    with: finalText.isEmpty ? selection.text : finalText
                )
            } catch is CancellationError {
                // O botão Cancelar já fechou o painel e restaurou o estado.
            } catch {
                guard !Task.isCancelled else { return }
                self.currentTask = nil
                panel?.close()
                self.updateStatusIcon(processing: false)
                self.isProcessing = false
                clipboardSnapshot.restoreIfUnchanged(
                    since: selection.clipboardChangeCount
                )
                self.showAlert(
                    title: "Falha ao processar",
                    message: error.localizedDescription
                )
            }
        }
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
        if let element = selection.element,
           replaceSelection(of: element, expecting: selection.text, with: finalText) {
            logger.info("Resultado aplicado pela Acessibilidade.")
            showSuccessFeedback(playPop: true)
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
        showSuccessFeedback(playPop: true)

        try? await Task.sleep(nanoseconds: 2_000_000_000)
        clipboardSnapshot.restoreIfUnchanged(since: injectionChangeCount)
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
