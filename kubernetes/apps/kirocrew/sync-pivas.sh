#!/bin/sh
# Prepara/actualiza el WORKSPACE de PIVAS para Crew: clona/pull los dos repos del
# proyecto (código + docs) y ensambla el steering top-level = canon + pivas-context.
# Crew trabaja en este dir (workspace "pivas") para autoría + git de PIVAS.
# NO compila ni deploya (el pod no tiene docker/kubectl): eso queda en la máquina de dev.
#
# Uso (manual):  kubectl -n kirocrew exec deploy/kirocrew -- sh /home/kirocrew/.kiro/crew/sync-pivas.sh
#
# Ubicación: el picker de workspaces del dashboard navega /home/kirocrew/workplace/,
# así que el workspace de PIVAS vive ahí (aparece junto a kirocrew-workspace). El script
# se guarda fuera de workplace/ para no aparecer como entrada en el picker.
set +e
umask 077
HOME="${HOME:-/home/kirocrew}"
BASE="$HOME/workplace/pivas"
CANON="$HOME/.kiro/crew/checkouts/protecso-kiro-workflow"
FS_URL="https://github.com/Protecso-SAC/protecso-pivas-fs.git"
DOC_URL="https://github.com/Protecso-SAC/protecso-pivas-doc.git"

mkdir -p "$BASE/.kiro/steering"

clone_or_pull() {
  # $1=url  $2=dir
  if [ -d "$2/.git" ]; then git -C "$2" pull --ff-only; else git clone "$1" "$2"; fi
}

clone_or_pull "$FS_URL"  "$BASE/protecso-pivas-fs"
clone_or_pull "$DOC_URL" "$BASE/protecso-pivas-doc"
# Canon (por si el checkout no existe aún)
if [ -d "$CANON/.git" ]; then git -C "$CANON" pull --ff-only; else git clone --depth 1 https://github.com/Protecso-SAC/protecso-kiro-workflow.git "$CANON"; fi

# Ensamblar steering top-level del workspace: canon + steering del docs repo de PIVAS.
cp "$CANON"/.kiro/steering/*.md "$BASE/.kiro/steering/" 2>/dev/null
cp "$BASE/protecso-pivas-doc/.kiro/steering/"*.md "$BASE/.kiro/steering/" 2>/dev/null

echo "OK workspace pivas:"
echo "  repos:   $(ls -d "$BASE"/protecso-* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
echo "  steering: $(ls -1 "$BASE/.kiro/steering" 2>/dev/null | wc -l) archivos"
exit 0
