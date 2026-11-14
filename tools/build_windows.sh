#!/usr/bin/env bash
# Build de Windows em tela cheia: Enxame2199.exe + Enxame2199.pck numa pasta.
#
#   bash tools/build_windows.sh <pasta de saída> [commit, padrão HEAD]
#
# Monta o .pck a partir de um commit (worktree separada, para não sujar a cópia de trabalho), liga a
# tela cheia só no build, copia o executável do Godot como Enxame2199.exe e troca o ícone dele pelo
# icon.ico do projeto. Precisa do Godot (variável GODOT_DIR) e do Python.
set -euo pipefail

OUT="${1:?uso: bash tools/build_windows.sh <pasta de saída> [commit]}"
REF="${2:-HEAD}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_DIR="${GODOT_DIR:-D:/Godot Global/Godot_v4.8-beta3}"
G="$GODOT_DIR/Godot_v4.8-beta3_win64_console.exe"
RUNTIME="$GODOT_DIR/Godot_v4.8-beta3_win64.exe"
W="${BUILD_WORKTREE:-$REPO/../space_shooter_build_src}"

COMMIT="$(git -C "$REPO" rev-parse "$REF")"
[ -d "$W" ] || git -C "$REPO" worktree add --detach "$W" "$COMMIT"
cd "$W"
git reset -q --hard
git checkout -q --detach "$COMMIT"
# tela cheia só no build (no editor e nos testes continua em janela)
python -I -c "
p='project.godot'; s=open(p,encoding='utf-8').read()
s=s.replace('window/stretch/mode=\"canvas_items\"\n','window/stretch/mode=\"canvas_items\"\nwindow/size/mode=3\n',1)
open(p,'w',encoding='utf-8',newline='\n').write(s)"
# preset de exportação (export_presets.cfg fica fora do git)
cat > export_presets.cfg <<'PRESET'
[preset.0]

name="Windows Desktop"
platform="Windows Desktop"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter="art_src/*, tools/*, docs/*"
export_path=""
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false

[preset.0.options]

binary_format/embed_pck=false
binary_format/architecture="x86_64"
PRESET
"$G" --headless --path . --import > /dev/null 2>&1 || true
"$G" --headless --path . --import > /dev/null 2>&1 || true

mkdir -p "$OUT"
"$G" --headless --path . --export-pack "Windows Desktop" "$OUT/Enxame2199.pck" > "$OUT/_export.log" 2>&1
grep -q DONE "$OUT/_export.log" || { cat "$OUT/_export.log"; exit 1; }
rm -f "$OUT/_export.log"
cp "$RUNTIME" "$OUT/Enxame2199.exe"
python -I "$REPO/tools/set_exe_icon.py" "$OUT/Enxame2199.exe" "$W/icon.ico"

# fumaça: abre a Fortaleza, tira um screenshot e confere que não houve erro de script
cd "$OUT"
./Enxame2199.exe -- --mission=5 --autostart --shot="$OUT/_smoke.png" --shot-after=3 --quit-after-shot > _smoke.log 2>&1 || true
shots=$(grep -c SCREENSHOT _smoke.log || true)
errors=$(grep -ci "script error" _smoke.log || true)
rm -f _smoke.png _smoke.log
echo "build $COMMIT em $OUT (screenshot: $shots, erros de script: $errors)"
[ "$shots" -ge 1 ] && [ "$errors" -eq 0 ]
