# Histórico de versões

As alterações relevantes do HollyCorretor são registradas neste arquivo.

## 0.2.0 — 2026-08-08

- Renomeia o aplicativo de ZapCorrector para HollyCorretor.
- Separa o núcleo de tratamento de texto para facilitar testes e futura portabilidade.
- Atualiza KeyboardShortcuts de 1.10.0 para 1.15.0, a versão mais recente compatível com compilação usando apenas as Command Line Tools.
- Preserva espaços, quebras e delimitadores legítimos do texto original.
- Evita sobrescrever conteúdo novo copiado durante o processamento.
- Remove a seleção automática de todo o documento quando não há texto selecionado.
- Corrige a declaração dos Serviços do macOS para o fluxo assíncrono do aplicativo.
- Substitui o salvamento automático de Markdown por uma escolha explícita de destino.
- Adiciona testes automatizados e validação contínua no GitHub.
