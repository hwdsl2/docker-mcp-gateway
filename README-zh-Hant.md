[English](README.md) | [简体中文](README-zh.md) | [繁體中文](README-zh-Hant.md) | [Русский](README-ru.md)

# Docker 上的 MCP Gateway

[![建置狀態](https://github.com/hwdsl2/docker-mcp-gateway/actions/workflows/main.yml/badge.svg)](https://github.com/hwdsl2/docker-mcp-gateway/actions/workflows/main.yml) &nbsp;[![授權條款: MIT](docs/images/license.svg)](https://opensource.org/licenses/MIT)

用於執行自託管 [MCP](https://modelcontextprotocol.io/)（模型上下文協定）閘道的 Docker 映像，透過單一端點提供對多個 MCP 工具伺服器的經驗證存取。基於 [MCPHub](https://github.com/samanhappy/mcphub) 和 Caddy 驗證代理。設計簡單，並預設安全。

**功能特色：**

- **預設安全** — 所有 API 請求均需 Bearer Token（首次啟動時自動產生）
- 首次啟動時自動產生 API 金鑰，並儲存在持久化卷中
- 多伺服器閘道 — 在單一 HTTP 端點後執行多個 MCP 工具伺服器
- 路徑路由 — 透過 `/mcp` 存取所有伺服器，或透過 `/mcp/<名稱>` 存取指定伺服器
- 支援 Streamable HTTP + SSE 兩種 MCP 傳輸模式
- 儀表板 — 位於 `/` 的 Web UI，用於監控 MCP 伺服器狀態
- 環境檔案設定 — 簡單的 `mcp.env` 檔案；無需編輯 JSON
- 內建 MCP 伺服器：filesystem、fetch、GitHub、Brave Search、Git、PostgreSQL、memory、sequential-thinking
- Caddy 反向代理對所有 API 請求強制執行 Bearer Token 驗證（`/health` 健康檢查除外）
- 與 [LiteLLM](https://github.com/hwdsl2/docker-litellm) 配合，為任何 LLM 提供 MCP 工具存取
- 透過 [GitHub Actions](https://github.com/hwdsl2/docker-mcp-gateway/actions) 自動建置和發布
- 透過 Docker 卷持久化設定
- 多架構：`linux/amd64`、`linux/arm64`

**另提供：**

- AI/音訊：[Whisper (STT)](https://github.com/hwdsl2/docker-whisper/blob/main/README-zh-Hant.md)、[Kokoro (TTS)](https://github.com/hwdsl2/docker-kokoro/blob/main/README-zh-Hant.md)、[Embeddings](https://github.com/hwdsl2/docker-embeddings/blob/main/README-zh-Hant.md)、[LiteLLM](https://github.com/hwdsl2/docker-litellm/blob/main/README-zh-Hant.md)、[Ollama](https://github.com/hwdsl2/docker-ollama/blob/main/README-zh-Hant.md)
- VPN：[WireGuard](https://github.com/hwdsl2/docker-wireguard/blob/main/README-zh-Hant.md)、[OpenVPN](https://github.com/hwdsl2/docker-openvpn/blob/main/README-zh-Hant.md)、[IPsec VPN](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-zh-Hant.md)、[Headscale](https://github.com/hwdsl2/docker-headscale/blob/main/README-zh-Hant.md)

**提示：** MCP Gateway、Ollama、LiteLLM、Whisper、Kokoro 和 Embeddings 可以[協同使用](#與其他-ai-服務配合使用)，在您自己的伺服器上建置完整的私有 AI 技術堆疊——包含工具存取、本地 LLM、語音輸入/輸出和語意搜尋。

## 安全說明

MCP 伺服器沒有內建驗證。在沒有驗證的情況下公開暴露它們，與約 175,000 台未經驗證公開暴露的 Ollama 伺服器屬於同類問題（[來源](https://www.sentinelone.com/labs/silent-brothers-ollama-hosts-form-anonymous-ai-network-beyond-platform-guardrails/)）。本映像透過內建的 Caddy 驗證代理對**所有 API 請求強制執行 Bearer Token 驗證**，即使連接埠意外暴露，未授權存取也會被阻止。

## 快速開始

**第一步。** 啟動 MCP Gateway：

```bash
docker run \
    --name mcp-gateway \
    --restart=always \
    -v mcp-data:/var/lib/mcp \
    -p 3000:3000/tcp \
    -d hwdsl2/mcp-gateway
```

首次啟動時，系統會自動產生 API 金鑰並顯示在容器日誌中。所有 API 請求均需此金鑰。

**注意：** 對於需要 HTTPS 的面向網際網路部署，請參閱[使用反向代理](#使用反向代理)。

**第二步。** 取得 API 金鑰：

```bash
# 在容器日誌中查看金鑰
docker logs mcp-gateway

# 或取得金鑰以在腳本中使用
MCP_KEY=$(docker exec mcp-gateway mcp_manage --getkey)
```

API 金鑰顯示在標有 **MCP Gateway API key** 的方框中。隨時可以透過以下指令重新顯示：

```bash
docker exec mcp-gateway mcp_manage --showkey
```

**第三步。** 透過 API 測試：

```bash
MCP_KEY=$(docker exec mcp-gateway mcp_manage --getkey)

# 測試 MCP 端點（預設啟用 fetch 伺服器）
curl http://localhost:3000/mcp \
  -H "Authorization: Bearer $MCP_KEY"

# 檢查閘道健康狀態（無需驗證）
curl http://localhost:3000/health
```

**注意：** `docker exec` 管理指令（`mcp_manage`）不需要 API 金鑰。

要了解有關如何使用此映像的更多資訊，請閱讀以下各節。

## 系統需求

- 已安裝 Docker 的 Linux 伺服器（本地或雲端）
- 至少 512 MB 可用記憶體
- TCP 連接埠 3000（或您設定的連接埠）需可存取

## 下載

從 [Docker Hub 映像倉庫](https://hub.docker.com/r/hwdsl2/mcp-gateway/)取得可信建置版本：

```bash
docker pull hwdsl2/mcp-gateway
```

支援平台：`linux/amd64` 和 `linux/arm64`。

## 環境變數

所有變數均為可選。如果未設定，將自動使用安全預設值。

此 Docker 映像使用以下變數，可在 `env` 檔案中宣告（參見[範例](mcp.env.example)）：

| 變數 | 說明 | 預設值 |
|---|---|---|
| `MCP_API_KEY` | 用於驗證請求的 API 金鑰（未設定時自動產生） | 自動產生 |
| `MCP_PORT` | 閘道的 TCP 連接埠（1–65535） | `3000` |
| `MCP_HOST` | 在啟動資訊和 `--showkey` 輸出中顯示的主機名稱或 IP | 自動偵測 |
| `MCP_SERVERS` | 要啟用的 MCP 伺服器清單（逗號分隔） | `fetch` |
| `MCP_ADMIN_PASSWORD` | MCPHub 儀表板管理員帳戶密碼（未設定時首次啟動自動產生） | 自動產生 |

**注意：** 在 `env` 檔案中，您可以將值用單引號括起來，例如 `VAR='value'`。不要在 `=` 兩側新增空格。如果您更改了 `MCP_PORT`，請相應地更新 `docker run` 指令中的 `-p` 旗標。

使用 `env` 檔案的範例：

```bash
cp mcp.env.example mcp.env
# 編輯 mcp.env 並設定您的值，然後：
docker run \
    --name mcp-gateway \
    --restart=always \
    -v mcp-data:/var/lib/mcp \
    -v ./mcp.env:/mcp.env:ro \
    -p 3000:3000/tcp \
    -d hwdsl2/mcp-gateway
```

### 可用的 MCP 伺服器

在 `MCP_SERVERS` 中列出要啟用的伺服器（逗號分隔）：

| 伺服器 | 所需設定 | 說明 |
|---|---|---|
| `fetch` | — | 擷取 URL 並提取內容 |
| `filesystem` | `MCP_FILESYSTEM_DIRS` | 在允許的目錄中讀寫檔案 |
| `github` | `MCP_GITHUB_TOKEN` | GitHub API 存取（儲存庫、Issue、PR） |
| `brave-search` | `MCP_BRAVE_API_KEY` | 透過 Brave Search API 進行網頁搜尋 |
| `git` | `MCP_GIT_REPO` | Git 儲存庫工具（狀態、diff、提交、日誌） |
| `postgres` | `MCP_POSTGRES_URL` | 查詢 PostgreSQL 資料庫 |
| `memory` | — | 知識圖譜/持久化記憶 |
| `sequential-thinking` | — | 結構化思考與推理 |

**範例：**

```bash
# 啟用 filesystem、fetch 和 GitHub 伺服器
MCP_SERVERS=filesystem,fetch,github
MCP_FILESYSTEM_DIRS=/data/docs,/data/projects
MCP_GITHUB_TOKEN=ghp_your_token_here
```

對於 `filesystem` 伺服器，需將主機目錄掛載到容器中：

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

對於 `git` 伺服器，需將儲存庫掛載到容器中並設定 `MCP_GIT_REPO`：

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

## 管理 MCP 伺服器

使用 `docker exec` 透過 `mcp_manage` 輔助腳本管理閘道。

**列出已啟用的伺服器：**

```bash
docker exec mcp-gateway mcp_manage --list
```

**測試指定伺服器：**

```bash
docker exec mcp-gateway mcp_manage --test fetch
docker exec mcp-gateway mcp_manage --test github
```

**顯示閘道狀態：**

```bash
docker exec mcp-gateway mcp_manage --status
```

**顯示 API 金鑰：**

```bash
docker exec mcp-gateway mcp_manage --showkey
```

**取得 API 金鑰**（機器可讀，用於腳本）：

```bash
MCP_KEY=$(docker exec mcp-gateway mcp_manage --getkey)
```

## 使用 API

所有 API 請求均需 Bearer Token。首先取得 API 金鑰：

```bash
MCP_KEY=$(docker exec mcp-gateway mcp_manage --getkey)
```

**MCP 端點（所有已啟用伺服器）：**

```bash
curl http://localhost:3000/mcp \
  -H "Authorization: Bearer $MCP_KEY"
```

**MCP 端點（指定伺服器）：**

```bash
curl http://localhost:3000/mcp/fetch \
  -H "Authorization: Bearer $MCP_KEY"
```

**儀表板**（Web UI）：

在瀏覽器中開啟 `http://localhost:3000/`，並新增 `Authorization: Bearer <key>` 請求標頭，或使用支援標頭注入的客戶端。

**健康檢查**（無需驗證）：

```bash
curl http://localhost:3000/health
```

### 連接 AI 客戶端

**Cline（VS Code）** — 在 Cline 的 MCP 設定中：

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

**Claude Desktop** — 在 `claude_desktop_config.json` 中：

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

## 持久化資料

所有閘道資料儲存在 Docker 卷中（容器內的 `/var/lib/mcp`）：

```
/var/lib/mcp/
├── mcp_settings.json   # 產生的 MCPHub 設定
├── .api_key            # API 金鑰（自動產生，或從 MCP_API_KEY 同步）
├── .initialized        # 首次執行標記
├── .port               # 儲存的連接埠（供 mcp_manage 使用）
├── .server_addr        # 快取的伺服器位址（供 mcp_manage --showkey 使用）
├── .servers            # 已啟用伺服器清單（供 mcp_manage 使用）
└── .Caddyfile          # 產生的 Caddy 設定（驗證代理）
```

備份 Docker 卷以保留您的設定和 API 金鑰。

## 使用 docker-compose

```bash
cp mcp.env.example mcp.env
# 編輯 mcp.env 並設定您的值，然後：
docker compose up -d
docker logs mcp-gateway
```

`docker-compose.yml` 範例（已包含）：

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
      # 掛載主機目錄用於 filesystem MCP 伺服器（可選）：
      # - /path/to/docs:/data/docs:ro
      # - /path/to/code:/data/code:ro

volumes:
  mcp-data:
```

## 使用反向代理

對於面向網際網路的部署，在前面放置反向代理來處理 HTTPS。內建的 Caddy 驗證代理處理驗證；外部反向代理新增 TLS。使用以下位址之一存取 MCP Gateway 容器：

- **`mcp-gateway:3000`** — 如果反向代理作為容器在同一 Docker 網路中執行
- **`127.0.0.1:3000`** — 如果反向代理在主機上執行且連接埠已發布

**注意：** `Authorization: Bearer` 標頭會自動通過反向代理傳遞，無需特殊設定。

**使用 [Caddy](https://caddyserver.com/docs/) 的範例（透過 Let's Encrypt 自動 TLS）：**

`Caddyfile`：
```
mcp.example.com {
  reverse_proxy mcp-gateway:3000
}
```

**使用 nginx 的範例（主機上的反向代理）：**

```nginx
server {
  listen 443 ssl;
  server_name mcp.example.com;

  ssl_certificate     /path/to/cert.pem;
  ssl_certificate_key /path/to/key.pem;

  location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 300s;
    proxy_buffering off;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
  }
}
```

設定反向代理後，在 `env` 檔案中設定 `MCP_HOST=mcp.example.com`，以便在啟動日誌和 `mcp_manage --showkey` 輸出中顯示正確的端點 URL。

## 更新 Docker 映像

要更新 Docker 映像和容器：

```bash
docker pull hwdsl2/mcp-gateway
docker rm -f mcp-gateway
# 然後使用相同的卷重新執行快速開始中的 docker run 指令。
```

您的設定和 API 金鑰保存在 `mcp-data` 卷中。

## 與其他 AI 服務配合使用

[MCP Gateway](https://github.com/hwdsl2/docker-mcp-gateway)、[Ollama](https://github.com/hwdsl2/docker-ollama)、[LiteLLM](https://github.com/hwdsl2/docker-litellm)、[Whisper (STT)](https://github.com/hwdsl2/docker-whisper)、[Kokoro (TTS)](https://github.com/hwdsl2/docker-kokoro) 和 [Embeddings](https://github.com/hwdsl2/docker-embeddings) 映像可以組合在一起，在您自己的伺服器上建置完整的私有 AI 技術堆疊。MCP Gateway 為支援 MCP 的任何 LLM 客戶端提供工具（檔案存取、網頁搜尋、GitHub、資料庫）。Ollama 在本地執行所有 LLM 推論，無需向第三方傳送資料。使用 LiteLLM 接入外部提供商（如 OpenAI、Anthropic）時，您的資料將傳送給這些提供商。

```mermaid
graph LR
    A["🤖 AI 客戶端<br/>（Cline、Claude）"] -->|MCP 工具| G["MCP Gateway<br/>（工具存取）"]
    G -->|filesystem| F["📁 檔案"]
    G -->|fetch/search| W["🌐 網頁"]
    G -->|github| GH["🐙 GitHub"]
    A -->|對話| L["LiteLLM<br/>（AI 閘道）"]
    L -->|路由到| O["Ollama<br/>（本地 LLM）"]
    L -->|MCP 工具| G
```

| 服務 | 作用 | 預設連接埠 |
|---|---|---|
| **[MCP Gateway](https://github.com/hwdsl2/docker-mcp-gateway)** | 為 AI 客戶端提供 MCP 工具（檔案系統、fetch、GitHub、搜尋、資料庫） | `3000` |
| **[Ollama](https://github.com/hwdsl2/docker-ollama)** | 執行本地 LLM 模型（llama3、qwen、mistral 等） | `11434` |
| **[LiteLLM](https://github.com/hwdsl2/docker-litellm)** | AI 閘道 — 將請求路由到 Ollama、OpenAI、Anthropic 等 100+ 提供商 | `4000` |
| **[Embeddings](https://github.com/hwdsl2/docker-embeddings)** | 將文字轉換為向量，用於語意搜尋和 RAG | `8000` |
| **[Whisper（語音轉文字）](https://github.com/hwdsl2/docker-whisper)** | 將語音音訊轉錄為文字 | `9000` |
| **[Kokoro（文字轉語音）](https://github.com/hwdsl2/docker-kokoro)** | 將文字轉換為自然語音 | `8880` |

**將 MCP Gateway 連接到 LiteLLM：**

```yaml
# 在 LiteLLM 設定中，將 MCP 閘道新增為工具來源：
mcp_servers:
  - url: http://mcp-gateway:3000/mcp
    transport: sse
    headers:
      Authorization: "Bearer <mcp_api_key>"
```

<details>
<summary><strong>完整技術堆疊 docker-compose 範例</strong></summary>

使用一條指令部署 MCP Gateway、Ollama 和 LiteLLM。在 `litellm.env` 中設定 `LITELLM_OLLAMA_BASE_URL=http://ollama:11434`。

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

  ollama:
    image: hwdsl2/ollama-server
    container_name: ollama
    restart: always
    volumes:
      - ollama-data:/var/lib/ollama
      - ./ollama.env:/ollama.env:ro

  litellm:
    image: hwdsl2/litellm-server
    container_name: litellm
    restart: always
    ports:
      - "4000:4000/tcp"
    volumes:
      - litellm-data:/etc/litellm
      - ./litellm.env:/litellm.env:ro

volumes:
  mcp-data:
  ollama-data:
  litellm-data:
```

</details>

## 技術細節

- 基礎映像：`samanhappy/mcphub`（Python 3.13 + Node.js 22）
- 驗證代理：[Caddy](https://caddyserver.com)（始終啟用，強制執行 Bearer Token 驗證）
- 閘道：[MCPHub](https://github.com/samanhappy/mcphub)（多伺服器 MCP 集線器）
- MCPHub 內部連接埠：`3001`（未發布；Caddy 從 `MCP_PORT` 代理）
- 資料目錄：`/var/lib/mcp`（Docker 卷）
- 閘道 API：`http://localhost:3000`（或您設定的連接埠）
- MCP 端點：`http://localhost:3000/mcp`
- 多架構：`linux/amd64`、`linux/arm64`

## 授權條款

**注意：** 預建置映像中的軟體元件（如 MCPHub、Caddy 及其相依套件）遵循其各自版權持有者選擇的授權條款。與任何預建置映像的使用一樣，映像使用者有責任確保對此映像的任何使用均符合其中包含的所有軟體的相關授權條款。

版權所有 (C) 2026 Lin Song   
本作品基於 [MIT 授權條款](https://opensource.org/licenses/MIT)授權。

**MCPHub** 版權所有 (C) 2024 samanhappy，基於 [Apache 授權條款 2.0](https://github.com/samanhappy/mcphub/blob/main/LICENSE) 分發。

**Caddy** 版權所有 (C) 2015 Matthew Holt 和 Caddy 作者，基於 [Apache 授權條款 2.0](https://github.com/caddyserver/caddy/blob/master/LICENSE) 分發。

本專案是 MCPHub 的獨立 Docker 設定，與 MCPHub 沒有任何關聯、背書或贊助關係。