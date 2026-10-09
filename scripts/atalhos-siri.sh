#!/usr/bin/env bash
set -euo pipefail

# Cria atalhos do app Atalhos que a Siri executa pelo nome: "E aí Siri, revisar
# com Holly". Cada atalho só abre hollycorretor://<ação>, e o HollyCorretor age
# sobre o texto selecionado no aplicativo em uso, com a mesma conferência dos
# atalhos de teclado.
#
# Este caminho funciona com qualquer assinatura. As ações nativas (App Intents)
# dispensam estes atalhos, mas o macOS só as executa em aplicativos assinados
# com certificado da Apple; veja o README.
#
# Uso: ./scripts/atalhos-siri.sh
# O app Atalhos pede uma confirmação para cada atalho importado.

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$PROJECT_DIR/dist/Atalhos da Siri"
mkdir -p "$OUTPUT_DIR"

command -v shortcuts >/dev/null

EXISTING="$(shortcuts list 2>/dev/null || true)"

create_shortcut() {
    local name="$1"
    local action="$2"
    # O `shortcuts sign` reconhece o formato pela extensão: com .plist ele
    # recusa o arquivo.
    local plist="$OUTPUT_DIR/.$action-sem-assinatura.shortcut"
    local signed="$OUTPUT_DIR/$name.shortcut"

    if grep -Fxq "$name" <<< "$EXISTING"; then
        echo "Já existe: $name"
        return
    fi

    cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>WFWorkflowActions</key>
	<array>
		<dict>
			<key>WFWorkflowActionIdentifier</key>
			<string>is.workflow.actions.openurl</string>
			<key>WFWorkflowActionParameters</key>
			<dict>
				<key>WFInput</key>
				<dict>
					<key>Value</key>
					<dict>
						<key>attachmentsByRange</key>
						<dict/>
						<key>string</key>
						<string>hollycorretor://$action</string>
					</dict>
					<key>WFSerializationType</key>
					<string>WFTextTokenString</string>
				</dict>
			</dict>
		</dict>
	</array>
	<key>WFWorkflowClientVersion</key>
	<string>3000</string>
	<key>WFWorkflowIcon</key>
	<dict>
		<key>WFWorkflowIconGlyphNumber</key>
		<integer>59511</integer>
		<key>WFWorkflowIconStartColor</key>
		<integer>4251333119</integer>
	</dict>
	<key>WFWorkflowImportQuestions</key>
	<array/>
	<key>WFWorkflowInputContentItemClasses</key>
	<array/>
	<key>WFWorkflowMinimumClientVersion</key>
	<integer>900</integer>
	<key>WFWorkflowMinimumClientVersionString</key>
	<string>900</string>
	<key>WFWorkflowTypes</key>
	<array/>
</dict>
</plist>
PLIST
    /usr/bin/plutil -convert binary1 "$plist"
    shortcuts sign --mode people-who-know-me --input "$plist" --output "$signed"
    rm -f "$plist"
    echo "Importando: $name"
    open "$signed"
    # O app Atalhos abre uma confirmação por arquivo; abrir tudo de uma vez
    # faz algumas se perderem.
    sleep 2
}

create_shortcut "Revisar com Holly" "revisar"
create_shortcut "Reescrever com Holly" "reescrever"
create_shortcut "Formalizar com Holly" "formalizar"
create_shortcut "Simplificar com Holly" "simplificar"
create_shortcut "Resumir com Holly" "resumir"

echo
echo "Confirme cada atalho em \"Adicionar Atalho\" no app Atalhos."
echo "Depois, selecione um texto e diga, por exemplo: \"E aí Siri, revisar com Holly\"."
