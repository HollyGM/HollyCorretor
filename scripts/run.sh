#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/dist/HollyCorretor.app"

echo "Encerrando instâncias anteriores do HollyCorretor..."
killall HollyCorretor || true
killall ZapCorrector || true

echo "Compilando o HollyCorretor..."
"$ROOT_DIR/scripts/build.sh"

echo "Registrando o aplicativo no macOS..."
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$APP_PATH"

echo "Atualizando o menu Serviços..."
/System/Library/CoreServices/pbs -update

echo "Abrindo o HollyCorretor..."
open "$APP_PATH"
