import AppKit
import ServiceManagement
@preconcurrency import KeyboardShortcuts

/// Janela de Preferências em AppKit puro (sem SwiftUI), para permitir a
/// compilação apenas com o Command Line Tools (sem o Xcode completo). Usa o
/// `KeyboardShortcuts.RecorderCocoa` (variante AppKit) no lugar do
/// `KeyboardShortcuts.Recorder` (SwiftUI).
///
/// As opções ficam em grupos, como nos Ajustes do Sistema: acionamento,
/// atalhos, ação personalizada e privacidade. Cada grupo é uma caixa com
/// título, e as explicações ficam logo abaixo da opção a que se referem.
final class SettingsViewController: NSViewController, NSTextViewDelegate {
    private var launchToggle: NSButton!
    private var historyToggle: NSButton!
    private var cloudToggle: NSButton!
    private var pillToggle: NSButton!
    private var rightClickToggle: NSButton!
    private var promptTextView: NSTextView!

    private struct ShortcutRow {
        let title: String
        let name: KeyboardShortcuts.Name
    }

    private let rows: [ShortcutRow] = [
        .init(title: "Corrigir ortografia", name: .correct),
        .init(title: "Reescrever", name: .rewrite),
        .init(title: "Reescrever (alternativo)", name: .rewriteAlt),
        .init(title: "Formalizar (juridiquês)", name: .formalize),
        .init(title: "Simplificar para o cliente", name: .simplify),
        .init(title: "Resumir", name: .summarize),
        .init(title: "Ação personalizada", name: .custom),
        .init(title: "Salvar como Markdown", name: .markdown)
    ]

    private static let contentWidth: CGFloat = 480
    private static let margin: CGFloat = 20

    override func loadView() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.edgeInsets = NSEdgeInsets(
            top: Self.margin, left: Self.margin, bottom: Self.margin, right: Self.margin
        )
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(makeGeneralSection())
        stack.addArrangedSubview(makeActivationSection())
        stack.addArrangedSubview(makeShortcutsSection())
        stack.addArrangedSubview(makeCustomActionSection())
        stack.addArrangedSubview(makePrivacySection())

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            container.widthAnchor.constraint(equalToConstant: Self.contentWidth)
        ])
        for section in stack.arrangedSubviews {
            section.widthAnchor.constraint(
                equalToConstant: Self.contentWidth - 2 * Self.margin
            ).isActive = true
        }

        self.view = container
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        launchToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
        historyToggle.state = AppPreferences.shouldSaveHistory ? .on : .off
        cloudToggle.state = AppPreferences.usesPrivateCloudCompute ? .on : .off
        pillToggle.state = AppPreferences.showsSelectionPill ? .on : .off
        rightClickToggle.state = AppPreferences.showsPillOnRightClick ? .on : .off
    }

    // MARK: - Seções

    private func makeGeneralSection() -> NSView {
        launchToggle = NSButton(
            checkboxWithTitle: "Iniciar o HollyCorretor com o Mac",
            target: self,
            action: #selector(toggleLaunchAtLogin)
        )
        launchToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
        return makeSection(title: "Geral", content: [launchToggle])
    }

    private func makeActivationSection() -> NSView {
        rightClickToggle = NSButton(
            checkboxWithTitle: "Mostrar o HollyCorretor no clique direito",
            target: self,
            action: #selector(toggleRightClick)
        )
        rightClickToggle.state = AppPreferences.showsPillOnRightClick ? .on : .off
        let rightClickHelp = makeHelp(
            "Ao clicar com o botão direito sobre um texto selecionado, um botão do HollyCorretor aparece ao lado do menu de contexto — em qualquer aplicativo, inclusive nos que não oferecem o menu Serviços, como o Claude, o WhatsApp e os demais feitos em Electron. Uma palavra só já basta."
        )

        pillToggle = NSButton(
            checkboxWithTitle: "Mostrar o botão assim que um texto é selecionado",
            target: self,
            action: #selector(togglePill)
        )
        pillToggle.state = AppPreferences.showsSelectionPill ? .on : .off
        let pillHelp = makeHelp(
            "Ao soltar o mouse depois de selecionar um trecho, o botão aparece ao lado da seleção, sem precisar clicar com o botão direito."
        )

        let footer = makeHelp(
            "O menu Serviços do macOS continua disponível: nos aplicativos nativos, Serviços › HollyCorretor… abre o mesmo painel. As duas opções acima exigem a permissão de Acessibilidade e escutam apenas os botões do mouse — nunca o teclado."
        )

        return makeSection(
            title: "Acionamento",
            content: [rightClickToggle, rightClickHelp, pillToggle, pillHelp, footer]
        )
    }

    private func makeShortcutsSection() -> NSView {
        let grid = NSGridView()
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 0).xPlacement = .trailing

        for row in rows {
            let label = NSTextField(labelWithString: row.title + ":")
            label.alignment = .right
            label.font = .systemFont(ofSize: 13)
            let recorder = KeyboardShortcuts.RecorderCocoa(for: row.name)
            recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
            grid.addRow(with: [label, recorder])
        }
        grid.column(at: 0).width = 180

        let help = makeHelp(
            "Clique num campo e pressione a combinação desejada. Os atalhos valem em qualquer aplicativo, sobre o texto selecionado."
        )
        return makeSection(title: "Atalhos de teclado", content: [grid, help])
    }

    private func makeCustomActionSection() -> NSView {
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

        let help = makeHelp(
            "Instrução aplicada pela “Ação personalizada” do atalho e do menu da barra. Ex.: “Traduza para o inglês”. Vazia, o texto é resumido. No painel do clique direito a instrução é digitada na hora."
        )
        let section = makeSection(title: "Ação personalizada", content: [scrollView, help])
        scrollView.widthAnchor.constraint(
            equalToConstant: Self.contentWidth - 2 * Self.margin - 2 * Self.boxPadding
        ).isActive = true
        return section
    }

    private func makePrivacySection() -> NSView {
        historyToggle = NSButton(
            checkboxWithTitle: "Guardar os 10 resultados mais recentes no histórico local",
            target: self,
            action: #selector(toggleHistory)
        )
        historyToggle.state = AppPreferences.shouldSaveHistory ? .on : .off
        let historyHelp = makeHelp(
            "Gravado em arquivo protegido dentro da sua pasta de usuário, neste Mac. Nasce desligado; apague quando quiser em Ver histórico…"
        )

        cloudToggle = NSButton(
            checkboxWithTitle: "Usar o Private Cloud Compute em textos longos",
            target: self,
            action: #selector(toggleCloud)
        )
        cloudToggle.state = AppPreferences.usesPrivateCloudCompute ? .on : .off
        let cloudHelp = makeHelp(
            "Só é acionado quando o texto não cabe no modelo local. Com a opção ligada, esses textos são enviados aos servidores da Apple em vez de divididos em blocos; o conteúdo sai deste Mac. Mantenha desligada para material sob sigilo."
        )

        let note = makeHelp(
            "O processamento pela Apple Intelligence ocorre neste Mac. O HollyCorretor não contém chaves de API nem faz chamadas de rede próprias."
        )
        return makeSection(
            title: "Privacidade",
            content: [historyToggle, historyHelp, cloudToggle, cloudHelp, note]
        )
    }

    // MARK: - Construção

    private static let boxPadding: CGFloat = 12

    /// Um grupo com título em negrito e uma caixa arredondada com as opções,
    /// no espírito dos Ajustes do Sistema.
    private func makeSection(title: String, content: [NSView]) -> NSView {
        let header = NSTextField(labelWithString: title)
        header.font = .systemFont(ofSize: 13, weight: .semibold)

        let inner = NSStackView(views: content)
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 8
        inner.edgeInsets = NSEdgeInsets(
            top: Self.boxPadding, left: Self.boxPadding,
            bottom: Self.boxPadding, right: Self.boxPadding
        )
        inner.translatesAutoresizingMaskIntoConstraints = false

        let box = NSBox()
        box.boxType = .custom
        box.titlePosition = .noTitle
        box.cornerRadius = 10
        box.borderWidth = 1
        box.borderColor = .separatorColor
        box.fillColor = .quaternarySystemFill
        box.contentViewMargins = .zero
        box.contentView = inner
        box.translatesAutoresizingMaskIntoConstraints = false

        let section = NSStackView(views: [header, box])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 6
        section.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true

        // Os textos de ajuda ocupam a largura da caixa para quebrar linha.
        for view in content where view is NSTextField {
            view.widthAnchor.constraint(
                equalTo: inner.widthAnchor, constant: -2 * Self.boxPadding
            ).isActive = true
        }
        return section
    }

    private func makeHelp(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    // MARK: - Ações

    @objc private func togglePill() {
        UserDefaults.standard.set(
            pillToggle.state == .on,
            forKey: AppPreferences.selectionPillKey
        )
        // O delegate do aplicativo religa ou desliga o vigia ao notar a mudança.
        NotificationCenter.default.post(name: .hollySelectionPillPreferenceChanged, object: nil)
    }

    @objc private func toggleRightClick() {
        UserDefaults.standard.set(
            rightClickToggle.state == .on,
            forKey: AppPreferences.rightClickPillKey
        )
        NotificationCenter.default.post(name: .hollySelectionPillPreferenceChanged, object: nil)
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

    @objc private func toggleCloud() {
        UserDefaults.standard.set(
            cloudToggle.state == .on,
            forKey: AppPreferences.privateCloudComputeKey
        )
    }

    func textDidChange(_ notification: Notification) {
        UserDefaults.standard.set(
            promptTextView.string,
            forKey: AppPreferences.customPromptKey
        )
    }
}
