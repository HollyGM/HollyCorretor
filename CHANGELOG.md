# Histórico de versões

As alterações relevantes do HollyCorretor são registradas neste arquivo.

## 0.3.6 — 2026-09-25

- Recompilado e verificado no macOS 27.2 com o Swift 6.4: o projeto compila sem
  avisos de código e todos os testes do núcleo (`HollyCore`) passam. A
  atualização do sistema e da Apple Intelligence não exigiu nenhuma mudança de
  API além da migração já concluída na 0.3.5 (`GenerationError` →
  `LanguageModelError`, `sampling` → `samplingMode`, guardrails de transformação
  e Private Cloud Compute), confirmada contra a interface real do framework
  Foundation Models do SDK 27.
- Cópia instalada em `/Applications` regenerada contra o SDK do macOS 27.2 e
  assinada com a identidade estável do Chaveiro, de modo que os Serviços do menu
  de contexto e a permissão de Acessibilidade continuam valendo sem precisar
  autorizar de novo.

## 0.3.5 — 2026-09-11

- Impede que o painel de ações se feche sozinho pouco depois de aparecer no
  clique direito, quando o botão de seleção está ligado. O vigia da seleção só
  era suspenso no caminho da pastilha; pelo menu de Serviços ele continuava
  conferindo a seleção, que o próprio painel desfaz ao tomar o foco, e a tratava
  como desistência.
- Separa "a pastilha não faz mais sentido" de "a pessoa desistiu": agora só o
  clique ou a rolagem fora da interface encerra um painel aberto. A seleção
  deixar de existir passa apenas a esconder a pastilha.
- Interpreta a devolução de foco que o macOS 27 faz ao encerrar um Serviço.
  Ela chega depois do prazo fixo que a versão anterior supunha, e o painel
  retoma o foco em vez de se fechar, com um teto de retomadas para não disputar
  a ativação sem fim.
- Auditoria de compatibilidade com o macOS 27 (Swift 6.4): compila sem avisos,
  e a única API descontinuada no ciclo — `GenerationError` — já estava tratada.

## 0.3.4 — 2026-08-25

- Remove marcadores de resposta interrompidos no meio, incluindo `===FIM`,
  `===FIM=` e `===FIM==`, observados ao reescrever e simplificar no WhatsApp.
- Reconhece também as variantes truncadas de `===TEXTO===` sem apagar uma
  expressão semelhante que já faça parte do texto original.

## 0.3.3 — 2026-08-25

- Remove também envelopes abreviados como `===texto revisado===`, sem apagar
  sinais de igual que já faziam parte do texto original.
- Troca a pastilha larga de seleção por um acionador circular e discreto, mais
  próximo do comportamento contextual das Ferramentas de Escrita da Apple.
- Torna a prévia segura de aplicativos como o WhatsApp menor e contextual,
  posicionada junto da seleção em vez de centralizada na tela.

## 0.3.2 — 2026-08-25

- Posiciona o painel a partir da seleção real, não da posição do item no menu
  Serviços, impedindo que ele apareça cortado na borda da tela.
- Impede que o próprio clique no Serviço feche o painel recém-aberto e localiza
  corretamente o aplicativo que originou a seleção.
- Preserva e restaura o intervalo exato da seleção quando o editor perde o foco.
- Aplica revisões compatíveis diretamente no documento e mostra uma barra
  contextual com **Reverter**, visualização do original, contador e **OK**.
- Mantém uma prévia segura em editores sem suporte suficiente de Acessibilidade,
  em vez de colar o resultado às cegas no cursor.
- Substitui a janela central durante a geração por um indicador compacto junto
  do texto e remove os sons de confirmação do fluxo de correção.
- Adiciona testes do contador de alterações exibido após a revisão.

## 0.3.1 — 2026-08-25

- Substitui os treze Serviços soltos por um único item **HollyCorretor…** no
  clique direito; ele abre o painel completo de ações ao lado do cursor.
- Corrige a tentativa de criar submenu com uma barra no título, comportamento
  que o macOS deixou de oferecer e que ocultava o nome HollyCorretor.
- Aproxima o painel do visual das Ferramentas de Escrita da Apple, com cabeçalho,
  campo de instrução, ações agrupadas e indicação de processamento local.
- Ao pedir outra correção durante uma operação, traz a prévia para a frente ou
  explica o que está acontecendo, em vez de emitir apenas um bipe.
- Limpa o estado da operação quando a prévia é fechada, evitando que o app fique
  preso recusando todas as tentativas seguintes.

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
