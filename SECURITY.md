# Política de segurança

## Versões abrangidas

A linha atualmente mantida é a versão `0.2.x`. Versões anteriores podem não
receber correções.

## Como relatar uma vulnerabilidade

Não abra uma issue pública com detalhes que permitam explorar a vulnerabilidade.
Utilize o recurso privado **Report a vulnerability** na aba **Security** do
repositório, quando disponível. Caso esse recurso não apareça, estabeleça contato
privado com o mantenedor por meio do perfil do GitHub antes de compartilhar provas
de conceito ou dados sensíveis.

O relato deve conter, sempre que possível:

- versão do HollyCorretor e do macOS;
- arquitetura do Mac;
- descrição objetiva do impacto;
- passos mínimos para reprodução;
- comportamento esperado e comportamento observado;
- logs estritamente necessários, com dados pessoais, textos e caminhos privados
  removidos.

## Conteúdo que não deve ser publicado

Não inclua textos selecionados no aplicativo, documentos jurídicos, informações de
clientes, credenciais, chaves, histórico da área de transferência ou qualquer dado
pessoal ou sigiloso. Substitua esses elementos por exemplos artificiais.

## Escopo prioritário

São especialmente relevantes relatos relacionados a:

- envio inesperado de dados pela rede;
- exposição ou persistência indevida do histórico local;
- substituição incorreta do conteúdo da área de transferência;
- abuso das permissões de Acessibilidade;
- execução não intencional de comandos ou abertura de arquivos;
- manipulação do fluxo por conteúdo malicioso selecionado;
- comprometimento de dependências ou do processo de compilação.

## Divulgação responsável

Detalhes técnicos devem permanecer privados até que exista correção ou orientação
de mitigação. A publicação coordenada poderá ser ajustada conforme a gravidade e a
complexidade do problema.
