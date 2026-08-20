import AppKit
import HollyCore

/// Janela flutuante que não rouba o foco do aplicativo onde a pessoa está
/// escrevendo. Sem isto, só de aparecer o botão já desfaria a seleção.
class FloatingPanel: NSPanel {
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

/// A pastilha "HollyCorretor" que surge quando há texto selecionado.
@MainActor
final class SelectionPill {
    private var panel: FloatingPanel?
    private let onClick: () -> Void

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(at anchor: NSRect) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.position(near: anchor)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(size: NSSize(width: 132, height: 30), acceptsKeyboard: false)

        let button = PillButton(title: "HollyCorretor", symbol: "wand.and.stars")
        button.target = self
        button.action = #selector(clicked)
        button.frame = NSRect(x: 0, y: 0, width: 132, height: 30)
        button.autoresizingMask = [.width, .height]

        let container = NSView(frame: button.frame)
        container.addSubview(button)
        panel.contentView = container
        return panel
    }

    @objc private func clicked() {
        hide()
        onClick()
    }
}

/// Botão arredondado com ícone e rótulo, desenhado à mão para poder ter o
/// visual de pastilha flutuante.
private final class PillButton: NSButton {
    private var hovering = false
    private var tracking: NSTrackingArea?

    init(title: String, symbol: String) {
        super.init(frame: .zero)
        self.title = title
        self.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        self.imagePosition = .imageLeading
        self.isBordered = false
        self.font = .systemFont(ofSize: 12, weight: .medium)
        self.contentTintColor = .labelColor
        self.wantsLayer = true
        self.toolTip = "Abrir o HollyCorretor para o texto selecionado"
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
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        (hovering ? NSColor.controlAccentColor.withAlphaComponent(0.16) : NSColor.controlBackgroundColor)
            .setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
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
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Campo de instrução livre
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
            background.widthAnchor.constraint(equalToConstant: 268)
        ])
        instructionField.widthAnchor
            .constraint(equalTo: stack.widthAnchor, constant: -20).isActive = true
        primary.widthAnchor
            .constraint(equalTo: stack.widthAnchor, constant: -20).isActive = true

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
        button.widthAnchor.constraint(equalToConstant: 248).isActive = true
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
            NSSound.beep()
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
