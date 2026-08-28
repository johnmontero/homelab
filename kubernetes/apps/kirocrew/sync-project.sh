#!/bin/sh
# Prepara/actualiza un WORKSPACE de proyecto para Crew (autoría + git; NO build/deploy).
# Clona/pull el repo de código y el de docs, y ensambla el steering top-level =
# canon + steering del docs repo. El workspace queda en /home/kirocrew/workplace/<slug>
# (base que navega el picker del dashboard).
#
# Uso:
#   sh /home/kirocrew/.kiro/crew/sync-project.sh <slug> <repo-fs> <repo-docs>
# Ejemplos:
#   sh .../sync-project.sh pivas  protecso-pivas-fs  protecso-pivas-doc
#   sh .../sync-project.sh cotejo protecso-cotejo-fs protecso-cotejo-docs
#   sh .../sync-project.sh pulse  protecso-pulse-fs  protecso-pulse-docs
set +e
umask 077
SLUG="$1"; FS_REPO="$2"; DOC_REPO="$3"
if [ -z "$SLUG" ] || [ -z "$FS_REPO" ] || [ -z "$DOC_REPO" ]; then
  echo "uso: sync-project.sh <slug> <repo-fs> <repo-docs>"; exit 2
fi
HOME="${HOME:-/home/kirocrew}"
ORG="https://github.com/Protecso-SAC"
BASE="$HOME/workplace/$SLUG"
CANON="$HOME/.kiro/crew/checkouts/protecso-kiro-workflow"

mkdir -p "$BASE/.kiro/steering"

clone_or_pull() { # $1=url $2=dir
  if [ -d "$2/.git" ]; then git -C "$2" pull --ff-only; else git clone "$1" "$2"; fi
}

clone_or_pull "$ORG/$FS_REPO.git"  "$BASE/$FS_REPO"
clone_or_pull "$ORG/$DOC_REPO.git" "$BASE/$DOC_REPO"
if [ -d "$CANON/.git" ]; then git -C "$CANON" pull --ff-only; else git clone --depth 1 "$ORG/protecso-kiro-workflow.git" "$CANON"; fi

# Ensamblar steering: canon + steering del docs repo del proyecto.
cp "$CANON"/.kiro/steering/*.md "$BASE/.kiro/steering/" 2>/dev/null
cp "$BASE/$DOC_REPO/.kiro/steering/"*.md "$BASE/.kiro/steering/" 2>/dev/null

echo "OK workspace $SLUG:"
echo "  repos:    $(ls -d "$BASE"/protecso-* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
echo "  steering: $(ls -1 "$BASE/.kiro/steering" 2>/dev/null | wc -l) archivos"
exit 0
