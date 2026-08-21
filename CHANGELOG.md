# Histórico de versões

As alterações relevantes do HollyCorretor são registradas neste arquivo.

## 0.3.0 — 2026-08-20

### Correções

- Impede que o delimitador `===TEXTO===` vaze para dentro do texto revisado. A
  limpeza exigia o delimitador de abertura e o de fechamento juntos, mas o
  modelo com frequência devolve só a abertura; em texto de vários parágrafos
  isso acontecia em todas as tentativas.
- Restabelece o tratamento de erro no macOS 27. O sistema passou a lançar
  `LanguageModelError` no lugar de `GenerationError`, e o app capturava apenas o
  tipo antigo — o que desativava em silêncio a divisão automática de textos
  longos e fazia todas as mensagens em português serem substituídas pelo texto
  cru do framework, em inglês.
- Remove frases de apresentação do tipo "Aqui está o texto corrigido:" quando o
  modelo as acrescenta, preservando aberturas legítimas do próprio texto.

### Apple Intelligence

- Adota os guardrails `permissiveContentTransformations`, próprios para
  transformação de texto que a pessoa já possui. Os guardrails padrão recusavam
  trechos jurídicos legítimos, como a descrição típica do artigo 217-A.
- Mostra o texto enquanto ele é gerado, em vez de esperar o fim. O primeiro
  trecho aparece em cerca de 0,7 s, contra 3,3 s até a resposta completa.
- Permite cancelar uma geração em andamento.
- Corrige perda de conteúdo em textos com mais de ~2.500 caracteres. Numa tarefa
  de transformação o modelo local não produz mais que cerca de 2.400 caracteres
  por resposta: acima disso ele condensa o texto em vez de transformá-lo por
  inteiro, em silêncio. Com o limite anterior de 4.000 caracteres, um documento
  de 6.800 caracteres voltava com dois terços do tamanho original. O tamanho dos
  blocos passou a ser calibrado por essa medida, e não pela janela de contexto,
  que comporta bem mais (8.192 tokens) e não é o limite que vale.
- Confere o tamanho de cada resposta e refaz o bloco dividido quando o modelo
  devolve menos do que recebeu, para que o comportamento continue correto se o
  ponto de virada mudar com o texto ou com a versão do sistema.
- Usa a contagem de tokens do próprio framework para o orçamento de contexto,
  no lugar de estimativas fixas.
- Usa amostragem gulosa na correção ortográfica, para o mesmo texto produzir
  sempre o mesmo resultado.
- Define um teto de tokens de resposta como proteção contra geração desgovernada.
- Carrega o modelo em paralelo com a captura da seleção.
- Opção de usar o Private Cloud Compute em textos que não cabem no modelo local.
  Desligada por padrão, porque o conteúdo sai do aparelho.

### Comportamento

- Divide o texto preferindo fim de parágrafo, quebra de linha e fim de frase,
  nessa ordem, em vez de cortar em qualquer espaço.
- Devolve o resultado escrevendo direto no campo de origem pela API de
  Acessibilidade quando possível, sem usar a área de transferência nem simular
  teclas. A colagem por ⌘V continua como alternativa.
- Avisa quando a entrada protegida do sistema está ativa, situação em que
  eventos de teclado sintéticos são descartados sem erro.

### Privacidade

- O histórico passa a nascer desligado e a ser gravado em arquivo próprio, com
  permissão restrita e proteção de dados, em vez de ficar em texto claro no
  plist de preferências. O conteúdo existente é transferido e removido do plist.

### Desenvolvimento

- A validação contínua passa a rodar também na versão mais recente do macOS, e
  não só na do alvo declarado.
- Nova etapa que compila com a plataforma elevada para revelar APIs depreciadas
  acima do alvo — a ausência disso foi o que deixou passar a troca de
  `GenerationError`.
- O empacotamento aceita uma identidade de assinatura estável em
  `HOLLY_SIGN_IDENTITY`. Com assinatura ad-hoc, o identificador muda a cada
  compilação e o macOS exige nova autorização de Acessibilidade todas as vezes.
- Substitui o `codesign --deep`, obsoleto, pela assinatura dos pacotes internos
  antes do aplicativo.

## 0.3.0 — 2026-08-20

- Agrupa as ações num submenu **HollyCorretor** dentro do menu de Serviços,
  acessível pelo clique direito sobre o texto selecionado.
- Acrescenta as ações Amigável, Profissional, Conciso, Pontos Principais, Lista
  e Tabela.
- Corrige perda silenciosa de conteúdo em textos acima de ~2.500 caracteres.
- Corrige o vazamento do delimitador `===TEXTO===` para dentro do resultado.
- Restaura o tratamento de erro, que havia parado de funcionar no macOS 27.
- Deixa de bloquear texto jurídico legítimo, com guardrails de transformação.
- Mostra o texto enquanto é gerado e permite cancelar.
- Escreve o resultado direto no campo pela Acessibilidade quando possível.
- Passa a aceitar identidade de assinatura estável, para a autorização de
  Acessibilidade sobreviver às recompilações.
- Histórico desligado por padrão e gravado em arquivo protegido.

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
