#!/bin/bash
# Monta o Pynkaro.app a partir do build do Swift Package.
set -e
cd "$(dirname "$0")"

echo "🔨 Compilando (release)..."
swift build -c release

APP="Pynkaro.app"
BIN=".build/release/Pynkaro"

echo "📦 Montando $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Pynkaro"
cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Recursos do avatar (os que existirem).
for f in avatar.png avatar_mid.png avatar_open.png avatar_round.png avatar_fv.png avatar.riv; do
    [ -f "$f" ] && cp "$f" "$APP/Contents/Resources/"
done

# Servidor Kokoro local (usado pelo LaunchAgent no modo Mac local).
[ -f tools/kokoro_local_server.py ] && cp tools/kokoro_local_server.py "$APP/Contents/Resources/"

# Frameworks dinâmicos (RiveRuntime). O SPM extrai o xcframework em
# .build/artifacts/ — procura a fatia do macOS em todo o .build.
FRAMEWORK=$(find .build -type d -name "RiveRuntime.framework" -path "*macos*" -print -quit 2>/dev/null || true)
if [ -z "$FRAMEWORK" ]; then
    FRAMEWORK=$(find .build -type d -name "RiveRuntime.framework" -print -quit 2>/dev/null || true)
fi
if [ -n "$FRAMEWORK" ]; then
    echo "🧩 Incluindo $(basename "$FRAMEWORK") ($FRAMEWORK)"
    mkdir -p "$APP/Contents/Frameworks"
    cp -R "$FRAMEWORK" "$APP/Contents/Frameworks/"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Pynkaro" 2>/dev/null || true
    codesign --force --sign - "$APP/Contents/Frameworks/RiveRuntime.framework" 2>/dev/null || true
else
    echo "ℹ️ RiveRuntime.framework não encontrado no .build (ok se o link for estático)."
fi

# Assinatura ad-hoc (suficiente para uso local; para distribuir a outros
# Macs é preciso assinar com Developer ID e notarizar — ver README).
codesign --force --deep --sign - "$APP"

# DMG de distribuição (arrastar para Applications).
DMG="Pynkaro.dmg"
rm -f "$DMG"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Pynkaro" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo ""
echo "✅ $APP criado."
echo "💿 $DMG criado — o usuário abre e arrasta o Pynkaro para Applications."
echo "   Na primeira execução o app pede as chaves de API (salvas no Keychain)."
