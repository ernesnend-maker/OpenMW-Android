#!/usr/bin/env bash
# Mete el motor compilado (libopenmw.so + archivos de fisica) dentro del APK oficial de Andiweli,
# le cambia el nombre de paquete (se instala como app APARTE: "OpenMW Fisica") y lo firma.
#
# Uso: reempaquetar.sh <apk_base> <dir_jniLibs_arm64> <dir_assets_libopenmw> <salida.apk>
set -euo pipefail

BASE_APK="$1"
JNI_DIR="$2"
ASSETS_DIR="$3"
OUT_APK="$4"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEW_PKG="com.ast.openmw.fisica"
APP_LABEL="OpenMW Física"
WORK="$(mktemp -d)"

APKTOOL_JAR="${APKTOOL_JAR:-$WORK/apktool.jar}"
if [ ! -f "$APKTOOL_JAR" ]; then
    curl -sSL -o "$APKTOOL_JAR" https://github.com/iBotPeaches/Apktool/releases/download/v2.10.0/apktool_2.10.0.jar
fi

BT="$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -n1)"
echo "build-tools: $BT"

# -s: no tocar el codigo (dex); solo recursos, manifiesto y archivos
java -jar "$APKTOOL_JAR" d -f -s -o "$WORK/apk" "$BASE_APK"

echo "==> Motor nuevo"
cp -v "$JNI_DIR/libopenmw.so" "$WORK/apk/lib/arm64-v8a/libopenmw.so"

echo "==> Archivos de datos que cambian con la fisica"
# Solo lo que el parche de fisica cambia; el resto (shaders retocados por Andiweli) se queda como esta.
cp -v "$ASSETS_DIR/openmw/defaults.bin" "$WORK/apk/assets/libopenmw/openmw/defaults.bin"
for rel in vfs/modernphysics/impactsounds.yaml vfs/l10n/OMWEngine/en.yaml; do
    if [ -f "$ASSETS_DIR/resources/$rel" ]; then
        mkdir -p "$(dirname "$WORK/apk/assets/libopenmw/resources/$rel")"
        cp -v "$ASSETS_DIR/resources/$rel" "$WORK/apk/assets/libopenmw/resources/$rel"
    else
        echo "AVISO: no existe resources/$rel en la compilacion" >&2
    fi
done

echo "==> Nombre de paquete y de app"
# apktool cambia el paquete del manifiesto (las clases siguen en su sitio)
python3 - "$WORK/apk/apktool.yml" "$NEW_PKG" <<'PY'
import sys, re
p, pkg = sys.argv[1], sys.argv[2]
s = open(p, encoding='utf-8').read()
s = re.sub(r'renameManifestPackage:.*', 'renameManifestPackage: ' + pkg, s)
if 'renameManifestPackage' not in s:
    s += '\nrenameManifestPackage: ' + pkg + '\n'
open(p, 'w', encoding='utf-8').write(s)
PY
python3 - "$WORK/apk/res" "$APP_LABEL" <<'PY'
import sys, os, re
res, label = sys.argv[1], sys.argv[2]
for d in os.listdir(res):
    f = os.path.join(res, d, 'strings.xml')
    if d.startswith('values') and os.path.isfile(f):
        s = open(f, encoding='utf-8').read()
        s2 = re.sub(r'(<string name="app_name">)[^<]*(</string>)', r'\g<1>' + label + r'\g<2>', s)
        if s2 != s:
            open(f, 'w', encoding='utf-8').write(s2)
            print('app_name ->', label, 'en', f)
PY
# Autoridades de proveedores que lleven el paquete viejo (si las hay) pasan al nuevo
sed -i "s/android:authorities=\"com\.ast\.openmw\./android:authorities=\"$NEW_PKG./g" "$WORK/apk/AndroidManifest.xml"

java -jar "$APKTOOL_JAR" b -o "$WORK/sin_firmar.apk" "$WORK/apk"

echo "==> Alinear y firmar"
"$BT/zipalign" -f -p 4 "$WORK/sin_firmar.apk" "$WORK/alineado.apk"
"$BT/apksigner" sign --ks "$HERE/fisica.p12" --ks-type PKCS12 --ks-pass pass:fisica-openmw \
    --key-pass pass:fisica-openmw --ks-key-alias fisica --out "$OUT_APK" "$WORK/alineado.apk"
"$BT/apksigner" verify --print-certs "$OUT_APK" | head -n 3
"$BT/aapt2" dump badging "$OUT_APK" | grep -E "^package|application-label:" || true
echo "==> Listo: $OUT_APK"
