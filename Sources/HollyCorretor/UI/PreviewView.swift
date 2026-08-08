import AppKit

/// Painel de prévia em AppKit puro (sem SwiftUI). O texto gerado pela Apple
/// Intelligence é mostrado num editor; o usuário revisa e confirma. Evitar o
/// SwiftUI permite compilar apenas com o Command Line Tools, sem exigir o
/// Xcode completo (que traz o plugin de macros SwiftUIMacros).
final class PreviewViewController: NSViewController {
    private let initialText: String
    private let originalText: String?
    private let headerTitle: String
    private let onConfirm: (String) -> Void
    private let onCancel: () -> Void
    private let onCopy: ((String) -> Void)?

    private var textView: NSTextView!

    init(
        text: String,
        originalText: String?,
        title: String,
        onConfirm: @escaping (String) -> Void,
        onCancel: @escaping () -> Void,
        onCopy: ((String) -> Void)? = nil
    ) {
        self.initialText = text
        self.originalText = originalText
        self.headerTitle = title
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.onCopy = onCopy
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não implementado") }

    override func loadView() {
        let container = NSView()

        // MARK: Header
        let titleLabel = NSTextField(labelWithString: headerTitle)
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let closeButton = NSButton(
            image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Fechar")
                ?? NSImage(),
            target: self,
            action: #selector(cancelAction)
        )
        closeButton.isBordered = false
        closeButton.imageScaling = .scaleProportionallyUpOrDown
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let headerStack = NSStackView(views: [titleLabel, spacer, closeButton])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 8

        // MARK: Editor
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        guard let tv = scrollView.documentView as? NSTextView else {
            preconditionFailure("A visualização de texto não foi criada pelo AppKit")
        }
        tv.isEditable = true
        tv.isRichText = false
        tv.font = .systemFont(ofSize: 14)
        tv.string = initialText
        tv.textContainerInset = NSSize(width: 6, height: 8)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        self.textView = tv

        // MARK: Footer
        let note = NSTextField(labelWithString: "Revise o texto gerado pela Apple Intelligence antes de aplicar.")
        note.font = .preferredFont(forTextStyle: .caption1)
        note.textColor = .secondaryLabelColor
        note.lineBreakMode = .byWordWrapping
        note.maximumNumberOfLines = 2
        note.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let cancelButton = NSButton(title: "Cancelar", target: self, action: #selector(cancelAction))
        cancelButton.keyEquivalent = "\u{1b}" // Esc

        var footerViews: [NSView] = [note, cancelButton]

        if onCopy != nil {
            let copyButton = NSButton(title: "Copiar", target: self, action: #selector(copyAction))
            copyButton.toolTip = "Copia o resultado para a área de transferência sem substituir o texto original."
            footerViews.append(copyButton)
        }

        let confirmButton = NSButton(title: "Substituir", target: self, action: #selector(confirmAction))
        confirmButton.keyEquivalent = "\r" // Enter → botão padrão (destacado)
        footerViews.append(confirmButton)

        let footerStack = NSStackView(views: footerViews)
        footerStack.orientation = .horizontal
        footerStack.alignment = .centerY
        footerStack.spacing = 8

        // MARK: Layout
        for view in [headerStack, scrollView, footerStack] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }

        var constraints: [NSLayoutConstraint] = [
            headerStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            headerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            footerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            footerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            footerStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ]

        var topOfEditor = headerStack.bottomAnchor

        // MARK: Original (opcional)
        if let originalText {
            let originalCaption = NSTextField(labelWithString: "Original")
            originalCaption.font = .preferredFont(forTextStyle: .caption1)
            originalCaption.textColor = .secondaryLabelColor

            let originalValue = NSTextField(wrappingLabelWithString: originalText)
            originalValue.font = .systemFont(ofSize: 13)
            originalValue.textColor = .secondaryLabelColor
            originalValue.maximumNumberOfLines = 4

            let originalStack = NSStackView(views: [originalCaption, originalValue])
            originalStack.orientation = .vertical
            originalStack.alignment = .leading
            originalStack.spacing = 4
            originalStack.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(originalStack)

            constraints.append(contentsOf: [
                originalStack.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),
                originalStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
                originalStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16)
            ])
            topOfEditor = originalStack.bottomAnchor
        }

        constraints.append(contentsOf: [
            scrollView.topAnchor.constraint(equalTo: topOfEditor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: footerStack.topAnchor, constant: -12)
        ])

        NSLayoutConstraint.activate(constraints)

        container.setFrameSize(NSSize(width: 560, height: 320))
        self.view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
    }

    @objc private func confirmAction() { onConfirm(textView.string) }
    @objc private func cancelAction() { onCancel() }
    @objc private func copyAction() { onCopy?(textView.string) }
}
