#!/bin/sh
# Sincroniza el canon de steering de Protecso-Kiro a ~/.kiro/steering del crew.
# Best-effort: nunca falla el arranque del pod (si no hay red, conserva el canon
# ya presente en el PVC). Lo ejecuta el initContainer del deployment y también
# sirve para refrescos manuales:
#   kubectl -n kirocrew exec deploy/kirocrew -- sh /home/kirocrew/.kiro/crew/checkouts/sync-canon.sh
set +e
umask 077
HOME="${HOME:-/home/kirocrew}"
CHK="$HOME/.kiro/crew/checkouts"
REPO="$CHK/protecso-kiro-workflow"
REPO_URL="https://github.com/Protecso-SAC/protecso-kiro-workflow.git"
# Destino EFECTIVO: el agente de Crew (kirocrew.json) lee 'file://.kiro/steering/**/*.md'
# relativo a su workspace (default → ~/.kiro/crew/workspace). Ese es el dir que lee.
DEST="$HOME/.kiro/crew/workspace/.kiro/steering"

# Credenciales (si vienen por env desde el Secret kirocrew-git-creds).
if [ -n "$GIT_USER" ] && [ -n "$GIT_TOKEN" ]; then
  printf 'https://%s:%s@github.com\n' "$GIT_USER" "$GIT_TOKEN" > "$HOME/.git-credentials"
  chmod 600 "$HOME/.git-credentials"
  git config --global credential.helper store
fi

mkdir -p "$CHK" "$DEST"
if [ -d "$REPO/.git" ]; then
  git -C "$REPO" pull --ff-only
else
  git clone --depth 1 "$REPO_URL" "$REPO"
fi

if [ -d "$REPO/.kiro/steering" ]; then
  cp "$REPO"/.kiro/steering/*.md "$DEST"/ 2>/dev/null
  echo "OK: canon sincronizado a $DEST ($(ls -1 "$DEST" 2>/dev/null | wc -l) archivos)"
else
  echo "WARN: sin checkout del canon; se conserva el steering previo del PVC"
fi
exit 0
