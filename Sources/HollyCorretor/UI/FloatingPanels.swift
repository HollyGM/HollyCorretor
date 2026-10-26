import AppKit
import HollyCore

/// Janela flutuante que não rouba o foco do aplicativo onde a pessoa está
/// escrevendo. Sem isto, só de aparecer o botão já desfaria a seleção.
class FloatingPanel: NSPanel {
    /// Chamado quando a janela deixa de ser a ativa — clique em outro lugar,
    /// troca de aplicativo, ⌘Tab. Um painel que só some depois de escolher uma
    /// ação obriga a pessoa a usar o que ela já decidiu não usar.
    var onResignKey: (() -> Void)?

    init(size: NSSize, acceptsKeyboard: Bool) {
        self.acceptsKeyboard = acceptsKeyboard
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    private let acceptsKeyboard: Bool
    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    /// Esc fecha, venha de onde vier na cadeia de resposta.
    override func cancelOperation(_ sender: Any?) {
        onResignKey?()
    }

    /// Posiciona a janela junto de um retângulo da tela, virando para cima ou
    /// para baixo conforme o espaço disponível.
    func position(near anchor: NSRect, preferAbove: Bool = true, gap: CGFloat = 8) {
        let size = frame.size
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let visible = screen.visibleFrame

        var x = anchor.minX
        var y = preferAbove ? anchor.maxY + gap : anchor.minY - size.height - gap

        if preferAbove, y + size.height > visible.maxY {
            y = anchor.minY - size.height - gap
        }
        if !preferAbove, y < visible.minY {
            y = anchor.maxY + gap
        }

        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        y = min(max(y, visible.minY + 8), visible.maxY - size.height - 8)

        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - Botão que aparece ao lado da seleção

/// O acionador compacto que surge quando há texto selecionado: uma pastilha
/// com o símbolo e o nome do HollyCorretor, para a pessoa saber de onde ela
/// vem — no clique direito ela aparece ao lado de um menu que é de outro
/// aplicativo.
@MainActor
final class SelectionPill {
    private var panel: FloatingPanel?
    private let onClick: () -> Void

    /// Tamanho fixo da pastilha. É também o que o posicionamento usa antes da
    /// janela existir.
    private static let size = NSSize(width: 128, height: 30)

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Área ocupada na tela, para o vigia saber que um clique ali é nosso.
    var frame: NSRect? { panel?.isVisible == true ? panel?.frame : nil }

    /// Ao lado da seleção que acabou de ser arrastada.
    func show(at anchor: NSRect) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.position(near: anchor)
        panel.orderFrontRegardless()
    }

    /// Junto do ponteiro, acima e à esquerda do ponto clicado: o menu de
    /// contexto que o aplicativo abriu se estende para baixo e para a direita
    /// a partir dali, e a pastilha não pode cobri-lo nem ser coberta por ele.
    func show(nearPointer pointer: NSPoint) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = panel.frame.size
        let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let gap: CGFloat = 8

        var x = pointer.x - size.width - gap
        var y = pointer.y + gap
        if x < visible.minX + 8 {
            // Sem espaço à esquerda, fica acima do ponteiro, começando nele; o
            // menu só começa abaixo do ponteiro, então não há sobreposição.
            x = pointer.x
        }
        if y + size.height > visible.maxY - 8 {
            // Perto do topo o menu abre para baixo como sempre; a pastilha vai
            // para baixo do ponteiro, do lado de fora da coluna do menu.
            y = pointer.y - size.height - gap
            x = min(x, pointer.x - size.width - gap)
        }
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        y = min(max(y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
    }

    func hide() {
        // Só quando está à mostra: cada rolagem e cada clique pedem para
        // esconder, e ordenar para fora uma janela já escondida é trabalho
        // (e registro no log) a sessenta vezes por segundo.
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
    }

    private func makePanel() -> FloatingPanel {
        let size = Self.size
        let panel = FloatingPanel(size: size, acceptsKeyboard: false)
        // Um nível acima dos menus de contexto: a pastilha do clique direito
        // convive com o menu que o aplicativo abriu e precisa ficar visível
        // mesmo que o sistema o posicione por cima dela.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = size.height / 2
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor.separatorColor.cgColor
        background.autoresizingMask = [.width, .height]

        let button = PillButton(title: "HollyCorretor", symbol: "wand.and.stars")
        button.target = self
        button.action = #selector(clicked)
        button.frame = background.bounds
        button.autoresizingMask = [.width, .height]
        background.addSubview(button)

        panel.contentView = background
        return panel
    }

    @objc private func clicked() {
        hide()
        onClick()
    }
}

/// Botão em forma de pastilha: símbolo na cor da marca e o nome do app.
private final class PillButton: NSButton {
    private var hovering = false
    private var tracking: NSTrackingArea?

    /// Laranja da identidade Holly, um pouco mais fechado no modo claro para
    /// manter o contraste sobre o fundo translúcido.
    static let brandTint = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 1.00, green: 0.64, blue: 0.40, alpha: 1)
            : NSColor(srgbRed: 0.85, green: 0.44, blue: 0.16, alpha: 1)
    }

    init(title: String, symbol: String) {
        super.init(frame: .zero)
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        self.title = title
        self.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        self.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        self.imageHugsTitle = true
        self.isBordered = false
        self.font = .systemFont(ofSize: 12, weight: .semibold)
        self.contentTintColor = Self.brandTint
        self.wantsLayer = true
        self.toolTip = "Abrir o HollyCorretor para o texto selecionado"
        self.setAccessibilityLabel("HollyCorretor")

        // O título fica na cor do texto; só o símbolo leva a cor da marca.
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        self.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { return nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovering {
            let radius = min(bounds.width, bounds.height) / 2
            let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
            Self.brandTint.withAlphaComponent(0.14).setFill()
            path.fill()
        }
        super.draw(dirtyRect)
    }
}

// MARK: - Painel de ações

/// O painel com as ações, no formato da ferramenta de escrita do sistema, mas
/// com as ações e a identidade do HollyCorretor.
@MainActor
final class ActionPanel: NSViewController {
    private let onAction: (CorrectionAction, String?) -> Void
    private let onDismiss: () -> Void
    private var instructionField: NSTextField!

    init(
        onAction: @escaping (CorrectionAction, String?) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.onAction = onAction
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não implementado") }

    override func loadView() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // A ferramenta da Apple abre direto no campo e deixa a identidade fora
        // do caminho. O nome HollyCorretor já aparece no menu que abriu o painel.
        instructionField = NSTextField()
        instructionField.placeholderString = "Descreva sua alteração"
        instructionField.font = .systemFont(ofSize: 13)
        instructionField.bezelStyle = .roundedBezel
        instructionField.target = self
        instructionField.action = #selector(runInstruction)
        instructionField.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(instructionField)

        // Revisar e Reescrever, lado a lado
        let primary = NSStackView(views: CorrectionAction.panelPrimary.map(makeTile))
        primary.orientation = .horizontal
        primary.distribution = .fillEqually
        primary.spacing = 6
        primary.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(primary)

        stack.addArrangedSubview(makeSeparator())
        for action in CorrectionAction.panelTone {
            stack.addArrangedSubview(makeRow(action))
        }
        stack.addArrangedSubview(makeSeparator())
        for action in CorrectionAction.panelStructure {
            stack.addArrangedSubview(makeRow(action))
        }
        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(makeRow(.custom, label: "Redigir…"))

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        background.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            background.widthAnchor.constraint(equalToConstant: 244)
        ])
        instructionField.widthAnchor
            .constraint(equalTo: stack.widthAnchor, constant: -16).isActive = true
        primary.widthAnchor
            .constraint(equalTo: stack.widthAnchor, constant: -16).isActive = true

        self.view = background
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(instructionField)
    }

    // MARK: Construção dos controles

    private func makeSeparator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    private func makeTile(_ action: CorrectionAction) -> NSView {
        let button = ActionButton(action: action, style: .tile)
        button.target = self
        button.action = #selector(runAction(_:))
        return button
    }

    private func makeRow(_ action: CorrectionAction, label: String? = nil) -> NSView {
        let button = ActionButton(action: action, style: .row, overrideTitle: label)
        button.target = self
        button.action = #selector(runAction(_:))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        button.widthAnchor.constraint(equalToConstant: 228).isActive = true
        return button
    }

    // MARK: Ações

    @objc private func runAction(_ sender: ActionButton) {
        if sender.correctionAction == .custom {
            runInstruction()
            return
        }
        onAction(sender.correctionAction, nil)
    }

    @objc private func runInstruction() {
        let text = instructionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            instructionField.placeholderString = "Digite primeiro o que deseja alterar"
            view.window?.makeFirstResponder(instructionField)
            return
        }
        onAction(.custom, text)
    }

    override func cancelOperation(_ sender: Any?) {
        onDismiss()
    }
}

/// Botão de uma ação, nos dois formatos usados no painel.
final class ActionButton: NSButton {
    enum Style {
        case tile
        case row
    }

    let correctionAction: CorrectionAction
    private let style: Style
    private var hovering = false
    private var tracking: NSTrackingArea?

    init(action: CorrectionAction, style: Style, overrideTitle: String? = nil) {
        self.correctionAction = action
        self.style = style
        super.init(frame: .zero)

        title = overrideTitle ?? action.title
        image = NSImage(
            systemSymbolName: action.symbolName,
            accessibilityDescription: nil
        )
        isBordered = false
        wantsLayer = true
        contentTintColor = .labelColor

        switch style {
        case .tile:
            imagePosition = .imageAbove
            font = .systemFont(ofSize: 12, weight: .medium)
            translatesAutoresizingMaskIntoConstraints = false
            heightAnchor.constraint(equalToConstant: 54).isActive = true
        case .row:
            imagePosition = .imageLeading
            alignment = .left
            font = .systemFont(ofSize: 13)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { return nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = style == .tile ? 8 : 6
        let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)

        switch style {
        case .tile:
            (hovering ? NSColor.controlAccentColor.withAlphaComponent(0.18)
                      : NSColor.controlColor.withAlphaComponent(0.6)).setFill()
            path.fill()
        case .row:
            if hovering {
                NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
                path.fill()
            }
        }

        super.draw(dirtyRect)
    }
}
