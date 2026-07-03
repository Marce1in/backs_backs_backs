# backs_backs_backs

Backend (Elixir + Phoenix) da extensão de navegador [Tabs Tabs Tabs](https://github.com/Marce1in/tabs-tabs-tabs). Ele é responsável por:

- **Login com GitHub** (OAuth) — cada usuário tem seus próprios dados;
- **Sincronização de abas em tempo real** entre os navegadores do usuário, via Phoenix Channels (websocket);
- **Agrupamento de abas com IA** — o servidor chama o OpenRouter, salva os grupos gerados e envia o resultado para todos os navegadores conectados. Isso roda automaticamente **a cada 5 minutos** para os usuários online, ou imediatamente quando o usuário clica em **Agrupar abas** na extensão.

> **Já está no ar em `https://tabs.marce1in.com.br`.** Para avaliar o projeto, normalmente basta rodar a extensão apontando para essa URL (veja o [README da extensão](https://github.com/Marce1in/tabs-tabs-tabs)). Rodar o backend localmente é opcional — o guia abaixo existe para esse caso.

## Rodando localmente

### Requisitos

- Elixir 1.15+ com Erlang/OTP (ou apenas Docker, na opção B)
- Uma conta GitHub, para criar o OAuth App
- Uma chave de API do [OpenRouter](https://openrouter.ai), para o agrupamento com IA

### 1. Criar um GitHub OAuth App

1. Acesse GitHub → Settings → Developer settings → OAuth Apps → **New OAuth App**;
2. Use qualquer nome/homepage e, em **Authorization callback URL**, coloque:
   `http://localhost:4000/auth/github/callback`
3. Guarde o **Client ID** e gere um **Client Secret**.

### 2. Configurar as variáveis de ambiente

```bash
cp .env.example .env
```

Preencha no `.env`:

| Variável | O que é |
| --- | --- |
| `GITHUB_CLIENT_ID` / `GITHUB_CLIENT_SECRET` | Credenciais do OAuth App criado acima |
| `GITHUB_CALLBACK_URL` | `http://localhost:4000/auth/github/callback` (já vem preenchida) |
| `EXTENSION_REDIRECT_URIS` | Redirect URI da extensão (veja abaixo) |
| `OPENROUTER_API_KEY` | Chave do OpenRouter (necessária para o agrupamento com IA) |
| `OPENROUTER_MODEL` | Modelo usado (padrão: `openrouter/owl-alpha`) |
| `TAB_ORGANIZER_INTERVAL_MS` | Intervalo do agrupamento automático (padrão: `300000` = 5 minutos) |
| `SECRET_KEY_BASE` | Necessária só no Docker — gere com `mix phx.gen.secret` ou `openssl rand -base64 48` |

**Valor do `EXTENSION_REDIRECT_URIS`:** o ID da extensão é fixo (definido pelo campo `key` no `wxt.config.ts` dela), então o redirect URI é sempre:

```
https://liafoemlclglbogonogjffloegilkmgh.chromiumapp.org/github
```

(A variável aceita vários valores separados por vírgula. Para conferir o ID, abra `chrome://extensions` no navegador aberto pelo `pnpm dev`.)

### 3. Subir o servidor

**Opção A — com Elixir instalado:**

```bash
mix setup                     # instala dependências e cria o banco (SQLite)
set -a; source .env; set +a   # carrega as variáveis do .env
mix phx.server
```

**Opção B — com Docker:**

```bash
docker compose up -d
```

Nos dois casos o servidor sobe em `http://localhost:4000`. Depois, aponte o `.env` da extensão para ele:

```bash
WXT_BACKEND_HTTP_URL=http://localhost:4000
WXT_SYNC_SOCKET_URL=ws://localhost:4000/socket
```

## Testes

```bash
mix test
```
