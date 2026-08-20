<p align="center">
  <img src="docs/branding/holly-banner.svg" alt="HollyCorretor — correção, reescrita e resumo no macOS" width="100%">
</p>

<p align="center">
  <strong>Correção, reescrita, formalização e resumo no macOS.</strong><br>
  Apple Intelligence · Privacidade por padrão · Revisão antes da substituição
</p>

<p align="center">
  <a href="https://github.com/HollyGM/HollyCorretor/actions/workflows/ci.yml"><img alt="Validação" src="https://github.com/HollyGM/HollyCorretor/actions/workflows/ci.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="Licença Apache 2.0" src="https://img.shields.io/badge/licença-Apache%202.0-blue.svg"></a>
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-black.svg">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6.0-orange.svg">
</p>

> **Parte da suíte Holly**  
> Ferramentas local-first para texto, documentos e mídia, com privacidade por padrão e segurança verificável.  
> [HollyOCR](https://github.com/HollyGM/HollyOCR) · [HollyTranscrição](https://github.com/HollyGM/HollyTranscricao) · [HollyOptimizer](https://github.com/HollyGM/HollyOptimizer)

Aplicativo de barra de menus para macOS que corrige, reescreve, formaliza,
simplifica ou resume o texto selecionado. O processamento usa o modelo local da
Apple Intelligence por meio do framework Foundation Models; o texto não é enviado
a uma API de terceiros.

<p align="center">
  <img src="docs/images/preview-formalizar.png" width="820"
       alt="Menu da barra de status do HollyCorretor aberto ao lado do painel de prévia da ação Formalizar (juridiquês), mostrando o texto original e a versão em linguagem jurídica formal com os botões Cancelar, Copiar e Substituir.">
</p>

<p align="center">
  <em>Painel de prévia da ação <strong>Formalizar (juridiquês)</strong> com o menu da barra de status aberto.
  Todo resultado é revisado antes de substituir o texto original.</em>
</p>

Versão atual: **0.3.0** — consulte o [histórico de versões](CHANGELOG.md).

## Compatibilidade

- macOS 26 (Tahoe) ou posterior.
- Mac com Apple Silicon compatível com Apple Intelligence.
- Apple Intelligence ativada e com o modelo local concluído.
- Um MacBook com chip M5 atende ao requisito de arquitetura; a disponibilidade
  final também depende da versão do macOS, da região e das configurações da Apple
  Intelligence.

O aplicativo ainda não funciona no Windows ou Linux. A interface, os atalhos
globais, a leitura da seleção e o modelo de IA usam APIs exclusivas do macOS. A
lógica independente dessas APIs está no módulo `HollyCore`, que compila
separadamente e serve de base para futuros clientes de outras plataformas.

## Ações e atalhos iniciais

Todos os atalhos usam `Control + Option + Command` mais a tecla indicada e podem
ser alterados em **Preferências**.

| Ação | Tecla | Resultado |
|---|---:|---|
| Corrigir ortografia | `C` | Corrige ortografia, gramática, acentuação e pontuação. |
| Reescrever | `K` ou `R` | Melhora clareza, fluidez e estrutura. |
| Formalizar | `F` | Adapta para linguagem jurídica formal. |
| Simplificar | `S` | Torna o texto acessível para quem não tem formação jurídica. |
| Resumir | `Z` | Gera um resumo executivo com decisões, prazos e próximos passos. |
| Ação personalizada | `P` | Aplica a instrução definida em Preferências. |
| Salvar como Markdown | `M` | Abre uma janela para salvar a seleção em um arquivo `.md`. |

## Interface

O HollyCorretor vive na barra de menus, sem ícone no Dock. Ao acionar uma ação —
por atalho, pelo ícone da barra de menus ou pelo menu **Serviços** — o resultado
aparece em um painel de prévia editável sobre o aplicativo em uso; nada é
substituído sem confirmação.

Os atalhos, a instrução da **Ação personalizada** e o histórico local são
ajustados em **Preferências**:

<p align="center">
  <img src="docs/images/preferencias.png" width="560"
       alt="Janela de Preferências do HollyCorretor com as opções de iniciar com o Mac e salvar o histórico local, os campos de atalho de cada ação e o campo de instrução personalizada.">
</p>

## Como compilar e usar

É necessário ter as Command Line Tools da Apple ou o Xcode com o SDK do macOS 26
ou posterior.

```bash
git clone https://github.com/HollyGM/HollyCorretor.git
cd HollyCorretor
./scripts/run.sh
```

O script compila o app, cria `dist/HollyCorretor.app`, aplica uma assinatura local,
registra os itens do menu Serviços e abre o aplicativo.

No primeiro uso:

1. Autorize o HollyCorretor em **Ajustes do Sistema › Privacidade e Segurança ›
   Acessibilidade**.
2. Selecione o texto em um aplicativo compatível.
3. Use um atalho, uma ação no ícone da barra de menus ou um item de
   **Serviços › HollyCorretor**.
4. Revise o resultado na prévia.
5. Escolha **Substituir**, **Copiar** ou **Cancelar**.

O HollyCorretor nunca envia a mensagem automaticamente.

## Privacidade e segurança

- O modelo padrão roda no dispositivo por meio da Apple Intelligence.
- O aplicativo não contém chaves de API nem implementa chamadas de rede em tempo
  de execução.
- O histórico **nasce desligado**. Quando ativado em Preferências, guarda os 10
  resultados mais recentes em `~/Library/Application Support/HollyCorretor/`,
  em arquivo com permissão restrita e proteção de dados — não mais em texto
  claro dentro do plist de preferências. Pode ser apagado pelo menu.
- O envio ao Private Cloud Compute também nasce desligado. Com a opção ativada,
  apenas textos que não cabem no modelo local saem do aparelho, rumo aos
  servidores da Apple. Para material sob sigilo, mantenha-a desligada.
- Quando o aplicativo de origem expõe o campo pela API de Acessibilidade, o
  resultado é escrito direto nele e a área de transferência não é tocada.
- No caminho alternativo, que usa a área de transferência, o conteúdo anterior
  só é restaurado se ela não tiver sido alterada novamente; assim, uma cópia
  feita durante o processamento não é sobrescrita.

## Limites do modelo local

Numa tarefa de transformação, o modelo on-device devolve no máximo cerca de
2.400 caracteres por resposta. Textos maiores são divididos automaticamente em
blocos — preferindo fim de parágrafo, quebra de linha e fim de frase, nessa
ordem — e recompostos ao final. O aplicativo ainda confere o tamanho de cada
resposta e refaz o bloco dividido se o modelo tiver condensado o texto em vez de
transformá-lo.

Esse teto vem da fidelidade da saída, não da janela de contexto, que é bem maior
(8.192 tokens). Para resumos, em que encurtar é o resultado desejado, os blocos
podem ser bem maiores.

Para relatar uma vulnerabilidade sem expor detalhes publicamente, consulte a
[política de segurança](SECURITY.md).

## Limitações de uso

Resultados produzidos por modelos generativos podem conter erros, omissões ou
alterações indesejadas. Todo resultado deve ser revisado antes de ser substituído,
copiado ou utilizado. A ação de formalização auxilia a redação, mas não constitui
parecer jurídico nem valida fatos, fundamentos ou conclusões.

## Desenvolvimento

```bash
./scripts/test.sh
./scripts/build.sh
```

Estrutura principal:

- `Sources/HollyCore`: regras, divisão segura de textos e limpeza de respostas;
- `Sources/HollyCorretor`: integração com Apple Intelligence e recursos do macOS;
- `Tests/HollyCoreChecks`: testes automatizados do núcleo portátil;
- `Resources/Info.plist`: metadados do app e declaração dos Serviços do macOS;
- `scripts`: compilação, empacotamento e execução local.

O fluxo do GitHub Actions executa testes e uma compilação de produção em macOS 26.
As orientações para propostas de alteração estão em [CONTRIBUTING.md](CONTRIBUTING.md).

## Dependência de terceiros

O projeto utiliza `KeyboardShortcuts` 1.15.0, de Sindre Sorhus, distribuído sob a
Licença MIT. As atribuições e o texto aplicável estão em
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Assinatura e a permissão de Acessibilidade

O macOS identifica um aplicativo autorizado pela assinatura do binário. Com
assinatura ad hoc, essa identidade muda a cada compilação, e o sistema passa a
tratar o app como se fosse outro — exigindo autorizar de novo em **Ajustes do
Sistema › Privacidade e Segurança › Acessibilidade** toda vez que você compila.

Para ter identidade estável, crie um certificado de assinatura de código. O
aplicativo **Acesso às Chaves** não existe mais no macOS 27, então o caminho é o
Terminal:

```bash
# 1. Gerar o certificado, já com a finalidade de assinatura de código
cat > /tmp/holly.cnf <<'CNF'
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no
[ dn ]
CN = HollyCorretor
[ ext ]
basicConstraints       = critical,CA:false
keyUsage               = critical,digitalSignature
extendedKeyUsage       = critical,codeSigning
subjectKeyIdentifier   = hash
CNF
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout /tmp/holly.key -out /tmp/holly.crt -config /tmp/holly.cnf

# O -legacy e a senha são necessários: o macOS não lê o formato novo do
# OpenSSL 3, e senha vazia faz a verificação do MAC falhar na importação.
openssl pkcs12 -export -legacy -out /tmp/HollyCorretor.p12 \
  -inkey /tmp/holly.key -in /tmp/holly.crt -name "HollyCorretor" -passout pass:holly

# 2. Importar e marcar como confiável
security import /tmp/HollyCorretor.p12 -k ~/Library/Keychains/login.keychain-db \
  -P holly -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign \
  -k ~/Library/Keychains/login.keychain-db /tmp/holly.crt

# 3. Conferir
security find-identity -v -p codesigning
```

Com o certificado no lugar, informe o nome dele ao compilar:

```bash
HOLLY_SIGN_IDENTITY="Nome do certificado" ./scripts/run.sh
```

Sem a variável, o script continua usando assinatura ad hoc e avisa a respeito.

A diferença aparece no requisito designado, que é o que o macOS guarda ao
autorizar o aplicativo. Com assinatura ad hoc ele fixa o `cdhash` do binário, que
muda a cada compilação; com o certificado, fixa o identificador e o certificado,
que não mudam — e a autorização de Acessibilidade sobrevive às recompilações.

## Distribuição

Para distribuir um binário pronto a outras pessoas sem alertas do Gatekeeper,
ainda será necessário usar uma conta Apple Developer, assinatura Developer ID e
notarização. O código fonte pode ser compilado localmente sem essas credenciais.

## Licença

O código original do HollyCorretor é disponibilizado sob a
[Apache License 2.0](LICENSE). Componentes de terceiros permanecem sujeitos às
respectivas licenças; consulte [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
