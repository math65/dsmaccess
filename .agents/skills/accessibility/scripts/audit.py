#!/usr/bin/env python3
"""Audit d'accessibilité statique de DSM Access.

Cherche les défauts que la compilation ne voit pas et qu'un utilisateur VoiceOver
découvre à l'usage : une zone sans nom, une annonce jamais traduite, un libellé qui
fait répéter le lecteur d'écran, une couleur système illisible.

Usage, depuis la racine du dépôt :
    python3 .agents/skills/accessibility/scripts/audit.py
    python3 .agents/skills/accessibility/scripts/audit.py --only regions,announces
    python3 .agents/skills/accessibility/scripts/audit.py --files dsmaccess/Views/LoginView.swift
    python3 .agents/skills/accessibility/scripts/audit.py --diff        # fichiers modifiés seulement

Sortie : une ligne « fichier:ligne  [règle]  message » par constat, puis un décompte.
Code de sortie 1 s'il reste des constats, 0 sinon.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

CATALOG = Path("dsmaccess/Localizable.xcstrings")
VIEWS = Path("dsmaccess/Views")
SOURCES = Path("dsmaccess")

# Les conteneurs défilants que VoiceOver annonce comme « zone de défilement ».
SCROLLING = re.compile(r"\.formStyle\(|^\s*ScrollView\b|^\s*List\s*[({]")
# Fenêtre de lignes dans laquelle on accepte de trouver le nom du conteneur.
NEARBY = 4


@dataclass
class Finding:
    path: str
    line: int
    rule: str
    message: str

    def __str__(self) -> str:
        return f"{self.path}:{self.line}  [{self.rule}]  {self.message}"


def swift_files(paths: list[Path]) -> list[Path]:
    files: list[Path] = []
    for base in paths:
        if base.is_file() and base.suffix == ".swift":
            files.append(base)
        elif base.is_dir():
            files.extend(sorted(base.rglob("*.swift")))
    return files


def changed_files() -> list[Path]:
    out = subprocess.run(
        ["git", "diff", "--name-only", "HEAD"],
        capture_output=True, text=True, check=False,
    ).stdout.split()
    untracked = subprocess.run(
        ["git", "ls-files", "--others", "--exclude-standard"],
        capture_output=True, text=True, check=False,
    ).stdout.split()
    return [Path(p) for p in out + untracked if p.endswith(".swift") and Path(p).exists()]


def load_catalog() -> dict[str, dict[str, str]]:
    """clé -> {langue: valeur}. Vide si le catalogue est introuvable."""
    if not CATALOG.exists():
        return {}
    data = json.loads(CATALOG.read_text(encoding="utf-8"))
    out: dict[str, dict[str, str]] = {}
    for key, entry in data.get("strings", {}).items():
        values = {}
        for lang, block in (entry.get("localizations") or {}).items():
            unit = block.get("stringUnit") or {}
            if "value" in unit:
                values[lang] = unit["value"]
        if values:
            out[key] = values
    return out


# --- Règles ----------------------------------------------------------------


def _modifier_window(lines: list[str], i: int) -> str:
    """Les lignes où peut se trouver le nom du conteneur ouvert en ligne `i`.

    Un `.formStyle(` est un modificateur : le nom se pose juste après. Mais un `List` ou un
    `ScrollView` ouvre un bloc, et ses modificateurs ne viennent qu'à sa fermeture, parfois
    cent lignes plus bas. Lire les seules lignes suivantes y signalait douze zones **déjà
    nommées** (02/08/2026) — un audit qui crie au loup ne sert à rien.
    """
    if ".formStyle(" in lines[i]:
        return "\n".join(lines[i:i + NEARBY])
    indent = len(lines[i]) - len(lines[i].lstrip())
    for j in range(i + 1, len(lines)):
        stripped = lines[j].strip()
        if not stripped:
            continue
        if len(lines[j]) - len(lines[j].lstrip()) <= indent and stripped[0] in "}.":
            return "\n".join(lines[j:j + NEARBY + 4])
    return "\n".join(lines[i:i + NEARBY])


def rule_regions(files: list[Path], _catalog) -> list[Finding]:
    """Un conteneur défilant sans nom s'annonce « zone de défilement » et rien d'autre."""
    findings = []
    for path in files:
        lines = path.read_text(encoding="utf-8").split("\n")
        for i, line in enumerate(lines):
            if not SCROLLING.search(line):
                continue
            window = _modifier_window(lines, i)
            if "accessibilityLabel" in window or "accessibilityHidden" in window:
                continue
            kind = "Form" if ".formStyle(" in line else ("List" if "List" in line else "ScrollView")
            findings.append(Finding(
                str(path), i + 1, "regions",
                f"{kind} sans accessibilityLabel : VoiceOver annonce une zone anonyme",
            ))
    return findings


def rule_tables(files: list[Path], _catalog) -> list[Finding]:
    """Un Table sans nom est signalé sans description par l'audit XCUITest."""
    findings = []
    for path in files:
        lines = path.read_text(encoding="utf-8").split("\n")
        for i, line in enumerate(lines):
            if not re.search(r"^\s*Table\s*[({]", line):
                continue
            # Le nom peut arriver loin après, une fois les colonnes déclarées.
            window = "\n".join(lines[i:i + 60])
            if "accessibilityLabel" not in window:
                findings.append(Finding(
                    str(path), i + 1, "tables",
                    "Table sans accessibilityLabel : le tableau n'est pas nommé",
                ))
    return findings


def rule_announces(files: list[Path], _catalog) -> list[Finding]:
    """Une annonce écrite en dur compile, part en production, et n'est jamais traduite."""
    findings = []
    for path in files:
        for i, line in enumerate(path.read_text(encoding="utf-8").split("\n")):
            if re.search(r'VoiceOver\.announce\(\s*"', line):
                findings.append(Finding(
                    str(path), i + 1, "announces",
                    "VoiceOver.announce avec un littéral : passer par String(localized:)",
                ))
    return findings


def rule_combine(files: list[Path], _catalog) -> list[Finding]:
    """Combiner un conteneur enterre les boutons et les valeurs qu'il contient."""
    findings = []
    for path in files:
        for i, line in enumerate(path.read_text(encoding="utf-8").split("\n")):
            if "accessibilityElement(children: .combine)" in line:
                findings.append(Finding(
                    str(path), i + 1, "combine",
                    "children: .combine masque les éléments internes ; vérifier qu'aucun "
                    "contrôle ni valeur utile n'y est enfermé",
                ))
    return findings


def rule_contrast(files: list[Path], _catalog) -> list[Finding]:
    """Les couleurs système échouent au seuil AA aux tailles utilisées ici."""
    findings = []
    pattern = re.compile(r"foregroundStyle\(\s*\.(secondary|green|orange|red|yellow)\b")
    for path in files:
        if VIEWS not in path.parents and path.parent != VIEWS:
            continue
        for i, line in enumerate(path.read_text(encoding="utf-8").split("\n")):
            match = pattern.search(line)
            if match:
                name = match.group(1)
                readable = "readableSecondary" if name == "secondary" else f"readable{name.capitalize()}"
                findings.append(Finding(
                    str(path), i + 1, "contrast",
                    f".{name} sous le seuil AA : utiliser .{readable} (ReadableStyles.swift)",
                ))
    return findings


def used_keys(files: list[Path], call: str) -> dict[str, list[tuple[str, int]]]:
    """Clés littérales passées à un appel donné, avec leurs emplacements."""
    pattern = re.compile(re.escape(call) + r'\(\s*"([^"]+)"')
    found: dict[str, list[tuple[str, int]]] = {}
    for path in files:
        for i, line in enumerate(path.read_text(encoding="utf-8").split("\n")):
            for key in pattern.findall(line):
                found.setdefault(key, []).append((str(path), i + 1))
    return found


def rule_hints(files: list[Path], catalog) -> list[Finding]:
    """Un hint est une phrase : c'est le point final qui donne son intonation à VoiceOver.

    À ne pas confondre avec `.help`, qui est une infobulle et garde la forme courte.
    """
    findings = []
    for key, places in used_keys(files, ".accessibilityHint").items():
        values = catalog.get(key)
        if not values:
            continue
        for lang, value in sorted(values.items()):
            if value and not value.rstrip().endswith((".", "!", "?", "…")):
                path, line = places[0]
                findings.append(Finding(
                    path, line, "hints",
                    f'{key} ({lang}) ne finit pas par un point : « {value} »',
                ))
    return findings


def rule_labels(files: list[Path], catalog) -> list[Finding]:
    """Un libellé nomme la chose, sans point final et sans redire le type du contrôle.

    Le trait d'accessibilité dit déjà « bouton » : le répéter fait entendre
    « Supprimer bouton, bouton ».
    """
    findings = []
    types = re.compile(
        r"\b(bouton|boutons|button|buttons|case à cocher|checkbox|menu déroulant|"
        r"pop-?up button|champ de texte|text field|curseur|slider|onglet|tab)\b",
        re.IGNORECASE,
    )
    # Certaines clés servent de libellé à un élément mais portent une phrase : une annonce,
    # un message d'erreur, une description. La règle du libellé court ne les concerne pas.
    prose = (".announcement", ".message", ".description", ".error", ".summary", "_for")
    for key, places in used_keys(files, ".accessibilityLabel").items():
        values = catalog.get(key)
        if not values or key.endswith(prose) or any(p in key for p in prose):
            continue
        path, line = places[0]
        for lang, value in sorted(values.items()):
            if not value:
                continue
            if value.rstrip().endswith("."):
                findings.append(Finding(
                    path, line, "labels",
                    f'{key} ({lang}) : un libellé ne prend pas de point final — « {value} »',
                ))
            match = types.search(value)
            if match:
                findings.append(Finding(
                    path, line, "labels",
                    f'{key} ({lang}) nomme le type de contrôle « {match.group(0)} » : '
                    "le trait le dit déjà",
                ))
            first = value.lstrip()[:1]
            if first and first.isalpha() and not first.isupper():
                findings.append(Finding(
                    path, line, "labels",
                    f'{key} ({lang}) commence en minuscule : « {value} »',
                ))
    return findings


def looks_like_prose(value: str) -> bool:
    """Distingue un mot destiné à l'utilisateur d'une clé ou d'un nom de symbole.

    Une clé de catalogue (`common.button.enable`) et un symbole SF (`video.fill`)
    portent un point et restent en minuscules ; une phrase affichée commence par une
    capitale ou contient une espace.
    """
    if "." in value or "_" in value:
        return False
    stripped = value.strip()
    if not stripped or not re.search(r"[A-Za-zÀ-ÿ]", stripped):
        return False
    return stripped[0].isupper() or " " in stripped


def rule_untranslated(files: list[Path], _catalog) -> list[Finding]:
    """Un mot écrit en dur dans une valeur affichée ne passe jamais par le catalogue.

    Le cas courant est le ternaire `condition ? "Oui" : "Non"` : il compile, il
    s'affiche, et un système en anglais montre quand même le mot français.
    """
    findings = []
    pattern = re.compile(r'\?\s*"([^"]{1,40})"\s*:\s*"([^"]{1,40})"')
    for path in files:
        for i, line in enumerate(path.read_text(encoding="utf-8").split("\n")):
            if "String(localized" in line or "systemImage" in line:
                continue
            match = pattern.search(line)
            if match and all(looks_like_prose(group) for group in match.groups()):
                findings.append(Finding(
                    str(path), i + 1, "untranslated",
                    f'littéraux affichés « {match.group(1)} » / « {match.group(2)} » : '
                    "passer par String(localized:)",
                ))
    return findings


def rule_icon_buttons(files: list[Path], _catalog) -> list[Finding]:
    """Un bouton qui ne porte qu'une icône n'a pas de nom à annoncer."""
    findings = []
    pattern = re.compile(r'Button\s*\{[^}]*Image\(systemName:|Button\(\s*action:')
    for path in files:
        lines = path.read_text(encoding="utf-8").split("\n")
        for i, line in enumerate(lines):
            if "Image(systemName:" not in line:
                continue
            window = "\n".join(lines[max(0, i - 3):i + 6])
            if "Button" not in window:
                continue
            if "accessibilityLabel" in window or "Label(" in window or "Text(" in window:
                continue
            findings.append(Finding(
                str(path), i + 1, "icon-buttons",
                "bouton apparemment sans texte : vérifier qu'il porte un accessibilityLabel",
            ))
    return findings


RULES = {
    "regions": rule_regions,
    "tables": rule_tables,
    "announces": rule_announces,
    "combine": rule_combine,
    "contrast": rule_contrast,
    "hints": rule_hints,

    "labels": rule_labels,
    "untranslated": rule_untranslated,
    "icon-buttons": rule_icon_buttons,
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", help="règles à exécuter, séparées par des virgules")
    parser.add_argument("--files", nargs="*", help="fichiers ou dossiers à examiner")
    parser.add_argument("--diff", action="store_true", help="fichiers modifiés seulement")
    parser.add_argument("--list-rules", action="store_true", help="lister les règles")
    args = parser.parse_args()

    if args.list_rules:
        for name, function in RULES.items():
            summary = (function.__doc__ or "").strip().split("\n")[0]
            print(f"{name:14} {summary}")
        return 0

    if args.diff:
        targets = changed_files()
        if not targets:
            print("Aucun fichier Swift modifié.")
            return 0
    elif args.files:
        targets = [Path(p) for p in args.files]
    else:
        targets = [SOURCES]

    files = swift_files(targets)
    if not files:
        print("Aucun fichier Swift à examiner.")
        return 0

    selected = args.only.split(",") if args.only else list(RULES)
    unknown = [name for name in selected if name not in RULES]
    if unknown:
        print(f"Règle inconnue : {', '.join(unknown)}", file=sys.stderr)
        print(f"Disponibles : {', '.join(RULES)}", file=sys.stderr)
        return 2

    catalog = load_catalog()
    findings: list[Finding] = []
    for name in selected:
        findings.extend(RULES[name](files, catalog))

    findings.sort(key=lambda f: (f.rule, f.path, f.line))
    for finding in findings:
        print(finding)

    if not findings:
        print(f"Aucun constat sur {len(files)} fichiers.")
        return 0

    print()
    counts: dict[str, int] = {}
    for finding in findings:
        counts[finding.rule] = counts.get(finding.rule, 0) + 1
    detail = ", ".join(f"{rule} {count}" for rule, count in sorted(counts.items()))
    print(f"{len(findings)} constats sur {len(files)} fichiers — {detail}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
