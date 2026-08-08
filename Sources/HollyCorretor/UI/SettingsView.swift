import AppKit
import ServiceManagement
@preconcurrency import KeyboardShortcuts

/// Janela de Preferências em AppKit puro (sem SwiftUI), para permitir a
/// compilação apenas com o Command Line Tools (sem o Xcode completo). Usa o
/// `KeyboardShortcuts.RecorderCocoa` (variante AppKit) no lugar do
/// `KeyboardShortcuts.Recorder` (SwiftUI).
final class SettingsViewController: NSViewController, NSTextViewDelegate {
    private var launchToggle: NSButton!
    private var historyToggle: NSButton!
    private var promptTextView: NSTextView!

    private struct ShortcutRow {
        let title: String
        let name: KeyboardShortcuts.Name
    }

    private let rows: [ShortcutRow] = [
        .init(title: "Corrigir Ortografia:", name: .correct),
        .init(title: "Reescrever (Atalho 1):", name: .rewrite),
        .init(title: "Reescrever (Atalho 2):", name: .rewriteAlt),
        .init(title: "Formalizar (juridiquês):", name: .formalize),
        .init(title: "Simplificar para cliente:", name: .simplify),
        .init(title: "Resumir texto:", name: .summarize),
        .init(title: "Ação personalizada:", name: .custom),
        .init(title: "Salvar como Markdown:", name: .markdown)
    ]

    override func loadView() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: "Preferências — HollyCorretor")
        header.font = .preferredFont(forTextStyle: .headline)
        stack.addArrangedSubview(header)

        launchToggle = NSButton(
            checkboxWithTitle: "Iniciar com o Mac",
            target: self,
            action: #selector(toggleLaunchAtLogin)
        )
        launchToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
        stack.addArrangedSubview(launchToggle)

        historyToggle = NSButton(
            checkboxWithTitle: "Salvar os 10 resultados mais recentes no histórico local",
            target: self,
            action: #selector(toggleHistory)
        )
        historyToggle.state = AppPreferences.shouldSaveHistory ? .on : .off
        historyToggle.toolTip = "Desative para que novos textos não sejam guardados pelo aplicativo."
        stack.addArrangedSubview(historyToggle)

        for row in rows {
            let label = NSTextField(labelWithString: row.title)
            label.alignment = .right
            label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            label.widthAnchor.constraint(equalToConstant: 160).isActive = true

            let recorder = KeyboardShortcuts.RecorderCocoa(for: row.name)
            recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

            let rowStack = NSStackView(views: [label, recorder])
            rowStack.orientation = .horizontal
            rowStack.alignment = .centerY
            rowStack.spacing = 8
            stack.addArrangedSubview(rowStack)
        }

        let promptCaption = NSTextField(labelWithString: "Instrução personalizada:")
        promptCaption.font = .preferredFont(forTextStyle: .caption1)
        promptCaption.textColor = .secondaryLabelColor
        stack.addArrangedSubview(promptCaption)

        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 64).isActive = true
        guard let tv = scrollView.documentView as? NSTextView else {
            preconditionFailure("A visualização de texto não foi criada pelo AppKit")
        }
        tv.isRichText = false
        tv.font = .preferredFont(forTextStyle: .body)
        tv.string = AppPreferences.customPrompt ?? ""
        tv.delegate = self
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        promptTextView = tv
        stack.addArrangedSubview(scrollView)

        let promptHelp = NSTextField(wrappingLabelWithString:
            "Usada pela “Ação personalizada”. Ex.: “Traduza para o inglês”. Se ficar vazia, o texto será resumido.")
        promptHelp.font = .preferredFont(forTextStyle: .caption2)
        promptHelp.textColor = .secondaryLabelColor
        stack.addArrangedSubview(promptHelp)

        let privacyNote = NSTextField(wrappingLabelWithString:
            "O processamento pela Apple Intelligence ocorre no Mac. O histórico, quando ativado, também fica somente neste dispositivo.")
        privacyNote.font = .preferredFont(forTextStyle: .caption1)
        privacyNote.textColor = .secondaryLabelColor
        stack.addArrangedSubview(privacyNote)

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            container.widthAnchor.constraint(equalToConstant: 460)
        ])

        // Faz as caixas de texto de largura total acompanharem o container.
        scrollView.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 20).isActive = true
        scrollView.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -20).isActive = true

        self.view = container
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        launchToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
        historyToggle.state = AppPreferences.shouldSaveHistory ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("HollyCorretor: Erro ao alterar login item: %@", error.localizedDescription)
            let alert = NSAlert(error: error)
            alert.messageText = "Não foi possível alterar a inicialização automática"
            alert.runModal()
        }
        // Reflete o estado real do sistema (a operação pode falhar ou exigir
        // aprovação do usuário em Ajustes do Sistema).
        launchToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleHistory() {
        UserDefaults.standard.set(
            historyToggle.state == .on,
            forKey: AppPreferences.saveHistoryKey
        )
    }

    func textDidChange(_ notification: Notification) {
        UserDefaults.standard.set(
            promptTextView.string,
            forKey: AppPreferences.customPromptKey
        )
    }
}
