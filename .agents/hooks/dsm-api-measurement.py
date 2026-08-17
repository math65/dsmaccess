#!/usr/bin/env python3
"""Hook PostToolUse : rappelle qu'un contrat DSM se mesure, jamais ne se devine.

Claude Code envoie sur l'entrée standard le JSON de l'appel d'outil. Le rappel ne
part que si l'édition touche la pile DSM *et* introduit de la surface d'API : un
nom `SYNO.…`, un appel de transport, un `method:`, ou des clés de décodage en
snake_case. Un rappel posé à chaque édition serait ignoré au bout de trois.

Le hook ne bloque jamais. Il rappelle ce qui doit être prouvé ; le modèle décide.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WATCHED = ("dsmaccess/Networking/", "dsmaccess/Models/")

API_NAME = re.compile(r"SYNO\.[A-Za-z0-9._]+")
SURFACE = (
    re.compile(r"\bDSMAPI\("),
    re.compile(r"transport\.(read|perform|value|response|upload)\("),
    re.compile(r'\bmethod:\s*"'),
    # Une clé de décodage en snake_case est une affirmation sur la réponse du NAS,
    # au même titre qu'un paramètre de requête.
    re.compile(r'=\s*"[a-z0-9]+(_[a-z0-9]+)+"'),
)

REMINDER = (
    "Ce fichier parle à DSM. Le contrat écrit ici est-il MESURÉ, ou déduit ?\n"
    "Une mesure, c'est l'opération exécutée pour de vrai dans l'interface DSM, par "
    "son vrai parcours, trafic intercepté, tous les champs relevés — requête ET "
    "réponse. Le JS du webman, SYNO.API.Info, la doc Synology, une lib "
    "communautaire et le code déjà présent disent où pointer la mesure : aucun ne "
    "la remplace, et aucun n'autorise une ligne de code à lui seul.\n"
    "Une requête assemblée à la main puis affinée sur les codes d'erreur n'est pas "
    "une mesure : un refus ne dit jamais quel paramètre manquait, et un appel qui "
    "passe par hasard enseigne un faux contrat aussi bien qu'un vrai. Un test "
    "unitaire vert ne prouve rien non plus : il vérifie la forme que j'ai décidé "
    "de donner à la requête.\n"
    "Si la mesure est impossible (paquet absent, mutation trop risquée), le dire à "
    "Mathieu et livrer le plus petit périmètre vérifiable plutôt qu'une supposition."
)


def edited_text(payload: dict) -> str:
    tool_input = payload.get("tool_input") or {}
    parts = [
        tool_input.get("content"),
        tool_input.get("new_string"),
    ]
    edits = tool_input.get("edits")
    if isinstance(edits, list):
        parts.extend(edit.get("new_string") for edit in edits if isinstance(edit, dict))
    return "\n".join(part for part in parts if isinstance(part, str))


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0

    tool_input = payload.get("tool_input") or {}
    tool_response = payload.get("tool_response") or {}
    raw_path = tool_response.get("filePath") or tool_input.get("file_path")
    if not raw_path:
        return 0

    path = Path(raw_path)
    try:
        relative = path.resolve().relative_to(ROOT)
    except ValueError:
        return 0
    if path.suffix != ".swift" or not str(relative).startswith(WATCHED):
        return 0

    text = edited_text(payload)
    if not text or not any(pattern.search(text) for pattern in SURFACE):
        return 0

    context = f"{relative} — mesure du contrat DSM :\n{REMINDER}"
    touched = sorted(set(API_NAME.findall(text)))
    if touched:
        context += "\nAPI touchées par cette édition : " + ", ".join(touched) + "."

    print(json.dumps({
        "suppressOutput": True,
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": context,
        },
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
