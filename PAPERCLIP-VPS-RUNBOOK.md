# Runbook — Instalar o Paperclip numa VPS (com Claude Max)

Guia prático baseado em lições reais de deploy. Segue a ordem — ela **evita** os
erros que a gente pegou (fetch failed, página em branco, cert errado, etc.).

> **Objetivo:** Paperclip rodando em Docker, atrás de reverse proxy com HTTPS válido,
> com os agentes usando **Claude Max** (assinatura, sem pagar por token).

---

## 0. Pré-requisitos na VPS
- Linux com **root** (Ubuntu 24 testado)
- **Docker + Docker Compose v2**
- Um **reverse proxy** já instalado (Apache ou nginx) com **certbot** pra TLS
- **git**
- Um **hostname público** que resolva pro IP da VPS (subdomínio próprio, ex.:
  `agencia.seudominio.com`, ou o hostname auto da hospedagem)
- (Opcional, se for desenvolver na VPS) **Node 22** — adaptadores Cursor/Codex exigem ≥22

---

## 1. Subir o container do Paperclip

### Opção A — One-click (ex.: catálogo Docker da Hostinger)
No formulário de deploy:
- **Admin name / email / password** → preencha (é seu login no painel)
- **Anthropic / OpenAI / Gemini API Key** → **DEIXE EM BRANCO** ⚠️
  (essas keys = cobrança por token. O Claude **Max** NÃO entra por aqui — entra depois,
  como agente, via login. Ver passo 4.)

### Opção B — docker-compose manual
Use o `docker-compose.yml` deste repo como base (build do submodule `vendor/paperclip`).
Variáveis mínimas: `BETTER_AUTH_SECRET` (gere com `openssl rand -base64 48`),
`PAPERCLIP_PUBLIC_URL`, `PAPERCLIP_DATA_DIR`.

Depois de subir, ache o container e a porta publicada:
```bash
docker ps --format '{{.Names}}\t{{.Ports}}'
CID=$(docker ps --format '{{.Names}}' | grep -i paperclip | head -1); echo "$CID"
# confirme que responde internamente (troque a porta se necessário):
docker exec "$CID" sh -lc 'curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3100/api/health'
```

---

## 2. Reverse proxy + HTTPS válido — O PASSO MAIS IMPORTANTE ⭐

O Paperclip (modo `authenticated/private`) faz os **agentes falarem com o board pela URL
PÚBLICA**. Se essa URL não servir o Paperclip com **cert VÁLIDO**, os agentes falham com
`fetch failed` / `Cannot GET` (cert inválido = a CLI recusa; ou o proxy cai no vhost errado).

**Regra de ouro:** crie um vhost dedicado pro hostname do Paperclip → `127.0.0.1:<porta-publicada>`,
com cert Let's Encrypt. NÃO deixe cair no vhost default de outro app.

Exemplo Apache (troque `<HOST>` e `<PORTA>`):
```bash
# backup
cp -a /etc/apache2/sites-available /root/apache-backup-$(date +%s)

# vhost :80 (proxy + exceção pro desafio do certbot)
cat > /etc/apache2/sites-available/paperclip.conf <<'EOF'
<VirtualHost *:80>
    ServerName <HOST>
    ProxyPreserveHost On
    ProxyPass /.well-known/acme-challenge/ !
    ProxyPass / http://127.0.0.1:<PORTA>/
    ProxyPassReverse / http://127.0.0.1:<PORTA>/
</VirtualHost>
EOF

a2ensite paperclip
apachectl configtest && systemctl reload apache2

# emite cert + cria vhost :443 automaticamente
certbot --apache -d <HOST> --non-interactive --agree-tos --redirect
# (se pedir e-mail: adicione  -m seu-email@dominio )

# verificar
echo | openssl s_client -connect <HOST>:443 -servername <HOST> 2>/dev/null | openssl x509 -noout -subject
curl -sS https://<HOST>/api/health   # deve retornar o health do Paperclip
```
✅ Sucesso = `subject=CN = <HOST>` **e** o `/api/health` retorna `{"status":"ok",...}`.

Depois, garanta que `PAPERCLIP_PUBLIC_URL` no compose seja **`https://<HOST>`** e recrie:
```bash
cd <dir-do-compose> && docker compose up -d
```

---

## 3. Liberar o hostname na allowlist do Paperclip
No modo authenticated, o Paperclip recusa hostnames fora da allowlist:
```bash
docker exec -it "$CID" pnpm paperclipai allowed-hostname <HOST>
# (se pnpm falhar, tente com npx)
```

---

## 4. Login do Claude Max (assinatura, sem API key)
O adaptador `claude_local` usa o Claude Code logado no **Max**, DENTRO do container.
Quando um agente falhar com `Not logged in · Please run /login (claude_auth_required)`:

- **Opção fácil:** no painel, no run que falhou, clique **"Login to Claude Code"** e siga a URL.
- **Se o botão não abrir (headless):** pelo terminal:
```bash
docker exec -it "$CID" claude
# dentro: /login  → escolha CONTA COM ASSINATURA (Max), NÃO API key
#         abra a URL no navegador, autentique com a conta Max, cole o código
#         /exit
```
O login persiste no volume do container (`~/.claude` = `/paperclip/.claude`). Vale pra todos
os runs seguintes.

---

## 5. Tokens de entrega (pros agentes publicarem/versionarem)
- **Vercel (publicar sites):** crie um token em vercel.com/account/tokens → no agente,
  **Configuration → env** → `VERCEL_TOKEN` = `<token>`.
- **GitHub (push de código):** repo público resolve o *clone*, mas *push* precisa de auth.
  Crie um PAT fine-grained (Contents: read/write) e coloque no **Repo URL do projeto**:
  `https://<TOKEN>@github.com/<user>/<repo>`.

---

## 6. Modelo e orçamento do Max ⚡
- Agentes vêm em **Opus 4.8** por padrão → **queima a cota do Max rápido**, ainda mais com
  vários agentes. Para trabalho contínuo, troque o **Primary Model → Sonnet**
  (Configuration → Model). Deixe Opus só pra raciocínio pesado.
- Vários agentes rodando junto multiplicam o consumo. Se runs começarem a **morrer no meio**
  ("live execution disappeared"), suspeite de cota — mas confirme no run (429/usage limit).

---

## 7. Task travada / execução some
Se uma task ficar `blocked` com `issue_continuation_waiting_on_review` ou "no live execution":
1. **Feche/cancele** qualquer card de aprovação pendente na task (Confirmation / Ask user
   questions) — eles seguram a continuação.
2. Mova a task pra **Todo** (Properties → Status).
3. No agente → **Run Heartbeat** (dá uma execução viva nova).
4. (Opcional) Ligue **Settings → Instance → Experimental → Task Watchdogs** pra auto-recuperar.

---

## 8. Troubleshooting rápido (erros reais → fix)
| Sintoma | Causa | Fix |
|---|---|---|
| `Hostname X is not allowed` | allowlist | passo 3 (`allowed-hostname`) |
| `fetch failed em GET /api/health` | agente não alcança a API pela URL pública | passo 2 (vhost + cert válido) |
| Cert servido = outro domínio / `Cannot GET` nas rotas | sem vhost pro host → cai no default | passo 2 (criar vhost dedicado) |
| `Not logged in / claude_auth_required` | Max não logado no container | passo 4 |
| Deploy Vercel falha / sem `VERCEL_TOKEN` | token ausente no env do agente | passo 5 |
| `git push ... could not read Username` | sem credencial de push | passo 5 (PAT no Repo URL) |
| Página em branco (só o menu aparece) | animação de reveal escondendo conteúdo | conteúdo visível por padrão; motion só REALÇA (progressive enhancement) |
| Runs morrem no meio | cota do Max (Opus + vários agentes) | passo 6 (Sonnet); ou aguardar reset da janela |

---

## 9. Verificação final (checklist)
- [ ] `https://<HOST>/api/health` retorna `{"status":"ok"}` com cert válido
- [ ] Painel abre pelo hostname (HTTPS)
- [ ] Um `Run Heartbeat` do agente roda SEM `fetch failed`
- [ ] Agente consegue escrever no board (fechar/criar task)
- [ ] Claude Max logado (run não pede `/login`)
- [ ] Dados persistem (volume/bind mount preservado ao recriar o container)

---

_Gerado a partir do deploy real da Xiax (Paperclip via one-click Docker Hostinger,
Ubuntu 24). Ajuste hostnames/portas conforme sua VPS._
