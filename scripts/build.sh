#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="HollyCorretor"
INFO_TEMPLATE="$PROJECT_DIR/Resources/Info.plist"
test -f "$INFO_TEMPLATE"
APP_VERSION="${HOLLY_VERSION:-$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$INFO_TEMPLATE")}"
APP_BUILD="${HOLLY_BUILD_NUMBER:-$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$INFO_TEMPLATE")}"
APP_DIR="$PROJECT_DIR/dist/${APP_NAME}.app"
INSTALLED_APP="/Applications/${APP_NAME}.app"

# Monta e valida o pacote fora do destino final. Uma falha de cópia ou assinatura
# deixa a última compilação utilizável, em vez de apagar o pacote anterior.
mkdir -p "$PROJECT_DIR/dist"
STAGING_DIR="$(mktemp -d "$PROJECT_DIR/dist/.holly-build.XXXXXX")"
STAGED_APP="$STAGING_DIR/${APP_NAME}.app"
PREVIOUS_APP="$STAGING_DIR/previous.app"
CONTENTS_DIR="$STAGED_APP/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cleanup() {
    local status=$?
    if [[ -d "$PREVIOUS_APP" && ! -e "$APP_DIR" ]]; then
        mv "$PREVIOUS_APP" "$APP_DIR" || return 1
    fi
    rm -rf "$STAGING_DIR"
    return "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

command -v swift >/dev/null
command -v codesign >/dev/null
test -f "$INFO_TEMPLATE"

IDENTITIES="$(/usr/bin/security find-identity -v -p codesigning)"

has_signing_identity() {
    local line
    local identity_pattern='^[[:space:]]*[[:digit:]]+\)[[:space:]]+([[:xdigit:]]{40})[[:space:]]+"(.*)"$'
    while IFS= read -r line; do
        if [[ "$line" =~ $identity_pattern ]]; then
            if [[ "${BASH_REMATCH[1]}" == "$1" || "${BASH_REMATCH[2]}" == "$1" ]]; then
                return 0
            fi
        fi
    done <<< "$IDENTITIES"
    return 1
}

# Reutiliza o certificado exato da cópia instalada quando a variável não foi
# informada. O nome sozinho pode corresponder a outro certificado e mudar a
# identidade que sustenta a autorização de Acessibilidade.
SIGN_IDENTITY="${HOLLY_SIGN_IDENTITY:--}"
if [[ -z "${HOLLY_SIGN_IDENTITY:-}" && -d "$INSTALLED_APP" ]]; then
    if ! /usr/bin/codesign -d --extract-certificates="$STAGING_DIR/certificate" \
        "$INSTALLED_APP" >/dev/null 2>&1; then
        echo "Erro: não foi possível conferir a assinatura do aplicativo instalado." >&2
        echo "Informe HOLLY_SIGN_IDENTITY explicitamente para escolher a identidade da atualização." >&2
        exit 1
    fi
    if [[ -f "$STAGING_DIR/certificate0" ]]; then
        INSTALLED_IDENTITY="$(/usr/bin/shasum -a 1 "$STAGING_DIR/certificate0" | awk '{print toupper($1)}')"
        if has_signing_identity "$INSTALLED_IDENTITY"; then
            SIGN_IDENTITY="$INSTALLED_IDENTITY"
            echo "Preservando o certificado de assinatura do aplicativo instalado."
        else
            echo "Erro: o certificado do aplicativo instalado não está disponível para assinatura." >&2
            echo "Restaure a identidade no Chaveiro ou informe HOLLY_SIGN_IDENTITY explicitamente." >&2
            exit 1
        fi
    fi
fi

if [[ "$SIGN_IDENTITY" != "-" ]]; then
    if ! has_signing_identity "$SIGN_IDENTITY"; then
        echo "Erro: não há identidade de assinatura válida \"$SIGN_IDENTITY\" no Chaveiro." >&2
        echo "Identidades disponíveis hoje:" >&2
        printf '%s\n' "$IDENTITIES" >&2
        exit 1
    fi
fi

cd "$PROJECT_DIR"
swift build -c release --product "$APP_NAME"
BIN_DIR="$(swift build -c release --show-bin-path)"

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
    --identifier "com.hollycorretor.app" --timestamp=none "$STAGED_APP"
/usr/bin/codesign --verify --strict "$STAGED_APP"

if [[ -e "$APP_DIR" ]]; then
    mv "$APP_DIR" "$PREVIOUS_APP"
fi
mv "$STAGED_APP" "$APP_DIR"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "Aviso: assinatura ad-hoc. A permissão de Acessibilidade precisará ser" >&2
    echo "concedida de novo a cada compilação. Para evitar isso, crie um" >&2
    echo "certificado de assinatura de código no Acesso às Chaves e exporte" >&2
    echo "HOLLY_SIGN_IDENTITY com o nome dele." >&2
fi

echo "$APP_DIR"
