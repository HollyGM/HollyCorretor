import AppKit
import HollyCore

/// Prévia em AppKit puro (sem SwiftUI), para compilar só com as Command Line
/// Tools. Mostra o original e o resultado um sobre o outro, com as diferenças
/// destacadas, e só devolve o texto ao documento quando a pessoa clica em
/// Substituir. O resultado aparece enquanto é produzido e pode ser editado
/// antes de ser aplicado; os destaques acompanham a edição.
final class PreviewViewController: NSViewController, NSTextViewDelegate {
    static let defaultSize = NSSize(width: 540, height: 440)
    static let minimumSize = NSSize(width: 420, height: 320)

    private let originalText: String
    private let headerTitle: String
    private let resultCaption: String
    private let highlightsChanges: Bool
    private let onConfirm: (String) -> Void
    private let onCancel: () -> Void
    private let onCopy: (String) -> Void

    private var originalTextView: NSTextView!
    private var resultTextView: NSTextView!
    private var noteLabel: NSTextField!
    private var spinner: NSProgressIndicator!
    private var copyButton: NSButton!
    private var confirmButton: NSButton!

    private var isGenerating = true
    private var pendingHighlight: Task<Void, Never>?

    /// Fundo do que saiu do original e do que entrou no resultado. Com alfa,
    /// para funcionar sobre o fundo claro e o escuro.
    private static let removedColor = NSColor.systemRed.withAlphaComponent(0.22)
    private static let insertedColor = NSColor.systemGreen.withAlphaComponent(0.28)

    init(
        originalText: String,
        title: String,
        resultCaption: String,
        highlightsChanges: Bool,
        onConfirm: @escaping (String) -> Void,
        onCancel: @escaping () -> Void,
        onCopy: @escaping (String) -> Void
    ) {
        self.originalText = originalText
        self.headerTitle = title
        self.resultCaption = resultCaption
        self.highlightsChanges = highlightsChanges
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.onCopy = onCopy
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não implementado") }

    override func loadView() {
        let container = NSView()

        // MARK: Cabeçalho
        let titleLabel = NSTextField(labelWithString: headerTitle)
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.startAnimation(nil)
        spinner.setContentHuggingPriority(.defaultHigh, for: .horizontal)

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

        let headerStack = NSStackView(views: [titleLabel, spinner, spacer, closeButton])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 8

        // MARK: Original
        let originalCaption = makeCaption("Original")
        let (originalScroll, originalView) = makeTextArea()
        originalView.font = .systemFont(ofSize: 13)
        originalView.textColor = .secondaryLabelColor
        originalView.string = originalText
        originalTextView = originalView

        // MARK: Resultado
        let resultCaptionLabel = makeCaption(resultCaption)
        let (resultScroll, resultView) = makeTextArea()
        resultView.font = .systemFont(ofSize: 14)
        resultView.textColor = .labelColor
        resultView.allowsUndo = true
        resultView.delegate = self
        resultTextView = resultView

        // MARK: Rodapé
        noteLabel = NSTextField(labelWithString: "Gerando com a Apple Intelligence…")
        noteLabel.font = .preferredFont(forTextStyle: .caption1)
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.lineBreakMode = .byTruncatingTail
        noteLabel.maximumNumberOfLines = 1
        noteLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        noteLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let cancelButton = NSButton(title: "Cancelar", target: self, action: #selector(cancelAction))
        cancelButton.keyEquivalent = "\u{1b}" // Esc

        copyButton = NSButton(title: "Copiar", target: self, action: #selector(copyAction))
        copyButton.toolTip = "Copia o resultado para a área de transferência sem substituir o texto original."
        copyButton.isEnabled = false

        confirmButton = NSButton(title: "Substituir", target: self, action: #selector(confirmAction))
        // ⌘↩, porque o Enter sozinho pertence ao editor do resultado, onde a
        // pessoa pode estar ajustando uma frase.
        confirmButton.keyEquivalent = "\r"
        confirmButton.keyEquivalentModifierMask = [.command]
        confirmButton.toolTip = "Substitui o texto selecionado no documento pelo resultado (⌘↩)."
        confirmButton.isEnabled = false

        let footerStack = NSStackView(views: [noteLabel, cancelButton, copyButton, confirmButton])
        footerStack.orientation = .horizontal
        footerStack.alignment = .centerY
        footerStack.spacing = 8

        // MARK: Layout
        for view in [headerStack, originalCaption, originalScroll, resultCaptionLabel, resultScroll, footerStack] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }

        // O original ocupa pouco mais da metade da altura do resultado: é
        // referência, e o resultado é o que se revisa. Prioridade abaixo da
        // obrigatória para a janela poder ser redimensionada à vontade.
        let proportion = originalScroll.heightAnchor.constraint(
            equalTo: resultScroll.heightAnchor, multiplier: 0.55
        )
        proportion.priority = .defaultHigh

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            headerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            originalCaption.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),
            originalCaption.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),

            originalScroll.topAnchor.constraint(equalTo: originalCaption.bottomAnchor, constant: 4),
            originalScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            originalScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            originalScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            proportion,

            resultCaptionLabel.topAnchor.constraint(equalTo: originalScroll.bottomAnchor, constant: 12),
            resultCaptionLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),

            resultScroll.topAnchor.constraint(equalTo: resultCaptionLabel.bottomAnchor, constant: 4),
            resultScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            resultScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            resultScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
            resultScroll.bottomAnchor.constraint(equalTo: footerStack.topAnchor, constant: -12),

            footerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            footerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            footerStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])

        container.setFrameSize(Self.defaultSize)
        self.view = container
    }

    private func makeCaption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabelColor
        return label
    }

    /// Área de texto rolável. Nasce só para leitura: o resultado é liberado
    /// para edição quando a geração termina, porque editar enquanto o texto
    /// ainda está chegando faria a próxima atualização apagar a edição.
    private func makeTextArea() -> (NSScrollView, NSTextView) {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        guard let textView = scrollView.documentView as? NSTextView else {
            preconditionFailure("A visualização de texto não foi criada pelo AppKit")
        }
        textView.isRichText = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        // A correção automática do sistema mexeria no texto que a pessoa está
        // revisando; o verificador ortográfico continua só sublinhando.
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        return (scrollView, textView)
    }

    // MARK: - Geração

    /// Substitui o conteúdo pelo texto acumulado até agora e acompanha o fim
    /// do texto, para a pessoa ver o que está sendo escrito.
    func updateStreamingText(_ text: String) {
        guard isGenerating, isViewLoaded, resultTextView.string != text else { return }
        resultTextView.string = text
        resultTextView.scrollToEndOfDocument(nil)
    }

    /// O resultado definitivo chegou: libera a edição, destaca as diferenças e
    /// deixa o cursor no começo, para a revisão começar de cima.
    func finishStreaming(with text: String) {
        guard isViewLoaded else { return }
        isGenerating = false
        resultTextView.string = text
        resultTextView.isEditable = true
        spinner.stopAnimation(nil)
        copyButton.isEnabled = true
        refreshHighlights()
        updateNote()
        view.window?.makeFirstResponder(resultTextView)
        resultTextView.setSelectedRange(NSRange(location: 0, length: 0))
        resultTextView.scrollToBeginningOfDocument(nil)
        originalTextView.scrollToBeginningOfDocument(nil)
    }

    // MARK: - Destaques

    private func refreshHighlights() {
        let result = resultTextView.string
        let diff = highlightsChanges ? TextDiff.compare(originalText, result) : .none
        apply(diff.removed, to: originalTextView, in: originalText,
              color: Self.removedColor, strikethrough: true)
        apply(diff.inserted, to: resultTextView, in: result,
              color: Self.insertedColor, strikethrough: false)
    }

    private func apply(
        _ ranges: [Range<String.Index>],
        to textView: NSTextView,
        in text: String,
        color: NSColor,
        strikethrough: Bool
    ) {
        guard let storage = textView.textStorage, storage.string == text else { return }
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.removeAttribute(.backgroundColor, range: whole)
        storage.removeAttribute(.strikethroughStyle, range: whole)
        for range in ranges {
            let nsRange = NSRange(range, in: text)
            storage.addAttribute(.backgroundColor, value: color, range: nsRange)
            if strikethrough {
                storage.addAttribute(
                    .strikethroughStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    range: nsRange
                )
            }
        }
        storage.endEditing()

        // O que a pessoa digitar a seguir não herda o destaque do trecho em
        // que o cursor estava.
        textView.typingAttributes = [
            .font: textView.font ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: textView.textColor ?? NSColor.labelColor
        ]
    }

    private func updateNote() {
        let result = resultTextView.string
        guard result != originalText else {
            noteLabel.stringValue = "Nenhuma alteração: o texto já estava assim."
            confirmButton.isEnabled = false
            return
        }
        confirmButton.isEnabled = true
        guard highlightsChanges else {
            noteLabel.stringValue = "Revise o resultado antes de substituir."
            return
        }
        let count = TextChangeCounter.count(from: originalText, to: result)
        switch count {
        case 0:
            noteLabel.stringValue = "Só espaços ou quebras de linha mudaram. Revise antes de substituir."
        case 1:
            noteLabel.stringValue = "1 alteração destacada. Revise antes de substituir."
        default:
            noteLabel.stringValue = "\(count) alterações destacadas. Revise antes de substituir."
        }
    }

    /// A pessoa está ajustando o resultado: os destaques e a contagem são
    /// refeitos um instante depois da última tecla, para não disputar com a
    /// digitação.
    func textDidChange(_ notification: Notification) {
        guard !isGenerating, (notification.object as? NSTextView) === resultTextView else { return }
        pendingHighlight?.cancel()
        pendingHighlight = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self else { return }
            self.refreshHighlights()
            self.updateNote()
        }
    }

    // MARK: - Ações

    @objc private func confirmAction() {
        guard !isGenerating, confirmButton.isEnabled else { return }
        onConfirm(resultTextView.string)
    }

    @objc private func cancelAction() { onCancel() }

    @objc private func copyAction() {
        guard !isGenerating else { return }
        onCopy(resultTextView.string)
    }
}
