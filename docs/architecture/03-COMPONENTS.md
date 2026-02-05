# System Components (C4)

## Level 1: System Context

```
         User #1              User #2
            │                    │
            └───── Telegram ─────┘
                      │
                   Bot API
                      │
              ┌───────▼────────┐
              │  OPENCLAW      │
              │  SYSTEM        │
              │                │
              │  Personal AI   │
              │  Assistant     │
              └──┬──────────┬──┘
                 │          │
          OpenRouter    QMD Search
          (LLM API)    (local docs)
```

## Level 2: Container Diagram

```
┌─────────────────────────────────────────────────────────┐
│                     HOST (WSL2)                          │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │              GATEWAY (systemd service)              │ │
│  │              Node.js :18789 (loopback)              │ │
│  │                                                     │ │
│  │  Telegram    WebChat     Gateway    Security        │ │
│  │  Channel     Server      Core       Filter          │ │
│  │  (grammY)    (WS)        (Auth)     (Input/Output)  │ │
│  │                                                     │ │
│  │  Agent       Tools       LLM        Output          │ │
│  │  Runtime     Manager     Provider   Processor       │ │
│  │  (Sessions)  (Sandbox)   (OR API)   (Redaction)     │ │
│  └────────────────────┬───────────────────────────────┘ │
│                       │                                  │
│  ┌────────────────────▼───────────────────────────────┐ │
│  │           SANDBOX CONTAINER(S)                      │ │
│  │           Ephemeral, per-session                    │ │
│  │                                                     │ │
│  │  - Isolated /workspace (read-only)                  │ │
│  │  - No network access                                │ │
│  │  - Limited tools (deny: exec, write, browser)       │ │
│  │  - Resource limits (256MB, 0.5 CPU, 32 PIDs)        │ │
│  └─────────────────────────────────────────────────────┘ │
│                                                          │
│  ┌──────────────────┐  ┌──────────────────┐             │
│  │   cloudflared    │  │   QMD (MCP)      │             │
│  │   Zero Trust     │  │   Bun server     │             │
│  │   No open ports  │  │   MD search      │             │
│  └──────────────────┘  └──────────────────┘             │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │              PERSISTENT STORAGE                    │   │
│  │  ~/.openclaw/                                     │   │
│  │  ├── openclaw.json       # Config                 │   │
│  │  ├── workspace/          # SECURITY.md, SOUL.md   │   │
│  │  │   └── .openclaw/skills/ # prompt/skill-guard   │   │
│  │  ├── credentials/        # Secrets (chmod 600)    │   │
│  │  ├── backups/            # GPG AES-256            │   │
│  │  └── agents/             # Sessions & state       │   │
│  └──────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘
```

## C4 Mermaid Diagrams

```mermaid
C4Context
    title System Context - OpenClaw

    Person(user1, "User #1", "Primary Telegram account")
    Person(user2, "User #2", "Secondary Telegram account")

    System(openclaw, "OpenClaw System", "Personal AI Assistant with Telegram integration")

    System_Ext(telegram, "Telegram", "Messaging platform")
    System_Ext(openrouter, "OpenRouter", "LLM API Gateway")
    System_Ext(cloudflare, "Cloudflare", "Zero Trust Tunnel")

    Rel(user1, telegram, "Sends messages")
    Rel(user2, telegram, "Sends messages")
    Rel(telegram, cloudflare, "Bot API")
    Rel(cloudflare, openclaw, "Secure tunnel")
    Rel(openclaw, openrouter, "LLM requests")
```

```mermaid
C4Container
    title Container Diagram - OpenClaw

    Person(user, "Authorized User", "Telegram user in allowlist")

    System_Boundary(host, "Host Machine (WSL2)") {
        Container(gateway, "Gateway", "Node.js, systemd", "Main application process")
        Container(sandbox, "Sandbox", "Docker", "Isolated tool execution")
        Container(cloudflared, "Cloudflared", "Go", "Tunnel client")
        Container(qmd, "QMD", "Bun", "Markdown search MCP")
        ContainerDb(storage, "Storage", "Filesystem", "Config, sessions, credentials")
    }

    System_Ext(telegram, "Telegram API")
    System_Ext(openrouter, "OpenRouter API")
    System_Ext(cloudflare, "Cloudflare Edge")

    Rel(user, telegram, "Messages")
    Rel(telegram, cloudflare, "Webhook")
    Rel(cloudflare, cloudflared, "Tunnel")
    Rel(cloudflared, gateway, "localhost:18789")
    Rel(gateway, sandbox, "Docker API")
    Rel(gateway, qmd, "MCP Protocol")
    Rel(gateway, openrouter, "HTTPS")
    Rel(gateway, storage, "Read/Write")
```
