# Xiax-agencia

Repositório de **deploy/bootstrap** do [Paperclip](https://github.com/paperclipai/paperclip) — a plataforma open-source que orquestra um time de agentes de IA para "tocar uma empresa". Aqui ele já vem cabeado para rodar com **Claude Code (plano Max)** e com fluxo **spec-driven via OpenSpec**.

> **O que este repo NÃO é:** não é um fork do Paperclip. O Paperclip entra como *git submodule* em [`vendor/paperclip`](vendor/paperclip) (versão fixada = build reproduzível). Este repo carrega só a **configuração de deploy**, o runbook e o setup dos agentes.

---

## Arquitetura

```
Xiax-agencia/
├── vendor/paperclip/     # Paperclip (submodule, versão fixada)
├── docker-compose.yml    # self-host: build do submodule + Postgres embutido
├── .env.example          # variáveis (copie para .env — NUNCA commitar)
├── scripts/
│   └── bootstrap-vps.sh  # sobe tudo num comando na VPS
├── openspec/             # workflow spec-driven (OpenSpec)
├── .claude/              # comandos /opsx:* e skills do Claude Code
└── CLAUDE.md             # instruções do agente da agência
```

Agentes suportados pelo Paperclip: **Claude Code**, Codex, Cursor, OpenClaw, bash, HTTP. Aqui o foco é o adaptador `claude-local`, que usa o **login do seu plano Max** (sem API key).

---

## Pré-requisitos na VPS

| Item | Versão | Observação |
|---|---|---|
| Node.js | **22 LTS** | Node 20 roda o core, mas os adaptadores Cursor/Codex exigem ≥22. Use 22 e evita `EBADENGINE`. |
| Docker + Compose v2 | recente | o deploy é containerizado |
| git | qualquer | para clonar com submodule |
| Claude Code CLI | 2.x | logado no **plano Max** como o usuário de deploy |

> **VPS tars-server:** o usuário `rodrigo` **não tem sudo**. Instalar Docker/Node globais precisa de admin (Fert) ou instalação em user-space (ex.: `nvm` para Node, Docker rootless). Alinhe isso antes.

---

## Deploy em 4 passos

```bash
# 1. Clonar COM o submodule
git clone --recurse-submodules https://github.com/Ssnowzx/Xiax-agencia.git
cd Xiax-agencia

# 2. Garantir o login do Claude Code (plano Max) como o usuário de deploy
claude   # faça login pela assinatura Max se ainda não estiver logado

# 3. Configurar o ambiente
cp .env.example .env
#   edite .env: PAPERCLIP_PUBLIC_URL (seu subdomínio) e gere o segredo:
#   openssl rand -base64 48   ->  cole em BETTER_AUTH_SECRET

# 4. Subir
./scripts/bootstrap-vps.sh
```

O Paperclip sobe em `127.0.0.1:3100` (só loopback). **Exposição pública** é feita pelo **Apache/mod_proxy** da VPS (Virtualmin) apontando um subdomínio para essa porta — não instalar nginx.

### Reverse proxy (Apache) — esboço

```apache
<VirtualHost *:443>
    ServerName agencia.seu-dominio.com
    ProxyPreserveHost On
    ProxyPass        / http://127.0.0.1:3100/
    ProxyPassReverse / http://127.0.0.1:3100/
    # + SSL do Virtualmin/Let's Encrypt
</VirtualHost>
```

---

## Operação

```bash
docker compose logs -f paperclip        # logs
docker compose exec paperclip npx paperclipai doctor   # diagnóstico
docker compose exec paperclip npx paperclipai env      # env efetivo
docker compose down                     # parar
git submodule update --remote vendor/paperclip   # atualizar o Paperclip
```

---

## Workflow spec-driven (OpenSpec)

> **OpenSpec é ferramenta de _desenvolvimento_, não roda no container do Paperclip.**
> Ele vive na máquina onde você usa o Claude Code para evoluir este repo (seu Mac,
> ou a própria VPS se você desenvolver lá). Já vem **pré-configurado** no repo:
> `openspec/config.yaml` (com o contexto da Xiax) + comandos `/opsx:*` em `.claude/`.

**Pré-requisito (uma vez, onde você desenvolve):**
```bash
npm install -g @fission-ai/openspec@latest   # precisa Node >= 20.19
```
Os slash commands `/opsx:*` já funcionam pelo `.claude/` mesmo sem o CLI global;
o CLI é necessário para `openspec validate`, `archive`, `update`.

**Fluxo — toda mudança de infra/config começa por um proposal e termina validada:**
```
/opsx:propose "expor a agência em agencia.xiax.com com Apache"
/opsx:apply
/opsx:archive
```

Config em [`openspec/config.yaml`](openspec/config.yaml) (schema: spec-driven) — já
preenchido com stack, arquitetura e convenções da Xiax. **Regra-zero:** ver
[`CLAUDE.md`](CLAUDE.md) — nenhuma mudança de infra sem passar pelo OpenSpec.

---

## Segurança

- `.env` e credenciais **fora do git** (ver [`.gitignore`](.gitignore)).
- Deploy em modo `authenticated` + `private`: exige login para acessar o painel.
- O login do Claude Max vive no **host** (`~/.claude`), montado read-only no container — nunca no repositório.
