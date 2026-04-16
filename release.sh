#!/bin/bash
# release.sh — prefPane aus xcarchive extrahieren, Developer-ID signieren,
#              ZIP erstellen, notarisieren und für Verteilung vorbereiten.
#
# Voraussetzung: Archiv wurde in Xcode mit Product → Archive erstellt.
#
# Einmalige Vorbereitungen:
#   1. Developer ID Application Zertifikat in Keychain vorhanden
#   2. Notarization Keychain-Profil einmalig anlegen:
#        xcrun notarytool store-credentials "DNSOMaticRelease" \
#          --apple-id "deine@apple.id" \
#          --team-id "XXXXXXXXXX" \
#          --password "xxxx-xxxx-xxxx-xxxx"   # App-Specific Password
#   3. Umgebungsvariablen setzen (z.B. in ~/.zshrc):
#        export DOM_SIGN_ID="<SHA1 des Developer ID Application Zertifikats>"
#        export DOM_GITHUB_REPO="user/repo"    # optional, für Abschluss-Hinweis
#        export DOM_NOTARY_PROFILE="DNSOMaticRelease"
#
# Aufruf:
#   ./release.sh <xcarchive-Pfad> <version> <build>
#
# Beispiel:
#   ./release.sh ~/Library/Developer/Xcode/Archives/2026-04-14/DNS-O-MATIC\ Updater.xcarchive 1.0 1

set -euo pipefail

# ── Konfiguration ─────────────────────────────────────────────────────────────
SIGN_ID="${DOM_SIGN_ID:?DOM_SIGN_ID nicht gesetzt (Developer ID Application SHA1)}"
NOTARY_PROFILE="${DOM_NOTARY_PROFILE:-DNSOMaticRelease}"
GITHUB_REPO="${DOM_GITHUB_REPO:-}"
ENTITLEMENTS="$(dirname "$0")/DNS-O-MATIC Updater/DNS_O_MATIC_Updater.entitlements"
# ──────────────────────────────────────────────────────────────────────────────

# ── Argumente prüfen ──────────────────────────────────────────────────────────
if [ $# -ne 3 ]; then
    echo "Aufruf: $0 <xcarchive-Pfad> <version> <build>"
    echo "Beispiel: $0 ~/Library/Developer/Xcode/Archives/.../DNS-O-MATIC\\ Updater.xcarchive 1.0 1"
    exit 1
fi

XCARCHIVE="$1"; VERSION="$2"; BUILD="$3"
XCARCHIVE="${XCARCHIVE/#\~/$HOME}"

[ -d "$XCARCHIVE" ] || { echo "ERROR: xcarchive nicht gefunden: $XCARCHIVE"; exit 1; }

ZIP_BASENAME="DNS-O-MATIC-Updater-${VERSION}.zip"
ZIP="$HOME/Downloads/${ZIP_BASENAME}"
WORK_DIR="/tmp/domrelease_$$"
trap 'rm -rf "$WORK_DIR"' EXIT

# ── prefPane aus xcarchive suchen ─────────────────────────────────────────────
echo "=== prefPane aus xcarchive extrahieren ==="
PREFPANE_SRC=$(find "$XCARCHIVE/Products" -name "DNS-O-MATIC Updater.prefPane" -maxdepth 6 | head -1)
[ -n "$PREFPANE_SRC" ] || { echo "ERROR: DNS-O-MATIC Updater.prefPane nicht im xcarchive gefunden."; exit 1; }

mkdir -p "$WORK_DIR"
PREFPANE="$WORK_DIR/DNS-O-MATIC Updater.prefPane"
ditto "$PREFPANE_SRC" "$PREFPANE"
echo "Gefunden:  $PREFPANE_SRC"
echo "Kopiert nach: $PREFPANE"

# ── Signieren mit Developer ID Application ────────────────────────────────────
echo "=== Signieren mit Developer ID Application ==="

# Zuerst eventuell enthaltene Bundles tief signieren, dann das prefPane selbst.
# Für ein schlankes prefPane ohne eingebettete Frameworks reicht --deep.
# Sollte das prefPane eigene Frameworks enthalten, diese zuerst einzeln signieren.

# Entitlements prüfen
[ -f "$ENTITLEMENTS" ] || { echo "ERROR: Entitlements nicht gefunden: $ENTITLEMENTS"; exit 1; }
echo "  Entitlements: $ENTITLEMENTS"

# Frameworks signieren (falls vorhanden)
FW_DIR="$PREFPANE/Contents/Frameworks"
if [ -d "$FW_DIR" ]; then
    echo "  Signing: eingebettete Frameworks"
    for fw in "$FW_DIR"/*.framework; do
        [ -d "$fw" ] || continue
        echo "    $(basename "$fw")"
        codesign --force --sign "$SIGN_ID" --options runtime --timestamp "$fw"
    done
fi

# Plugins/XPC signieren (falls vorhanden)
for plug_dir in "$PREFPANE/Contents/PlugIns" "$PREFPANE/Contents/XPCServices"; do
    if [ -d "$plug_dir" ]; then
        echo "  Signing: $(basename "$plug_dir")"
        for bundle in "$plug_dir"/*; do
            [ -d "$bundle" ] || continue
            echo "    $(basename "$bundle")"
            codesign --force --sign "$SIGN_ID" --options runtime --timestamp "$bundle"
        done
    fi
done

# prefPane signieren (mit Entitlements)
echo "  Signing: DNS-O-MATIC Updater.prefPane"
codesign --force --sign "$SIGN_ID" --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --deep "$PREFPANE"

echo "Signatur verifizieren..."
codesign --verify --deep --strict "$PREFPANE" && echo "Signatur OK."
codesign -dvv "$PREFPANE" 2>&1 | grep "^Authority="

# ── ZIP erstellen ─────────────────────────────────────────────────────────────
echo "=== ZIP erstellen ==="
rm -f "$ZIP"
ditto -c -k --keepParent "$PREFPANE" "$ZIP"
echo "ZIP erstellt: $ZIP"

# ── Notarisieren ──────────────────────────────────────────────────────────────
echo "=== ZIP notarisieren ==="
NOTARY_OUT=$(xcrun notarytool submit "$ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait 2>&1) || true
echo "$NOTARY_OUT"

NOTARY_ID=$(echo "$NOTARY_OUT" | grep -o 'id: [0-9a-f-]*' | head -1 | awk '{print $2}')

if ! echo "$NOTARY_OUT" | grep -q "status: Accepted"; then
    echo "ERROR: Notarisierung fehlgeschlagen!"
    if [ -n "$NOTARY_ID" ]; then
        echo "=== Notarytool Log ==="
        xcrun notarytool log "$NOTARY_ID" --keychain-profile "$NOTARY_PROFILE" || true
    fi
    exit 1
fi
echo "Notarisierung abgeschlossen."

# ── Stapling ──────────────────────────────────────────────────────────────────
echo "=== Notarisierungsticket anheften (staple) ==="
xcrun stapler staple "$PREFPANE"
echo "Stapling OK."

# ── ZIP neu erstellen (mit gestapeltem Ticket) ────────────────────────────────
echo "=== ZIP mit gestapeltem prefPane neu erstellen ==="
rm -f "$ZIP"
ditto -c -k --keepParent "$PREFPANE" "$ZIP"
echo "ZIP erstellt: $ZIP"

# ── Dateigröße ────────────────────────────────────────────────────────────────
ZIP_SIZE=$(wc -c < "$ZIP" | tr -d ' ')
echo "ZIP: ${ZIP_SIZE} Bytes"

# ── Abschluss ─────────────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo " Fertig! Version ${VERSION} (Build ${BUILD})"
echo "========================================"
echo " Erstellt: $ZIP"
if [ -n "$GITHUB_REPO" ]; then
    echo ""
    echo " Naechste Schritte:"
    echo "   1. GitHub Release erstellen:"
    echo "      https://github.com/${GITHUB_REPO}/releases/new"
    echo "      Tag: v${VERSION}"
    echo "      Asset: ${ZIP_BASENAME}  (${ZIP_SIZE} Bytes)"
    echo "   2. ZIP hochladen und Release veröffentlichen."
fi
echo ""
echo " Installation beim Benutzer:"
echo "   ZIP entpacken → Doppelklick auf"
echo "   'DNS-O-MATIC Updater.prefPane'"
echo "========================================"
