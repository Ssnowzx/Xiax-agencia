#!/usr/bin/env bash
# ==========================================================================
# Xiax-agencia — bootstrap do Paperclip numa VPS Linux.
# Idempotente: pode rodar de novo sem estragar o que já existe.
# Uso:  ./scripts/bootstrap-vps.sh
# ==========================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 1/5  Checando pré-requisitos"
command -v docker >/dev/null || { echo "ERRO: docker não instalado"; exit 1; }
docker compose version >/dev/null || { echo "ERRO: docker compose v2 ausente"; exit 1; }
command -v git >/dev/null || { echo "ERRO: git não instalado"; exit 1; }
command -v claude >/dev/null || echo "AVISO: claude CLI não encontrado no host (adaptador claude-local vai precisar do login Max)."

echo "==> 2/5  Sincronizando submodule vendor/paperclip"
git submodule update --init --recursive

echo "==> 3/5  Verificando .env"
if [ ! -f .env ]; then
  cp .env.example .env
  # Gera um BETTER_AUTH_SECRET se estiver vazio.
  if command -v openssl >/dev/null; then
    secret="$(openssl rand -base64 48)"
    # substitui a linha BETTER_AUTH_SECRET=
    tmp="$(mktemp)"; sed "s|^BETTER_AUTH_SECRET=.*|BETTER_AUTH_SECRET=${secret}|" .env > "$tmp" && mv "$tmp" .env
    echo "    .env criado a partir do exemplo (BETTER_AUTH_SECRET gerado)."
  fi
  echo "    >>> REVISE o .env (PAPERCLIP_PUBLIC_URL, portas) antes de expor publicamente."
else
  echo "    .env já existe — mantido."
fi

echo "==> 4/5  Build + up (docker compose)"
docker compose up -d --build

echo "==> 5/5  Rodando doctor"
docker compose exec paperclip npx paperclipai doctor || true

echo ""
echo "OK. Paperclip no ar em 127.0.0.1:${PAPERCLIP_PORT:-3100} (aponte o reverse proxy do Apache para essa porta)."
echo "Logs:   docker compose logs -f paperclip"
