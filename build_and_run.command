#!/bin/bash
cd "$(dirname "$0")"
echo "=== Compilando o HollyCorretor ==="
./scripts/run.sh
STATUS=$?
echo ""
if [ $STATUS -eq 0 ]; then
  echo "=== Compilação concluída com sucesso. ==="
else
  echo "=== A compilação FALHOU (status $STATUS). Veja o erro acima. ==="
fi
echo ""
echo "Pressione Enter para fechar esta janela."
read
