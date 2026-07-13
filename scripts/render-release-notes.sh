#!/bin/bash
#
# Renders a Markdown release-notes file to HTML using pandoc and the
# release-notes-template.html template (light + dark mode CSS).
#
# Usage: ./scripts/render-release-notes.sh <input.md> <output.html> [lang]
#
# [lang] is the BCP 47 language code written to the <html lang="…"> attribute
# so VoiceOver reads the notes in the right voice. Defaults to "en".

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "Usage: $0 <input.md> <output.html> [lang]" >&2
    exit 2
fi

SRC="$1"
DST="$2"
LANG_CODE="${3:-en}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SCRIPT_DIR/release-notes-template.html"

if ! command -v pandoc &> /dev/null; then
    echo "✗ pandoc not found. Install with: brew install pandoc" >&2
    exit 1
fi

if [[ ! -f "$SRC" ]]; then
    echo "✗ Source file not found: $SRC" >&2
    exit 1
fi

if [[ ! -f "$TEMPLATE" ]]; then
    echo "✗ Template not found: $TEMPLATE" >&2
    exit 1
fi

TITLE="$(basename "${DST%.html}")"

pandoc \
    --from=gfm \
    --to=html5 \
    --standalone \
    --template="$TEMPLATE" \
    --metadata title="$TITLE" \
    --metadata lang="$LANG_CODE" \
    --output "$DST" \
    "$SRC"

echo "✓ Rendered $SRC → $DST"
