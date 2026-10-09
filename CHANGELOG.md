# Histórico de versões

As alterações relevantes do HollyCorretor são registradas neste arquivo.

## 0.4.0 — 2026-10-09

### Siri e app Atalhos

- Adiciona o endereço `hollycorretor://<ação>` (`revisar`, `reescrever`,
  `formalizar`, `simplificar`, `resumir`, `amigavel`, `profissional`,
  `conciso`, `pontos-principais`, `lista`, `tabela`, `personalizada` e
  `markdown`). A ação vale para o texto selecionado no aplicativo que estava
  em uso, com a mesma conferência dos atalhos de teclado. Instruções livres não
  são aceitas pelo endereço, para que uma página da web não possa ditar o que
  fazer com o texto.
- `scripts/atalhos-siri.sh` cria cinco atalhos do app Atalhos ("Revisar com
  Holly", "Reescrever com Holly", "Formalizar com Holly", "Simplificar com
  Holly" e "Resumir com Holly"), que a Siri executa pelo nome.
- Adiciona as App Intents nativas: cinco ações sobre o texto selecionado, com
  frases da Siri em português ("Revisar texto com o HollyCorretor"), uma ação
  com a ação como parâmetro e "Processar texto", que devolve o resultado para
  outras etapas do atalho. Os metadados que o Xcode geraria são escritos pelo
  próprio binário durante a compilação, com os nomes de tipo conferidos contra
  o código. O macOS só executa App Intents de aplicativos assinados com
  certificado da Apple (Team ID); por isso o `build.sh` as inclui no pacote
  apenas nessa condição, em vez de anunciar ações que falhariam.
- Declara nomes alternativos do app para a Siri ("Holly Corretor",
  "Corretor Holly", "Holly").
- Recusa o pedido de encerramento que o `linkd` envia 30 segundos depois de
  executar uma App Intent. Sem isso, cada uso pela Siri fechava o HollyCorretor
  da barra de menus. Sair pelo menu, encerrar a sessão e desligar o Mac
  continuam funcionando.

### Correções

- A cópia de segurança da área de transferência passa a ser feita só quando a
  colagem é necessária. Antes ela era tirada no início da ação e, na colagem de
  retaguarda, podia sobrescrever algo copiado durante o processamento — além
  de duplicar a cada atalho o conteúdo inteiro da área de transferência,
  imagens grandes inclusive.
- O ícone da barra não fica mais preso em "processando" quando a colagem pela
  prévia é recusada, e não volta ao repouso no meio de uma nova operação
  iniciada logo após a anterior.
- Depois de colar pela prévia, o app não fica mais dois segundos recusando o
  próximo atalho enquanto espera para restaurar a área de transferência.
- Começar uma nova ação enquanto a barra de conferência espera o OK conta como
  confirmação, como nas Ferramentas de Escrita da Apple, em vez de bloquear
  qualquer correção até a barra ser fechada. A confirmação implícita não move
  o cursor nem tira o foco da nova seleção.
- Um aplicativo travado não congela mais o clique direito por vários
  segundos: a busca pela seleção usa um prazo curto da Acessibilidade e para
  assim que encontra a seleção sob o ponteiro.
- O menu da barra não abre mais um alerta modal no meio do próprio menu quando
  o botão de seleção não consegue ser religado.
- Fechar Preferências não tira mais a janela de Histórico do Dock (e
  vice-versa) quando as duas estão abertas.
- Os alertas passam a abrir acima das outras janelas. Quando o app não estava
  ativo, eles podiam abrir atrás do editor e, como bloqueiam o app até serem
  fechados, davam a impressão de travamento.

### Validação

- Validado no macOS 27.2 com Swift 6.4: testes do núcleo, compilação de
  produção e auditoria de depreciações com alvo no macOS 27. O atalho
  "Revisar com Holly" foi executado de ponta a ponta: a seleção do TextEdit foi
  lida em segundo plano, corrigida pelo modelo local e aplicada no documento.
  As App Intents foram indexadas pelo sistema (ações e frases em pt-BR) e, sem
  Team ID, recusadas pelo linkd; nesse teste, o app recusou o pedido de
  encerramento e continuou na barra de menus.

## 0.3.7 — 2026-10-02

- Corrige um estouro numérico que encerrava o aplicativo ao calcular o tamanho
  dos blocos para resumos, listas e outras ações com Private Cloud Compute.
- Exige a correspondência do intervalo e do texto capturados antes de substituir
  uma seleção. A colagem alternativa também verifica o campo com foco, evitando
  atingir outra ocorrência idêntica ou outro campo do mesmo aplicativo.
- Mantém o cancelamento disponível até a aplicação do resultado e impede que
  uma operação cancelada altere o texto ou feche o painel de uma operação nova.
- Vincula o botão flutuante ao aplicativo, campo e intervalo de origem; mudanças
  de foco pelo teclado invalidam seleções antigas.
- Preserva espaços e quebras de linha exatamente na fronteira entre blocos e
  recusa respostas excessivamente reduzidas nas ações que preservam conteúdo
  quando não há mais como dividir e tentar novamente.
- Reduz o trabalho do contador de alterações em documentos longos ao excluir
  os trechos iguais no começo e no fim da comparação.
- Apagar o histórico também remove cópias antigas cuja migração ficou pendente,
  impedindo que os resultados apagados reapareçam na próxima abertura.
- Compilação e instalação passam a preparar e verificar as novas cópias antes
  de substituir as anteriores, com restauração em caso de falha. O certificado
  da cópia instalada é reutilizado automaticamente quando está no Chaveiro.
- Versão e número de compilação passam a vir de `Resources/Info.plist`, com as
  substituições opcionais por variáveis de ambiente preservadas.
- Validado no macOS 27.2 com Swift 6.4: testes do núcleo, compilação de produção,
  assinatura e cenários de recuperação da instalação. O modelo local corrigiu
  textos de teste curtos e um texto de 3.111 caracteres com 14 registros, sem
  perder os registros ou os separadores entre parágrafos.

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
- `scripts/run.sh` passa a descartar a cópia de `dist/` depois de promovê-la
  para `/Applications`. Enquanto ela ficava em disco, o LaunchServices voltava a
  registrá-la a cada build e o macOS ficava com duas cópias do mesmo
  identificador concorrendo por qual abrir e qual expõe o Serviço do clique
  direito.

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
