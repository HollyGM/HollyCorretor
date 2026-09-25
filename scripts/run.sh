#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/dist/HollyCorretor.app"

# Compila antes de encerrar o que está rodando: se a compilação falhar, o
# aplicativo em uso continua de pé em vez de sumir junto.
echo "Compilando o HollyCorretor..."
"$ROOT_DIR/scripts/build.sh"

echo "Encerrando instâncias anteriores do HollyCorretor..."
killall HollyCorretor || true
killall ZapCorrector || true

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
INSTALLED="/Applications/HollyCorretor.app"

# Se já existe uma cópia instalada, ela é atualizada e passa a ser a que roda.
# Duas cópias com o mesmo identificador fazem o macOS escolher qual abrir, e o
# resultado é testar uma versão antiga achando que é a recém-compilada.
if [[ -d "$INSTALLED" ]]; then
    echo "Atualizando a cópia instalada em /Applications..."
    rm -rf "$INSTALLED"
    ditto "$APP_PATH" "$INSTALLED"
    # Promovida a cópia para /Applications, a de dist/ é descartada. Enquanto ela
    # permanecia em disco, o LaunchServices voltava a registrá-la a cada build, e
    # duas cópias com o mesmo identificador fazem o macOS escolher qual abrir e
    # qual expõe o Serviço do clique direito. Desregistra antes de apagar para o
    # sistema esquecê-la de imediato, em vez de esperar a próxima varredura.
    "$LSREGISTER" -u "$APP_PATH"
    rm -rf "$APP_PATH"
    APP_PATH="$INSTALLED"
fi

echo "Registrando o aplicativo no macOS..."
"$LSREGISTER" -f "$APP_PATH"

echo "Atualizando o menu Serviços..."
/System/Library/CoreServices/pbs -update

echo "Abrindo o HollyCorretor..."
open "$APP_PATH"
