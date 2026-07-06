# CLAUDE.md — Xiax-agencia

Instruções para o Claude Code operando neste repositório (tanto como agente dentro do Paperclip quanto para manutenção do deploy).

## ⚠️ REGRA-ZERO (não-negociável)
**TODA mudança neste repo começa por OpenSpec — sem exceção e sem precisar ser pedido.**
Antes de editar `docker-compose.yml`, `scripts/`, `.env.example`, infra ou config, o fluxo obrigatório é:

```
/opsx:propose "<o que vai mudar>"   →   revisar   →   /opsx:apply   →   /opsx:archive
```

Nunca edite arquivos de infra "no grito". Se o usuário pedir uma mudança direta, primeiro crie a proposta OpenSpec e só então implemente. Exceção única: correção trivial de typo em doc.

## Contexto
- Este é o **repo de deploy** do Paperclip, não um fork. O código do Paperclip vive no submodule `vendor/paperclip` e **não deve ser editado aqui** — mudanças no produto sobem upstream.
- O que se edita aqui: `docker-compose.yml`, `.env.example`, `scripts/`, `README.md`, specs em `openspec/`.

## Regras
- **Nunca** commitar `.env`, segredos, ou `.claude/.credentials.json`.
- Toda mudança de infra/config passa por **OpenSpec**: `/opsx:propose` → `/opsx:apply` → `/opsx:archive`.
- Atualizar o Paperclip = bumpar o submodule (`git submodule update --remote vendor/paperclip`) num commit próprio, não editar `vendor/`.
- Reverse proxy é **Apache/mod_proxy** (VPS Virtualmin) — nunca sugerir nginx.
- O agente Claude usa o **plano Max** (login no host), sem `ANTHROPIC_API_KEY`.

## Comandos úteis
- `docker compose up -d --build` — subir
- `docker compose exec paperclip npx paperclipai doctor` — diagnóstico
- `./scripts/bootstrap-vps.sh` — bootstrap idempotente
