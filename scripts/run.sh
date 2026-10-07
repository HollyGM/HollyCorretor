#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/dist/HollyCorretor.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
INSTALLED="/Applications/HollyCorretor.app"
UPDATE_DIR=""
PREVIOUS_APP=""
INSTANCES_STOPPED=0

cleanup() {
    local status=$?
    if [[ "$status" -ne 0 && -n "$PREVIOUS_APP" && -d "$PREVIOUS_APP" ]]; then
        echo "A atualização falhou; restaurando o aplicativo anterior..." >&2
        rm -rf "$INSTALLED"
        if ! mv "$PREVIOUS_APP" "$INSTALLED"; then
            echo "A cópia anterior foi preservada em: $PREVIOUS_APP" >&2
            return 1
        fi
        "$LSREGISTER" -f "$INSTALLED" || true
        /System/Library/CoreServices/pbs -update || true
        if [[ "$INSTANCES_STOPPED" -eq 1 ]]; then
            open "$INSTALLED" || true
        fi
    fi
    if [[ -n "$UPDATE_DIR" ]]; then
        rm -rf "$UPDATE_DIR"
    fi
    return "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Compila antes de encerrar o que está rodando: se a compilação falhar, o
# aplicativo em uso continua de pé em vez de sumir junto.
echo "Compilando o HollyCorretor..."
"$ROOT_DIR/scripts/build.sh"

# A cópia é preparada e conferida antes de encerrar o app em uso. O diretório
# temporário fica no mesmo volume do destino para a promoção ser uma renomeação.
if [[ -d "$INSTALLED" ]]; then
    echo "Preparando a atualização da cópia instalada em /Applications..."
    UPDATE_DIR="$(mktemp -d "/Applications/.holly-update.XXXXXX")"
    STAGED_APP="$UPDATE_DIR/HollyCorretor.app"
    PREVIOUS_APP="$UPDATE_DIR/previous.app"
    ditto "$APP_PATH" "$STAGED_APP"
    /usr/bin/codesign --verify --strict "$STAGED_APP"
fi

echo "Encerrando instâncias anteriores do HollyCorretor..."
killall HollyCorretor || true
killall ZapCorrector || true
INSTANCES_STOPPED=1

# Se já existe uma cópia instalada, ela é atualizada e passa a ser a que roda.
# Duas cópias com o mesmo identificador fazem o macOS escolher qual abrir, e o
# resultado é testar uma versão antiga achando que é a recém-compilada.
if [[ -d "$INSTALLED" ]]; then
    echo "Atualizando a cópia instalada em /Applications..."
    mv "$INSTALLED" "$PREVIOUS_APP"
    mv "$STAGED_APP" "$INSTALLED"
    /usr/bin/codesign --verify --strict "$INSTALLED"
    "$LSREGISTER" -u "$APP_PATH" || true
    APP_PATH="$INSTALLED"
fi

echo "Registrando o aplicativo no macOS..."
"$LSREGISTER" -f "$APP_PATH"

echo "Atualizando o menu Serviços..."
/System/Library/CoreServices/pbs -update

echo "Abrindo o HollyCorretor..."
open "$APP_PATH"

# Depois de instalar e abrir, descarta a cópia de dist/ para não haver dois
# aplicativos com o mesmo identificador concorrendo no LaunchServices.
if [[ "$APP_PATH" == "$INSTALLED" ]]; then
    rm -rf "$ROOT_DIR/dist/HollyCorretor.app"
fi
