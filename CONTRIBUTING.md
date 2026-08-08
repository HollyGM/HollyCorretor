# Como contribuir com o HollyCorretor

Contribuições de código, testes e documentação são bem-vindas quando preservam o
escopo do projeto, a privacidade do processamento local e a compatibilidade
indicada no README.

## Antes de abrir uma issue

- Verifique se já existe relato ou proposta equivalente.
- Descreva o comportamento observado e o comportamento esperado.
- Informe a versão do macOS, a arquitetura do Mac e a versão do HollyCorretor.
- Nunca publique textos reais de clientes, documentos jurídicos, credenciais,
  chaves, dados pessoais ou qualquer outro conteúdo sigiloso.
- Em caso de vulnerabilidade, siga `SECURITY.md` em vez de abrir uma issue pública.

## Enviando uma alteração

1. Crie um fork e uma branch específica para a alteração.
2. Mantenha a mudança pequena e relacionada a um único objetivo.
3. Preserve o estilo e a organização existentes no código Swift.
4. Inclua ou atualize testes quando a alteração afetar o módulo `HollyCore`.
5. Execute as verificações locais:

```bash
./scripts/test.sh
./scripts/build.sh
```

6. Explique na pull request o problema, a solução adotada, os impactos e os testes
   executados.

## Compatibilidade e privacidade

Alterações não devem introduzir chamadas de rede, telemetria, envio de texto ou
armazenamento externo sem justificativa técnica clara e documentação expressa. Uma
proposta dessa natureza deve ser discutida antes da implementação.

## Licença das contribuições

Salvo declaração expressa em contrário, toda contribuição submetida
intencionalmente ao projeto será disponibilizada sob os termos da Apache License
2.0, conforme a Seção 5 da licença do repositório.

## Conduta

As discussões devem permanecer técnicas, respeitosas e voltadas à melhoria do
projeto. Comentários ofensivos, discriminatórios ou que exponham dados de terceiros
não serão aceitos.
