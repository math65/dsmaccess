#!/bin/bash
#
# build.sh — construit, signe, notarise et publie une release de DSM Access.
#
# Usage :
#   ./build.sh              Archive + signe Developer ID + exporte + zippe (LOCAL, rien d'envoyé).
#   ./build.sh --notarize   + notarise, staple, régénère docs/appcast.xml signé EdDSA.
#   ./build.sh --release     Tout ce qui précède + release GitHub + push de l'appcast (IRRÉVERSIBLE).
#
# Prérequis (tous déjà en place au 2026-07-10) :
#   - Identité « Developer ID Application: Mathieu Martin (633EG76YX5) » dans le trousseau.
#   - Clé privée EdDSA Sparkle dans le trousseau (clé publique = SUPublicEDKey de Info.plist).
#   - Profil notarytool $NOTARY_PROFILE enregistré (vérif : xcrun notarytool history --keychain-profile "$NOTARY_PROFILE").
#   - GitHub Pages activé (source main /docs) sert https://math65.github.io/dsmaccess/appcast.xml.
#
# Chaque release publique : bumper MARKETING_VERSION + CURRENT_PROJECT_VERSION dans le
# projet AVANT de lancer (Sparkle compare par numéro de build ; le tag GitHub est vVERSION).

set -euo pipefail

SCHEME="dsmaccess"
PROJECT="dsmaccess.xcodeproj"
CONFIGURATION="Release"
APP_NAME="dsmaccess"
REPO="math65/dsmaccess"
SIGN_IDENTITY="Developer ID Application: Mathieu Martin (633EG76YX5)"
TEAM_ID="633EG76YX5"
# Les profils notarytool ne sont PAS liés à une app : on réutilise celui de ttaccessible
# (identifiant Apple partagé). Voir mémoire sparkle-distribution.
NOTARY_PROFILE="ttaccessible-notary"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DERIVED_DATA="/tmp/${APP_NAME}-build"       # chemin fixe → outils Sparkle localisables
OUTPUT_DIR="$SCRIPT_DIR/BuildArtifacts"
DOCS_DIR="$SCRIPT_DIR/docs"
ARCHIVE_PATH="$DERIVED_DATA/${APP_NAME}.xcarchive"
EXPORT_DIR="$DERIVED_DATA/export"
APP_PATH="$EXPORT_DIR/${APP_NAME}.app"

NOTARIZE=0
RELEASE=0
for arg in "$@"; do
    case "$arg" in
        --notarize) NOTARIZE=1 ;;
        --release)  NOTARIZE=1; RELEASE=1 ;;
        *) echo "Argument inconnu : $arg" >&2; exit 2 ;;
    esac
done

echo "==> Archive Release (signature Developer ID manuelle)..."
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"
xcodebuild -project "$SCRIPT_DIR/$PROJECT" -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$DERIVED_DATA" \
    archive \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID"

echo "==> Export developer-id..."
EXPORT_PLIST="$DERIVED_DATA/ExportOptions.plist"
cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>${TEAM_ID}</string>
    <key>signingStyle</key><string>manual</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_PLIST"

echo "==> Vérification de signature (deep, strict)..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

VERSION=$(defaults read "$APP_PATH/Contents/Info" CFBundleShortVersionString)
BUILD=$(defaults read "$APP_PATH/Contents/Info" CFBundleVersion)

# Version « …-beta… » → pré-release : entrée d'appcast taguée sur le canal `beta` (seuls les
# builds beta la voient) et release GitHub marquée prerelease. La 1.0 stable reste intacte.
CHANNEL_ARGS=()
PRERELEASE_ARGS=()
if [[ "$VERSION" == *beta* ]]; then
    CHANNEL_ARGS=(--channel beta)
    PRERELEASE_ARGS=(--prerelease)
    echo "==> Version beta détectée ($VERSION) → canal Sparkle « beta » + release prerelease."
fi

mkdir -p "$OUTPUT_DIR"
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
ZIP_BASENAME="${ZIP_NAME%.zip}"
ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"

echo "==> Zip $ZIP_NAME (version $VERSION build $BUILD)..."
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

if [[ $NOTARIZE -eq 1 ]]; then
    echo "==> Notarisation (notarytool, peut prendre quelques minutes)..."
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

    echo "==> Staple du ticket..."
    xcrun stapler staple "$APP_PATH"

    echo "==> Contrôle Gatekeeper..."
    spctl --assess --type execute --verbose=2 "$APP_PATH" || true

    echo "==> Re-zip avec ticket agrafé..."
    rm -f "$ZIP_PATH"
    ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

    echo "==> Génération de l'appcast Sparkle signé EdDSA..."
    SPARKLE_BIN="$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin"
    if [[ ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
        echo "✗ Outils Sparkle introuvables à $SPARKLE_BIN" >&2
        exit 1
    fi
    STAGING="$DERIVED_DATA/appcast-staging"
    rm -rf "$STAGING"; mkdir -p "$STAGING"
    cp "$ZIP_PATH" "$STAGING/"
    # Préserver les entrées existantes (versions précédentes) dans le feed.
    [[ -f "$DOCS_DIR/appcast.xml" ]] && cp "$DOCS_DIR/appcast.xml" "$STAGING/appcast.xml"
    mkdir -p "$DOCS_DIR"

    # Notes de version localisées → HTML (thème clair/sombre) pour la popup Sparkle.
    # generate_appcast détecte les sidecars <base>.html / <base>.fr.html et émet les
    # <sparkle:releaseNotesLink> (Sparkle montre à chacun sa langue, repli sur l'anglais).
    # Le .md racine sert aussi de corps à la release GitHub (--notes-file) plus bas.
    if [[ -f "$SCRIPT_DIR/RELEASE_NOTES.md" ]]; then
        "$SCRIPT_DIR/scripts/render-release-notes.sh" \
            "$SCRIPT_DIR/RELEASE_NOTES.md" "$DOCS_DIR/${ZIP_BASENAME}.html" "en"
        cp "$DOCS_DIR/${ZIP_BASENAME}.html" "$STAGING/${ZIP_BASENAME}.html"
    fi
    if [[ -f "$SCRIPT_DIR/RELEASE_NOTES.fr.md" ]]; then
        "$SCRIPT_DIR/scripts/render-release-notes.sh" \
            "$SCRIPT_DIR/RELEASE_NOTES.fr.md" "$DOCS_DIR/${ZIP_BASENAME}.fr.html" "fr"
        cp "$DOCS_DIR/${ZIP_BASENAME}.fr.html" "$STAGING/${ZIP_BASENAME}.fr.html"
    fi

    "$SPARKLE_BIN/generate_appcast" \
        "$STAGING" \
        ${CHANNEL_ARGS[@]+"${CHANNEL_ARGS[@]}"} \
        --download-url-prefix "https://github.com/${REPO}/releases/download/v${VERSION}/" \
        --link "https://github.com/${REPO}/releases/tag/v${VERSION}" \
        -o "$DOCS_DIR/appcast.xml"
    rm -rf "$STAGING"
    echo "✓ docs/appcast.xml généré"
fi

echo ""
echo "✓ $ZIP_PATH"

if [[ $RELEASE -eq 1 ]]; then
    command -v gh >/dev/null || { echo "⚠ gh CLI absent — release GitHub sautée"; exit 0; }
    NOTES_FILE="$SCRIPT_DIR/RELEASE_NOTES.md"
    [[ -f "$NOTES_FILE" ]] || { echo "✗ RELEASE_NOTES.md introuvable — abandon."; exit 1; }
    TAG="v${VERSION}"

    echo "==> Release GitHub $TAG..."
    if gh release view "$TAG" -R "$REPO" &>/dev/null; then
        echo "⚠ $TAG existe déjà — mise à jour de l'asset."
        gh release upload "$TAG" "$ZIP_PATH" --clobber -R "$REPO"
    else
        gh release create "$TAG" "$ZIP_PATH" \
            --title "DSM Access ${VERSION}" \
            --notes-file "$NOTES_FILE" \
            ${PRERELEASE_ARGS[@]+"${PRERELEASE_ARGS[@]}"} \
            -R "$REPO"
    fi
    echo "✓ https://github.com/${REPO}/releases/tag/$TAG"

    # Pousser l'appcast (servi par Pages) — uniquement depuis main.
    CURRENT_BRANCH=$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD)
    if [[ "$CURRENT_BRANCH" == "main" && -n "$(git -C "$SCRIPT_DIR" status --porcelain -- docs/)" ]]; then
        git -C "$SCRIPT_DIR" add docs/appcast.xml "docs/${ZIP_BASENAME}.html" "docs/${ZIP_BASENAME}.fr.html" 2>/dev/null
        git -C "$SCRIPT_DIR" commit -m "Update appcast and release notes for v${VERSION}"
        git -C "$SCRIPT_DIR" push origin main
        echo "✓ appcast + notes poussés sur main"
    else
        echo "⚠ Appcast non poussé (branche != main ou aucun changement) — pousse-le à la main si besoin."
    fi
fi
