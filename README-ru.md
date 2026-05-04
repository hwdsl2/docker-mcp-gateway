[English](README.md) | [简体中文](README-zh.md) | [繁體中文](README-zh-Hant.md) | [Русский](README-ru.md)

# MCP Gateway на Docker

[![Статус сборки](https://github.com/hwdsl2/docker-mcp-gateway/actions/workflows/main.yml/badge.svg)](https://github.com/hwdsl2/docker-mcp-gateway/actions/workflows/main.yml) &nbsp;[![Лицензия: MIT](docs/images/license.svg)](https://opensource.org/licenses/MIT)

Docker-образ для запуска самостоятельно размещённого шлюза [MCP](https://modelcontextprotocol.io/) (Model Context Protocol), обеспечивающего аутентифицированный доступ к нескольким MCP-серверам инструментов через единую конечную точку. Основан на [MCPHub](https://github.com/samanhappy/mcphub) и прокси аутентификации Caddy. Разработан для простоты и безопасности по умолчанию.

**Возможности:**

- **Безопасность по умолчанию** — все API-запросы требуют Bearer Token (автоматически генерируется при первом запуске)
- Автоматически генерирует API-ключ при первом запуске, сохраняя его в постоянном томе
- Шлюз для нескольких серверов — запускает несколько MCP-серверов инструментов за единой конечной точкой HTTP
- Маршрутизация по пути — доступ ко всем серверам через `/mcp` или к конкретному через `/mcp/<имя>`
- Поддержка Streamable HTTP + SSE — оба режима транспорта MCP
- Панель управления — веб-интерфейс на `/` для мониторинга состояния MCP-серверов
- Конфигурация через env-файл — простой файл `mcp.env`; без редактирования JSON
- Встроенные MCP-серверы: filesystem, fetch, GitHub, Brave Search, Git, PostgreSQL, memory, sequential-thinking
- Обратный прокси Caddy обеспечивает аутентификацию Bearer Token для всех API-запросов (кроме `/health` для проверки работоспособности)
- Интеграция с [LiteLLM](https://github.com/hwdsl2/docker-litellm) для предоставления инструментов MCP любой LLM
- Автоматическая сборка и публикация через [GitHub Actions](https://github.com/hwdsl2/docker-mcp-gateway/actions)
- Постоянное хранение конфигурации через Docker-том
- Мультиархитектурный: `linux/amd64`, `linux/arm64`

**Также доступно:**

- ИИ/Аудио: [Whisper (STT)](https://github.com/hwdsl2/docker-whisper/blob/main/README-ru.md), [Kokoro (TTS)](https://github.com/hwdsl2/docker-kokoro/blob/main/README-ru.md), [Embeddings](https://github.com/hwdsl2/docker-embeddings/blob/main/README-ru.md), [LiteLLM](https://github.com/hwdsl2/docker-litellm/blob/main/README-ru.md), [Ollama (LLM)](https://github.com/hwdsl2/docker-ollama/blob/main/README-ru.md)
- VPN: [WireGuard](https://github.com/hwdsl2/docker-wireguard/blob/main/README-ru.md), [OpenVPN](https://github.com/hwdsl2/docker-openvpn/blob/main/README-ru.md), [IPsec VPN](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-ru.md), [Headscale](https://github.com/hwdsl2/docker-headscale/blob/main/README-ru.md)

**Совет:** MCP Gateway, Ollama, LiteLLM, Whisper, Kokoro и Embeddings можно [использовать совместно](#использование-с-другими-сервисами-ии) для создания полного приватного стека ИИ на вашем сервере — с доступом к инструментам, локальными LLM, голосовым вводом/выводом и семантическим поиском.

## Замечание по безопасности

MCP-серверы не имеют встроенной аутентификации. Публичное размещение без аутентификации — та же проблема, что и ~175 000 серверов Ollama, обнаруженных публично доступными без аутентификации ([источник](https://www.sentinelone.com/labs/silent-brothers-ollama-hosts-form-anonymous-ai-network-beyond-platform-guardrails/)). Этот образ через встроенный прокси аутентификации Caddy обеспечивает **аутентификацию Bearer Token для всех API-запросов**, поэтому даже при случайном открытии порта несанкционированный доступ будет заблокирован.

## Быстрый старт

**Шаг 1.** Запустите MCP Gateway:

```bash
docker run \
    --name mcp-gateway \
    --restart=always \
    -v mcp-data:/var/lib/mcp \
    -p 3000:3000/tcp \
    -d hwdsl2/mcp-gateway
```

При первом запуске автоматически генерируется API-ключ, который отображается в логах контейнера. Все API-запросы требуют этот ключ.

**Примечание:** Для развёртывания с доступом из интернета настоятельно **рекомендуется** использовать [обратный прокси](#использование-обратного-прокси) для добавления HTTPS. В этом случае также замените `-p 3000:3000/tcp` на `-p 127.0.0.1:3000:3000/tcp` в команде `docker run` выше, чтобы предотвратить прямой доступ к незашифрованному порту.

**Шаг 2.** Получите API-ключ:

```bash
# Просмотр ключа в логах контейнера
docker logs mcp-gateway

# Или получение ключа для использования в скриптах
MCP_KEY=$(docker exec mcp-gateway mcp_manage --getkey)
```

API-ключ отображается в рамке с надписью **MCP Gateway API key**. Чтобы отобразить его снова в любое время:

```bash
docker exec mcp-gateway mcp_manage --showkey
```

**Шаг 3.** Протестируйте API:

```bash
MCP_KEY=$(docker exec mcp-gateway mcp_manage --getkey)

# Проверка конечной точки MCP (по умолчанию включён сервер fetch)
curl http://localhost:3000/mcp \
  -H "Authorization: Bearer $MCP_KEY"

# Проверка работоспособности шлюза (без аутентификации)
curl http://localhost:3000/health
```

**Примечание:** Команды управления через `docker exec` (`mcp_manage`) не требуют API-ключа.

Чтобы узнать больше об использовании этого образа, читайте разделы ниже.

## Требования

- Сервер Linux (локальный или облачный) с установленным Docker
- Не менее 512 МБ доступной оперативной памяти
- TCP-порт 3000 (или настроенный вами) должен быть доступен

## Загрузка

Получите доверенную сборку из [реестра Docker Hub](https://hub.docker.com/r/hwdsl2/mcp-gateway/):

```bash
docker pull hwdsl2/mcp-gateway
```

Либо скачайте из [Quay.io](https://quay.io/repository/hwdsl2/mcp-gateway):

```bash
docker pull quay.io/hwdsl2/mcp-gateway
docker image tag quay.io/hwdsl2/mcp-gateway hwdsl2/mcp-gateway
```

Поддерживаемые платформы: `linux/amd64` и `linux/arm64`.

## Переменные окружения

Все переменные являются необязательными. Если они не установлены, автоматически используются безопасные значения по умолчанию.

Этот Docker-образ использует следующие переменные, которые можно объявить в файле `env` (см. [пример](mcp.env.example)):

| Переменная | Описание | По умолчанию |
|---|---|---|
| `MCP_API_KEY` | API-ключ для аутентификации запросов (автогенерируется, если не задан) | Автогенерируется |
| `MCP_PORT` | TCP-порт шлюза (1–65535) | `3000` |
| `MCP_HOST` | Имя хоста или IP, отображаемые в информации о запуске и выводе `--showkey` | Автоопределяется |
| `MCP_SERVERS` | Список MCP-серверов для включения (через запятую) | `fetch` |
| `MCP_ADMIN_PASSWORD` | Пароль администратора панели управления MCPHub (автогенерируется при первом запуске, если не задан) | Автогенерируется |

**Примечание:** В файле `env` значения можно заключать в одинарные кавычки, например `VAR='value'`. Не добавляйте пробелы вокруг `=`. Если вы изменили `MCP_PORT`, обновите флаг `-p` в команде `docker run` соответственно.

Пример использования файла `env`:

```bash
cp mcp.env.example mcp.env
# Отредактируйте mcp.env и установите значения, затем:
docker run \
    --name mcp-gateway \
    --restart=always \
    -v mcp-data:/var/lib/mcp \
    -v ./mcp.env:/mcp.env:ro \
    -p 3000:3000/tcp \
    -d hwdsl2/mcp-gateway
```

### Доступные MCP-серверы

Укажите серверы для включения в `MCP_SERVERS` (через запятую):

| Сервер | Необходимая конфигурация | Описание |
|---|---|---|
| `fetch` | — | Получение URL и извлечение содержимого |
| `filesystem` | `MCP_FILESYSTEM_DIRS` | Чтение/запись файлов в разрешённых директориях |
| `github` | `MCP_GITHUB_TOKEN` | Доступ к GitHub API (репозитории, issue, PR) |
| `brave-search` | `MCP_BRAVE_API_KEY` | Веб-поиск через Brave Search API |
| `git` | `MCP_GIT_REPO` | Инструменты Git (статус, diff, коммит, лог) |
| `postgres` | `MCP_POSTGRES_URL` | Запросы к базам данных PostgreSQL |
| `memory` | — | Граф знаний / постоянная память |
| `sequential-thinking` | — | Структурированное мышление и рассуждение |

**Пример:**

```bash
# Включить серверы filesystem, fetch и GitHub
MCP_SERVERS=filesystem,fetch,github
MCP_FILESYSTEM_DIRS=/data/docs,/data/projects
MCP_GITHUB_TOKEN=ghp_your_token_here
```

Для сервера `filesystem` примонтируйте директории хоста в контейнер:

```bash
docker run \
    --name mcp-gateway \
    --restart=always \
    -v mcp-data:/var/lib/mcp \
    -v ./mcp.env:/mcp.env:ro \
    -v /home/user/documents:/data/docs:ro \
    -v /home/user/projects:/data/projects \
    -p 3000:3000/tcp \
    -d hwdsl2/mcp-gateway
```

Для сервера `git` примонтируйте репозиторий в контейнер и задайте `MCP_GIT_REPO`:

```bash
MCP_SERVERS=git
MCP_GIT_REPO=/repo
```

```bash
docker run \
    --name mcp-gateway \
    --restart=always \
    -v mcp-data:/var/lib/mcp \
    -v ./mcp.env:/mcp.env:ro \
    -v /home/user/myrepo:/repo \
    -p 3000:3000/tcp \
    -d hwdsl2/mcp-gateway
```

## Управление MCP-серверами

Используйте `docker exec` для управления шлюзом с помощью вспомогательного скрипта `mcp_manage`.

**Список включённых серверов:**

```bash
docker exec mcp-gateway mcp_manage --list
```

**Проверка конкретного сервера:**

```bash
docker exec mcp-gateway mcp_manage --test fetch
docker exec mcp-gateway mcp_manage --test github
```

**Статус шлюза:**

```bash
docker exec mcp-gateway mcp_manage --status
```

**Показать API-ключ:**

```bash
docker exec mcp-gateway mcp_manage --showkey
```

**Получить API-ключ** (машиночитаемый формат, для скриптов):

```bash
MCP_KEY=$(docker exec mcp-gateway mcp_manage --getkey)
```

**Добавление или удаление серверов во время работы:**

Используйте панель управления MCPHub (`http://<сервер>:3000/`) для добавления, настройки или удаления MCP-серверов без перезапуска контейнера. Изменения сохраняются в постоянном томе и сохраняются после перезапуска.

> **Примечание:** `MCP_SERVERS` применяется только при **первом запуске**, когда создаётся `mcp_settings.json`. После этого панель управления является способом управления серверами. Чтобы повторно применить `MCP_SERVERS`, удалите файл конфигурации и перезапустите контейнер:
> ```bash
> docker exec mcp-gateway rm /var/lib/mcp/mcp_settings.json
> docker restart mcp-gateway
> ```

## Использование API

Все API-запросы требуют Bearer Token. Сначала получите API-ключ:

```bash
MCP_KEY=$(docker exec mcp-gateway mcp_manage --getkey)
```

**Конечная точка MCP (все включённые серверы):**

```bash
curl http://localhost:3000/mcp \
  -H "Authorization: Bearer $MCP_KEY"
```

**Конечная точка MCP (конкретный сервер):**

```bash
curl http://localhost:3000/mcp/fetch \
  -H "Authorization: Bearer $MCP_KEY"
```

**Панель управления** (веб-интерфейс):

Откройте `http://localhost:3000/` в браузере с заголовком `Authorization: Bearer <key>` или используйте клиент с поддержкой инъекции заголовков.

**Проверка работоспособности** (без аутентификации):

```bash
curl http://localhost:3000/health
```

### Подключение AI-клиентов

**Cline (VS Code)** — в настройках MCP Cline:

```json
{
  "mcpServers": {
    "gateway": {
      "url": "http://localhost:3000/mcp",
      "transport": "sse",
      "headers": {
        "Authorization": "Bearer <api_key>"
      }
    }
  }
}
```

**Claude Desktop** — в `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "gateway": {
      "url": "http://localhost:3000/mcp",
      "transport": "streamable-http",
      "headers": {
        "Authorization": "Bearer <api_key>"
      }
    }
  }
}
```

## Постоянное хранение данных

Все данные шлюза хранятся в Docker-томе (`/var/lib/mcp` внутри контейнера):

```
/var/lib/mcp/
├── mcp_settings.json   # Сгенерированная конфигурация MCPHub
├── .api_key            # API-ключ (автогенерируется или синхронизируется из MCP_API_KEY)
├── .initialized        # Маркер первого запуска
├── .port               # Сохранённый порт (используется mcp_manage)
├── .server_addr        # Кэшированный адрес сервера (используется mcp_manage --showkey)
├── .servers            # Список включённых серверов (используется mcp_manage)
└── .Caddyfile          # Сгенерированная конфигурация Caddy (прокси аутентификации)
```

`mcp_settings.json` генерируется из `MCP_SERVERS` только при первом запуске. При последующих перезапусках используется существующий файл, сохраняя все изменения, внесённые через панель управления.

Создавайте резервные копии Docker-тома для сохранения конфигурации и API-ключа.

## Использование docker-compose

```bash
cp mcp.env.example mcp.env
# Отредактируйте mcp.env и установите значения, затем:
docker compose up -d
docker logs mcp-gateway
```

Пример `docker-compose.yml` (уже включён):

```yaml
services:
  mcp-gateway:
    image: hwdsl2/mcp-gateway
    container_name: mcp-gateway
    restart: always
    ports:
      - "3000:3000/tcp"
    volumes:
      - mcp-data:/var/lib/mcp
      - ./mcp.env:/mcp.env:ro
      # Примонтируйте директории хоста для сервера filesystem MCP (необязательно):
      # - /path/to/docs:/data/docs:ro
      # - /path/to/code:/data/code:ro

volumes:
  mcp-data:
```

**Примечание:** Для развёртывания с доступом из интернета настоятельно **рекомендуется** использовать [обратный прокси](#использование-обратного-прокси) для добавления HTTPS. В этом случае также замените `"3000:3000/tcp"` на `"127.0.0.1:3000:3000/tcp"` в файле `docker-compose.yml`, чтобы предотвратить прямой доступ к незашифрованному порту.

## Использование обратного прокси

Для развёртывания с выходом в интернет разместите обратный прокси перед MCP Gateway для обработки HTTPS-терминации. Сервер работает без HTTPS в локальной или доверенной сети, но HTTPS рекомендуется при открытом доступе к API-эндпоинту из интернета.

Используйте один из следующих адресов для доступа к контейнеру MCP Gateway из обратного прокси:

- **`mcp-gateway:3000`** — если ваш обратный прокси работает как контейнер в **той же Docker-сети**, что и MCP Gateway (например, определён в том же `docker-compose.yml`).
- **`127.0.0.1:3000`** — если ваш обратный прокси работает **на хосте** и порт `3000` опубликован (по умолчанию `docker-compose.yml` публикует его).

**Примечание:** Заголовок `Authorization: Bearer` автоматически передаётся через обратные прокси — специальная настройка не требуется.

**Пример с [Caddy](https://caddyserver.com/docs/) ([Docker-образ](https://hub.docker.com/_/caddy))** (автоматический TLS через Let's Encrypt, обратный прокси в той же Docker-сети):

`Caddyfile`:
```
mcp.example.com {
  reverse_proxy mcp-gateway:3000
}
```

**Пример с nginx** (обратный прокси на хосте):

```nginx
server {
    listen 443 ssl;
    server_name mcp.example.com;

    ssl_certificate     /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass         http://127.0.0.1:3000;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;       # требуется для SSE и WebSocket
        proxy_read_timeout 300s;
        proxy_buffering    off;
        proxy_set_header   Upgrade $http_upgrade;
        proxy_set_header   Connection "upgrade";
    }
}
```

После настройки обратного прокси установите `MCP_HOST=mcp.example.com` в файле `env`, чтобы в логах запуска и выводе `mcp_manage --showkey` отображался правильный URL конечной точки.

## Обновление Docker-образа

Для обновления Docker-образа и контейнера сначала [загрузите](#загрузка) последнюю версию:

```bash
docker pull hwdsl2/mcp-gateway
```

Если Docker-образ уже актуален, вы увидите:

```
Status: Image is up to date for hwdsl2/mcp-gateway:latest
```

В противном случае будет загружена последняя версия. Удалите и пересоздайте контейнер:

```bash
docker rm -f mcp-gateway
# Затем повторно выполните команду docker run из раздела «Быстрый старт» с тем же томом.
```

Ваша конфигурация и API-ключ сохраняются в томе `mcp-data`.

## Использование с другими сервисами ИИ

Образы [MCP Gateway](https://github.com/hwdsl2/docker-mcp-gateway), [Ollama (LLM)](https://github.com/hwdsl2/docker-ollama), [LiteLLM](https://github.com/hwdsl2/docker-litellm), [Whisper (STT)](https://github.com/hwdsl2/docker-whisper), [Kokoro (TTS)](https://github.com/hwdsl2/docker-kokoro) и [Embeddings](https://github.com/hwdsl2/docker-embeddings) можно объединить для создания полного приватного стека ИИ на вашем сервере — от голосового ввода/вывода до RAG-ответов на вопросы. MCP Gateway предоставляет инструменты (доступ к файлам, веб-поиск, GitHub, базы данных) любому LLM-клиенту с поддержкой MCP. Whisper, Kokoro и Embeddings работают полностью локально. Ollama выполняет весь инференс LLM локально, данные не отправляются третьим сторонам. При использовании LiteLLM с внешними провайдерами (например, OpenAI, Anthropic) ваши данные будут отправлены этим провайдерам.

```mermaid
graph LR
    A["🤖 AI-клиент<br/>(Cline, Claude)"] -->|инструменты MCP| G["MCP Gateway<br/>(доступ к инструментам)"]
    G -->|filesystem| F["📁 Файлы"]
    G -->|fetch/search| W["🌐 Веб"]
    G -->|github| GH["🐙 GitHub"]
    A -->|чат| L["LiteLLM<br/>(шлюз ИИ)"]
    L -->|routes to| O["Ollama<br/>(локальная LLM)"]
    L -->|инструменты MCP| G
```

```mermaid
graph LR
    D["📄 Документы"] -->|embed| E["Embeddings<br/>(текст → векторы)"]
    E -->|хранение| VDB["Векторная БД<br/>(Qdrant, Chroma)"]
    A["🎤 Аудиовход"] -->|транскрипция| W["Whisper<br/>(речь → текст)"]
    W -->|запрос| E
    VDB -->|контекст| L["LiteLLM<br/>(шлюз ИИ)"]
    W -->|текст| L
    L -->|routes to| O["Ollama<br/>(локальная LLM)"]
    L -->|ответ| T["Kokoro TTS<br/>(текст → речь)"]
    T --> B["🔊 Аудиовыход"]
    L -->|протокол MCP| M["MCP Gateway<br/>(MCP-эндпоинт)"]
    M --> C["🤖 AI-ассистент<br/>(Claude, Cursor и др.)"]
```

| Сервис | Роль | Порт по умолчанию |
|---|---|---|
| **[Ollama (LLM)](https://github.com/hwdsl2/docker-ollama)** | Запускает локальные LLM-модели (llama3, qwen, mistral и др.) | `11434` |
| **[LiteLLM](https://github.com/hwdsl2/docker-litellm)** | Шлюз ИИ — маршрутизирует запросы к Ollama, OpenAI, Anthropic и 100+ провайдерам | `4000` |
| **[Embeddings](https://github.com/hwdsl2/docker-embeddings)** | Преобразует текст в векторы для семантического поиска и RAG | `8000` |
| **[Whisper (распознавание речи)](https://github.com/hwdsl2/docker-whisper)** | Транскрибирует речь в текст | `9000` |
| **[Kokoro (синтез речи)](https://github.com/hwdsl2/docker-kokoro)** | Преобразует текст в естественную речь | `8880` |
| **[MCP Gateway](https://github.com/hwdsl2/docker-mcp-gateway)** | Предоставляет инструменты MCP AI-клиентам (файловая система, fetch, GitHub, поиск, БД) | `3000` |

**Подключение MCP Gateway к LiteLLM:**

```yaml
# В конфигурации LiteLLM добавьте MCP-шлюз как источник инструментов:
mcp_servers:
  - url: http://mcp-gateway:3000/mcp
    transport: sse
    headers:
      Authorization: "Bearer <mcp_api_key>"
```

<details>
<summary><strong>Пример использования инструментов MCP</strong></summary>

Используйте MCP Gateway для предоставления AI-ассистенту доступа к файлам, вебу и GitHub:

```bash
MCP_KEY=$(docker exec mcp-gateway mcp_manage --getkey)

# Используйте MCP-эндпоинт с AI-клиентом (например, Cline в VS Code)
# Установите URL MCP-сервера: http://localhost:3000/mcp
# Установите заголовок Authorization: Bearer <api_key>

# Или протестируйте MCP-эндпоинт напрямую
curl -s http://localhost:3000/mcp \
    -X POST \
    -H "Authorization: Bearer $MCP_KEY" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
```

</details>

<details>
<summary><strong>Пример голосового конвейера</strong></summary>

Транскрибируйте речевой вопрос, получите ответ от локальной LLM через Ollama и преобразуйте в речь:

```bash
LITELLM_KEY=$(docker exec litellm litellm_manage --getkey)

# Шаг 1: Транскрибировать аудио в текст (Whisper)
TEXT=$(curl -s http://localhost:9000/v1/audio/transcriptions \
    -F file=@question.mp3 -F model=whisper-1 | jq -r .text)

# Шаг 2: Отправить текст в Ollama через LiteLLM и получить ответ
RESPONSE=$(curl -s http://localhost:4000/v1/chat/completions \
    -H "Authorization: Bearer $LITELLM_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"ollama/llama3.2:3b\",\"messages\":[{\"role\":\"user\",\"content\":\"$TEXT\"}]}" \
    | jq -r '.choices[0].message.content')

# Шаг 3: Преобразовать ответ в речь (Kokoro TTS)
curl -s http://localhost:8880/v1/audio/speech \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"tts-1\",\"input\":\"$RESPONSE\",\"voice\":\"af_heart\"}" \
    --output response.mp3
```

</details>

<details>
<summary><strong>Пример RAG-конвейера</strong></summary>

Встраивайте документы для семантического поиска, извлекайте контекст и отвечайте на вопросы с помощью локальной модели Ollama:

```bash
LITELLM_KEY=$(docker exec litellm litellm_manage --getkey)

# Шаг 1: Встроить фрагмент документа и сохранить вектор в векторной БД
curl -s http://localhost:8000/v1/embeddings \
    -H "Content-Type: application/json" \
    -d '{"input": "Docker упрощает развёртывание, упаковывая приложения в контейнеры.", "model": "text-embedding-ada-002"}' \
    | jq '.data[0].embedding'
# → Сохраните возвращённый вектор вместе с исходным текстом в Qdrant, Chroma, pgvector и т.д.

# Шаг 2: При запросе встройте вопрос, извлеките наиболее подходящие фрагменты из
#          векторной БД, затем отправьте вопрос и контекст в Ollama через LiteLLM.
curl -s http://localhost:4000/v1/chat/completions \
    -H "Authorization: Bearer $LITELLM_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "model": "ollama/llama3.2:3b",
      "messages": [
        {"role": "system", "content": "Отвечайте только на основе предоставленного контекста."},
        {"role": "user", "content": "Что делает Docker?\n\nКонтекст: Docker упрощает развёртывание, упаковывая приложения в контейнеры."}
      ]
    }' \
    | jq -r '.choices[0].message.content'
```

</details>

<details>
<summary><strong>Пример docker-compose для полного стека</strong></summary>

Разверните все сервисы одной командой. Настройка не требуется — все сервисы автоматически конфигурируются с безопасными значениями по умолчанию при первом запуске.

**Требования к ресурсам:** Для одновременного запуска всех сервисов требуется не менее 8 ГБ ОЗУ (с небольшими моделями). Для более крупных LLM-моделей (8B+) рекомендуется 32 ГБ и более. Вы можете закомментировать ненужные сервисы, чтобы снизить потребление памяти.

```yaml
services:
  ollama:
    image: hwdsl2/ollama-server
    container_name: ollama
    restart: always
    # ports:
    #   - "11434:11434/tcp"  # Uncomment for direct access to Ollama
    volumes:
      - ollama-data:/var/lib/ollama
      # - ./ollama.env:/ollama.env:ro  # optional: custom config

  litellm:
    image: hwdsl2/litellm-server
    container_name: litellm
    restart: always
    ports:
      - "4000:4000/tcp"
    environment:
      - LITELLM_OLLAMA_BASE_URL=http://ollama:11434
    volumes:
      - litellm-data:/etc/litellm
      # - ./litellm.env:/litellm.env:ro  # optional: custom config

  embeddings:
    image: hwdsl2/embeddings-server
    container_name: embeddings
    restart: always
    ports:
      - "8000:8000/tcp"
    volumes:
      - embeddings-data:/var/lib/embeddings
      # - ./embed.env:/embed.env:ro  # optional: custom config

  whisper:
    image: hwdsl2/whisper-server
    container_name: whisper
    restart: always
    ports:
      - "9000:9000/tcp"
    volumes:
      - whisper-data:/var/lib/whisper
      # - ./whisper.env:/whisper.env:ro  # optional: custom config

  kokoro:
    image: hwdsl2/kokoro-server
    container_name: kokoro
    restart: always
    ports:
      - "8880:8880/tcp"
    volumes:
      - kokoro-data:/var/lib/kokoro
      # - ./kokoro.env:/kokoro.env:ro  # optional: custom config

  mcp:
    image: hwdsl2/mcp-gateway
    container_name: mcp
    restart: always
    ports:
      - "3000:3000/tcp"
    volumes:
      - mcp-data:/var/lib/mcp
      # - ./mcp.env:/mcp.env:ro  # optional: custom config

volumes:
  ollama-data:
  litellm-data:
  embeddings-data:
  whisper-data:
  kokoro-data:
  mcp-data:
```

Для ускорения на NVIDIA GPU измените теги образов на `:cuda` для ollama, whisper и kokoro, и добавьте следующее к каждому из этих сервисов:

```yaml
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
```

</details>

## Технические подробности

- Базовый образ: `samanhappy/mcphub` (Python 3.13 + Node.js 22)
- Прокси аутентификации: [Caddy](https://caddyserver.com) (всегда активен, обеспечивает аутентификацию Bearer Token)
- Шлюз: [MCPHub](https://github.com/samanhappy/mcphub) (многосерверный MCP-концентратор)
- Внутренний порт MCPHub: `3001` (не публикуется; Caddy проксирует с `MCP_PORT`)
- Каталог данных: `/var/lib/mcp` (Docker-том)
- API шлюза: `http://localhost:3000` (или настроенный вами порт)
- Конечная точка MCP: `http://localhost:3000/mcp`
- Мультиархитектурный: `linux/amd64`, `linux/arm64`

## Лицензия

**Примечание:** Программные компоненты внутри готового образа (такие как MCPHub, Caddy и их зависимости) распространяются под лицензиями, выбранными их авторами. При использовании готового образа ответственность за соответствие лицензиям всего содержащегося в нём программного обеспечения лежит на пользователе образа.

Copyright (C) 2026 Lin Song   
Настоящая работа распространяется под [лицензией MIT](https://opensource.org/licenses/MIT).

**MCPHub** является собственностью (C) 2025 samanhappy и распространяется под [лицензией Apache 2.0](https://github.com/samanhappy/mcphub/blob/main/LICENSE).

**Caddy** является собственностью (C) 2015 Matthew Holt и авторов Caddy, и распространяется под [лицензией Apache 2.0](https://github.com/caddyserver/caddy/blob/master/LICENSE).

Этот проект представляет собой независимую Docker-конфигурацию для MCPHub и не связан с MCPHub, не одобрен и не спонсируется им.