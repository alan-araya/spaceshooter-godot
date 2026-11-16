#!/usr/bin/env bash
# Build de Windows: um único Enxame2199.exe (template de release do Godot com o .pck embutido).
#
#   bash tools/build_windows.sh <pasta de saída> [commit]
#
# Usa o preset "Windows Desktop" de export_presets.cfg (o mesmo do Projeto → Exportar do editor): ícone,
# versão e .pck embutido vêm de lá; a tela cheia só no build vem de window/size/mode.release no
# project.godot. Sem commit, exporta a cópia de trabalho; com commit, exporta numa worktree separada.
# Precisa do Godot (GODOT_DIR) e dos modelos de exportação da mesma versão instalados.
set -euo pipefail

OUT="${1:?uso: bash tools/build_windows.sh <pasta de saída> [commit]}"
REF="${2:-}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_DIR="${GODOT_DIR:-D:/Godot Global/Godot_v4.8-beta3}"
G="$GODOT_DIR/Godot_v4.8-beta3_win64_console.exe"

SRC="$REPO"
if [ -n "$REF" ]; then
	SRC="${BUILD_WORKTREE:-$REPO/../space_shooter_build_src}"
	COMMIT="$(git -C "$REPO" rev-parse "$REF")"
	[ -d "$SRC" ] || git -C "$REPO" worktree add --detach "$SRC" "$COMMIT"
	git -C "$SRC" reset -q --hard
	git -C "$SRC" checkout -q --detach "$COMMIT"
	"$G" --headless --path "$SRC" --import > /dev/null 2>&1 || true
fi

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
rm -f "$OUT/Enxame2199.exe" "$OUT/Enxame2199.pck" "$OUT/Enxame2199.console.exe"
"$G" --headless --path "$SRC" --export-release "Windows Desktop" "$OUT/Enxame2199.exe" > "$OUT/_export.log" 2>&1 || true
[ -f "$OUT/Enxame2199.exe" ] || { cat "$OUT/_export.log"; exit 1; }
rm -f "$OUT/_export.log"

# fumaça: abre a Fortaleza, tira um screenshot e confere que não houve erro de script
cd "$OUT"
./Enxame2199.exe -- --mission=5 --autostart --shot="$OUT/_smoke.png" --shot-after=3 --quit-after-shot > _smoke.log 2>&1 || true
shots=$(grep -c SCREENSHOT _smoke.log || true)
errors=$(grep -ci "script error" _smoke.log || true)
rm -f _smoke.png _smoke.log
echo "build de $(git -C "$SRC" rev-parse --short HEAD)$( [ -z "$REF" ] && ! git -C "$SRC" diff --quiet && echo '+mudanças') em $OUT/Enxame2199.exe ($(du -m Enxame2199.exe | cut -f1) MB; screenshot: $shots, erros de script: $errors)"
[ "$shots" -ge 1 ] && [ "$errors" -eq 0 ]
