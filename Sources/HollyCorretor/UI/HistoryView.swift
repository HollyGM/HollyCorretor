import AppKit

final class HistoryViewController: NSViewController {
    private var scrollView: NSScrollView!
    private var stackView: NSStackView!
    
    override func loadView() {
        let container = NSView()
        container.setFrameSize(NSSize(width: 560, height: 400))
        
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        
        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 16
        stackView.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: documentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor)
        ])
        
        scrollView.documentView = documentView
        container.addSubview(scrollView)
        
        let titleLabel = NSTextField(labelWithString: "Histórico de Correções")
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
        
        self.view = container
        renderHistory()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        renderHistory()
    }
    
    private func renderHistory() {
        stackView.views.forEach { $0.removeFromSuperview() }
        
        let items = HistoryStore.shared.items
        
        if items.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "Nenhum resultado salvo no histórico.")
            emptyLabel.textColor = .secondaryLabelColor
            stackView.addArrangedSubview(emptyLabel)
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        
        for item in items {
            let card = NSBox()
            card.boxType = .custom
            card.borderWidth = 1
            card.borderColor = .separatorColor
            card.cornerRadius = 8
            card.fillColor = .controlBackgroundColor
            card.translatesAutoresizingMaskIntoConstraints = false
            
            let cardStack = NSStackView()
            cardStack.orientation = .vertical
            cardStack.alignment = .leading
            cardStack.spacing = 8
            cardStack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
            cardStack.translatesAutoresizingMaskIntoConstraints = false
            
            let headerStack = NSStackView()
            headerStack.orientation = .horizontal
            headerStack.distribution = .gravityAreas
            headerStack.translatesAutoresizingMaskIntoConstraints = false
            
            let titleLabel = NSTextField(labelWithString: item.actionTitle)
            titleLabel.font = .boldSystemFont(ofSize: 13)
            
            let dateLabel = NSTextField(labelWithString: dateFormatter.string(from: item.date))
            dateLabel.font = .systemFont(ofSize: 11)
            dateLabel.textColor = .secondaryLabelColor
            
            headerStack.addView(titleLabel, in: .leading)
            headerStack.addView(dateLabel, in: .trailing)
            
            let textValue = NSTextField(wrappingLabelWithString: item.processedText)
            textValue.font = .systemFont(ofSize: 13)
            textValue.maximumNumberOfLines = 10
            textValue.lineBreakMode = .byTruncatingTail
            textValue.isSelectable = true
            
            let copyButton = CopyButton(title: "Copiar", textToCopy: item.processedText)
            copyButton.target = self
            copyButton.action = #selector(copyAction(_:))
            
            cardStack.addArrangedSubview(headerStack)
            cardStack.addArrangedSubview(textValue)
            cardStack.addArrangedSubview(copyButton)
            
            card.contentView = cardStack
            
            NSLayoutConstraint.activate([
                headerStack.widthAnchor.constraint(equalTo: cardStack.widthAnchor, constant: -24),
                textValue.widthAnchor.constraint(equalTo: cardStack.widthAnchor, constant: -24)
            ])
            
            stackView.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -32).isActive = true
        }
        
        let clearButton = NSButton(title: "Limpar Histórico", target: self, action: #selector(clearAction))
        stackView.addArrangedSubview(clearButton)
    }
    
    @objc private func copyAction(_ sender: CopyButton) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(sender.textToCopy, forType: .string)
        
        sender.title = "Copiado!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            sender.title = "Copiar"
        }
    }
    
    @objc private func clearAction() {
        let alert = NSAlert()
        alert.messageText = "Limpar todo o histórico?"
        alert.informativeText = "Esta ação remove os resultados armazenados pelo HollyCorretor neste Mac."
        alert.addButton(withTitle: "Limpar")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        HistoryStore.shared.clear()
        renderHistory()
    }
}

// Subclasse para anexar a string ao botão sem usar dicionários globais
final class CopyButton: NSButton {
    let textToCopy: String
    
    init(title: String, textToCopy: String) {
        self.textToCopy = textToCopy
        super.init(frame: .zero)
        self.title = title
        self.bezelStyle = .rounded
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) { return nil }
}

// Faz o topo da ScrollView iniciar no alto no AppKit
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
