#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="HollyCorretor"
APP_VERSION="${HOLLY_VERSION:-0.3.0}"
APP_BUILD="${HOLLY_BUILD_NUMBER:-1}"
APP_DIR="$PROJECT_DIR/dist/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_TEMPLATE="$PROJECT_DIR/Resources/Info.plist"

# O macOS amarra a permissão de Acessibilidade à assinatura do binário. Com
# assinatura ad-hoc o identificador muda a cada compilação, e o sistema passa a
# tratar o app como outro — exigindo nova autorização toda vez. Defina
# HOLLY_SIGN_IDENTITY com um certificado do Chaveiro para ter identidade
# estável e não precisar reautorizar.
SIGN_IDENTITY="${HOLLY_SIGN_IDENTITY:--}"

command -v swift >/dev/null
command -v codesign >/dev/null
test -f "$INFO_TEMPLATE"

# Conferido antes de qualquer coisa: uma identidade inexistente só falharia na
# última etapa, depois de o pacote anterior já ter sido apagado.
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    if ! /usr/bin/security find-identity -v -p codesigning | grep -qF "$SIGN_IDENTITY"; then
        echo "Erro: não há identidade de assinatura chamada \"$SIGN_IDENTITY\" no Chaveiro." >&2
        echo "" >&2
        echo "Crie uma em Acesso às Chaves › menu Acesso às Chaves › Assistente de" >&2
        echo "Certificado › Criar um certificado, com:" >&2
        echo "  Nome................: $SIGN_IDENTITY" >&2
        echo "  Tipo de identidade..: Raiz autoassinada" >&2
        echo "  Tipo de certificado.: Assinatura de código" >&2
        echo "" >&2
        echo "Identidades disponíveis hoje:" >&2
        /usr/bin/security find-identity -v -p codesigning >&2
        exit 1
    fi
fi

cd "$PROJECT_DIR"
swift build -c release --product "$APP_NAME"
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$INFO_TEMPLATE" "$CONTENTS_DIR/Info.plist"

/usr/bin/plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$APP_BUILD" "$CONTENTS_DIR/Info.plist"

for bundle in "$BIN_DIR"/*.bundle; do
    if [[ -e "$bundle" ]]; then
        cp -R "$bundle" "$RESOURCES_DIR/"
    fi
done

chmod +x "$MACOS_DIR/$APP_NAME"
/usr/bin/plutil -lint "$CONTENTS_DIR/Info.plist"

# `--deep` está obsoleto: a Apple pede que os pacotes internos sejam assinados
# primeiro e o app por último.
for bundle in "$RESOURCES_DIR"/*.bundle; do
    if [[ -e "$bundle" ]]; then
        /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$bundle"
    fi
done

/usr/bin/codesign --force --sign "$SIGN_IDENTITY" \
    --identifier "com.hollycorretor.app" --timestamp=none "$APP_DIR"
/usr/bin/codesign --verify --strict "$APP_DIR"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "Aviso: assinatura ad-hoc. A permissão de Acessibilidade precisará ser" >&2
    echo "concedida de novo a cada compilação. Para evitar isso, crie um" >&2
    echo "certificado de assinatura de código no Acesso às Chaves e exporte" >&2
    echo "HOLLY_SIGN_IDENTITY com o nome dele." >&2
fi

echo "$APP_DIR"
