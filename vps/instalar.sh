#!/usr/bin/env bash
# One-time setup of the `evolution` app on the VPS. Runs from the PC.
# Idempotent: every step checks first, so it is safe to run again.
#
# Before running: create the app `evolution` in the painel (repo
# jaopdc11/evolution-api, branch vps). This script never creates the app.
#
#   bash vps/instalar.sh
set -euo pipefail

HOST="${VPS_HOST:-jaopd}"
APP=evolution
ADMIN=/usr/local/sbin/vps-admin
REPO=jaopdc11/evolution-api
BRANCH=vps

erro() { printf '\e[31merro:\e[0m %s\n' "$*" >&2; exit 1; }
ok()   { printf '\e[32m✓\e[0m %s\n' "$*"; }
etapa(){ printf '\e[1m== %s\e[0m\n' "$*"; }
admin() { ssh "$HOST" sudo -n "$ADMIN" "$@"; }
# value goes through stdin: never in argv (ps) or in a log
env_set() { printf '%s\n' "$2" | admin env "$APP" set "$1" >/dev/null; ok "$1"; }

etapa "app $APP existe?"
chaves=$(admin env "$APP" ls 2>/dev/null) \
  || erro "o app '$APP' não existe. Crie pelo painel (repo $REPO, branch $BRANCH) e rode de novo."
ok "existe"

etapa "Caddy, memória e porta (pede a SUA senha do sudo)"
# Evolution must not be public: drop the site the app creation made.
# MemoryMax goes in a drop-in, which vps-admin never rewrites.
# Not captured, so the sudo password prompt shows. The port is handed back in a
# file the login user owns, read by a plain ssh right after.
ssh -t "$HOST" sudo bash -c "'
  set -e
  if [ -e /etc/caddy/sites/$APP.caddy ]; then
    rm -f /etc/caddy/sites/$APP.caddy
    systemctl reload caddy
  fi
  install -d /etc/systemd/system/$APP.service.d
  printf \"[Service]\nMemoryMax=1G\n\" > /etc/systemd/system/$APP.service.d/memoria.conf
  systemctl daemon-reload
  install -m 600 -o \"\$SUDO_USER\" /etc/$APP/porta /tmp/$APP-porta
'"
porta=$(ssh "$HOST" "cat /tmp/$APP-porta && rm -f /tmp/$APP-porta" | tr -d '\r')
[[ $porta =~ ^[0-9]+$ ]] || erro "não consegui ler a porta do app (lido: '$porta')"
ok "sem site no Caddy · MemoryMax=1G · porta $porta"

etapa "variáveis de ambiente"
env_set SERVER_PORT "$porta"
env_set SERVER_URL "http://127.0.0.1:$porta"
env_set DATABASE_PROVIDER postgresql
env_set DATABASE_CONNECTION_URI "postgresql://$APP@localhost/$APP?host=/var/run/postgresql"
env_set DATABASE_SAVE_DATA_INSTANCE true
env_set EVOLUTION_DADOS "/srv/$APP/dados"
env_set CACHE_REDIS_ENABLED false
env_set CACHE_LOCAL_ENABLED true
env_set TELEMETRY_ENABLED false
env_set LOG_LEVEL ERROR,WARN,INFO
env_set DEL_INSTANCE false
env_set LANGUAGE pt-BR
env_set CONFIG_SESSION_PHONE_CLIENT Argos
chave_nova=""
if grep -qx AUTHENTICATION_API_KEY <<<"$chaves"; then
  ok "AUTHENTICATION_API_KEY (já existia, mantida)"
else
  chave_nova=$(openssl rand -hex 32)
  env_set AUTHENTICATION_API_KEY "$chave_nova"
  # shown now: a later step may fail, and a rerun keeps the stored key unseen
  printf '\n\e[1mChave da API (aparece só agora, guarde no gerenciador de senhas):\e[0m\n  %s\n\n' "$chave_nova"
fi

etapa "deploy"
if ! out=$(admin deploy-git "$APP" 2>&1); then
  if grep -q "não tem repo vinculado" <<<"$out"; then
    admin git-vincular "$APP" "$REPO" "$BRANCH"
    admin deploy-git "$APP"
  else
    printf '%s\n' "$out"; erro "deploy falhou"
  fi
else
  printf '%s\n' "$out" | tail -3
fi

etapa "painel (allowlist)"
ssh -t "$HOST" sudo -n "$ADMIN" painel-setup >/dev/null
ok "painel atualizado"

printf '\n\e[1mPronto.\e[0m Manager (QR code) só por túnel:\n'
printf '  ssh -N -L 8080:127.0.0.1:%s %s\n' "$porta" "$HOST"
printf '  depois abra http://localhost:8080/manager\n'
