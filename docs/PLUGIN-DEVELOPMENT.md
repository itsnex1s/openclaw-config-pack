# OpenClaw Plugin Development

Complete guide to building plugins (extensions) for OpenClaw 2026.2.x.

---

## Overview

A plugin is a TypeScript module that:
- Registers **tools** — actions the agent can invoke
- Subscribes to **events** — reacts to incoming messages
- Runs in the gateway process (Node.js), NOT in sandbox

**Skills vs Plugins:**

| | Skills (`.md`) | Plugins (`.ts`) |
|---|---|---|
| Format | Markdown instructions | TypeScript code |
| Capabilities | Prompt injection into context | Tools, events, exec, files, API |
| Sandbox | Runs inside sandbox | Runs in gateway process |
| Reload | Automatic | Requires gateway restart |

---

## Quick Start

### 1. Create directory

```bash
mkdir -p ~/.openclaw/workspace/.openclaw/extensions/my-plugin
```

### 2. Create manifest

**`openclaw.plugin.json`** — required file:

```json
{
  "id": "my-plugin",
  "name": "My Plugin",
  "version": "1.0.0",
  "description": "Plugin description",
  "entry": "index.ts",
  "configSchema": {
    "type": "object",
    "properties": {},
    "additionalProperties": false
  }
}
```

**Required fields:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique ID, must match directory name |
| `name` | string | Human-readable name |
| `version` | string | semver |
| `description` | string | Brief description |
| `configSchema` | object | JSON Schema for configuration (**required, even if empty**) |

**Optional fields:**

| Field | Type | Description |
|-------|------|-------------|
| `entry` | string | Entry point (default: `index.ts`) |
| `author` | string | Author |
| `peerDependencies` | object | `{"openclaw": ">=2026.2.0"}` |

### 3. Create entry point

**`index.ts`** — main plugin file:

```typescript
import type { PluginApi } from "openclaw";

export default function (api: PluginApi) {
  console.log("[my-plugin] Plugin loaded");

  // Register a tool
  api.registerTool({
    name: "my_tool",
    description: "Tool description for the agent",
    parameters: {
      type: "object",
      properties: {
        input: { type: "string", description: "Input parameter" },
      },
      required: ["input"],
    },
    handler: async ({ input }: { input: string }) => {
      return { result: `Processed: ${input}` };
    },
  });
}
```

### 4. Restart gateway

```bash
# In tmux
tmux send-keys -t gw C-c
# Gateway will restart, or start manually
```

You should see in logs:
```
[my-plugin] Plugin loaded
```

---

## API: PluginApi

### registerTool

> **Warning:** `registerTool()` registers a **gateway-level** tool. The agent (LLM) can invoke it, but for handling incoming messages in topics, use `api.on("message_received")` — it's more reliable and doesn't depend on the LLM's decision.

Registers a tool at the gateway level.

```typescript
api.registerTool({
  name: "tool_name",           // snake_case, unique name
  description: "...",          // Description for the agent — the more precise, the better
  parameters: {                // JSON Schema for parameters
    type: "object",
    properties: {
      param1: { type: "string", description: "..." },
      param2: { type: "number", description: "...", default: 10 },
    },
    required: ["param1"],
  },
  handler: async (params) => {
    // params — parsed parameters from JSON Schema
    // return — object the agent will see as the result
    return { result: "..." };
    // or on error:
    return { error: "..." };
  },
});
```

**Tool naming rules:**
- `snake_case` — `save_bookmark`, `list_channels`
- No plugin prefix needed (plugin ID is added automatically)
- Description is for the LLM — write clearly and specifically

### on (events)

Subscribe to gateway events.

```typescript
// Incoming message (before agent processing)
api.on("message_received", async (msg: any) => {
  const meta = msg.metadata || {};
  // msg.content — message text
  // meta.threadId — topic ID (message_thread_id)
  // meta.to — chat ID (format: "telegram:-100xxx")
  // meta.message_id — message ID
  // msg.voice — voice message (if present)

  // You can modify msg.content for the agent:
  msg.content = `[Processed]: ${msg.content}`;
});
```

**Valid event names (from `types.d.ts`):**

```
before_agent_start | agent_end
before_compaction  | after_compaction
message_received   | message_sending  | message_sent
before_tool_call   | after_tool_call  | tool_result_persist
session_start      | session_end
gateway_start      | gateway_stop
```

> **Important:** Events use underscores (`message_received`), NOT colons (`message:received`). Colon-style names were used in OpenClaw 2026.1.x and are no longer valid.

### config

Access to OpenClaw and plugin configuration.

```typescript
export default function (api: PluginApi) {
  // Plugin config (from openclaw.json -> plugins.entries.my-plugin.config)
  const pluginConfig = api.config?.plugins?.entries?.["my-plugin"]?.config || {};

  // Global config
  const workspace = api.config?.agents?.defaults?.workspace;
}
```

---

## Templates

### Script Wrapper Plugin

The most common pattern — a tool calls an external script (Python, bash).

```typescript
import type { PluginApi } from "openclaw";
import { execSync } from "child_process";
import { existsSync, readFileSync } from "fs";
import { join } from "path";

const HOME = process.env.OPENCLAW_HOME
  || join(process.env.HOME || "", ".openclaw");
const SCRIPT = join(HOME, "scripts", "my-script.py");
const ENV_FILE = join(HOME, "credentials", ".env");

// Load variables from .env
function loadEnv(): Record<string, string> {
  const env: Record<string, string> = { ...process.env } as any;
  if (existsSync(ENV_FILE)) {
    for (const line of readFileSync(ENV_FILE, "utf-8").split("\n")) {
      const t = line.trim();
      if (t && !t.startsWith("#")) {
        const i = t.indexOf("=");
        if (i > 0) env[t.slice(0, i)] = t.slice(i + 1);
      }
    }
  }
  return env;
}

function run(args: string): string {
  if (!existsSync(SCRIPT)) throw new Error(`Not found: ${SCRIPT}`);
  return execSync(`python3 "${SCRIPT}" ${args}`, {
    encoding: "utf-8",
    timeout: 30_000,
    env: loadEnv(),
    cwd: join(HOME, "scripts"),
  }).trim();
}

export default function (api: PluginApi) {
  console.log("[my-plugin] Plugin loaded");

  api.registerTool({
    name: "do_something",
    description: "Performs an action via external script",
    parameters: {
      type: "object",
      properties: {
        query: { type: "string", description: "Query" },
      },
      required: ["query"],
    },
    handler: async ({ query }: { query: string }) => {
      try {
        return { result: run(`"${query}"`) };
      } catch (err: any) {
        return { error: err.message };
      }
    },
  });
}
```

### Event Hook Plugin

Reacts to incoming messages (e.g., voice-transcriber).

```typescript
import type { PluginApi } from "openclaw";

export default function (api: PluginApi) {
  console.log("[my-hook] Plugin loaded");

  api.on("message_received", async (msg: any) => {
    // Example: auto-process messages containing URLs
    const text = msg.content || "";
    const urlMatch = text.match(/https?:\/\/\S+/);
    if (!urlMatch) return;

    const url = urlMatch[0];
    console.log(`[my-hook] URL detected: ${url}`);

    // Modify text for the agent
    msg.content = `[URL detected: ${url}]\n\n${text}`;
  });
}
```

### Plugin with configSchema

If the plugin accepts settings from `openclaw.json`:

**openclaw.plugin.json:**
```json
{
  "id": "my-configurable",
  "name": "Configurable Plugin",
  "version": "1.0.0",
  "description": "Plugin with configuration",
  "configSchema": {
    "type": "object",
    "properties": {
      "targetTopic": {
        "type": "string",
        "default": "12",
        "description": "Topic ID to send results to"
      },
      "language": {
        "type": "string",
        "default": "en",
        "description": "Output language"
      },
      "maxResults": {
        "type": "number",
        "default": 10,
        "description": "Maximum results"
      }
    }
  }
}
```

**openclaw.json (activation):**
```json
{
  "plugins": {
    "entries": {
      "my-configurable": {
        "enabled": true,
        "config": {
          "targetTopic": "15",
          "language": "en",
          "maxResults": 5
        }
      }
    }
  }
}
```

**index.ts (reading config):**
```typescript
export default function (api: PluginApi) {
  const cfg = api.config?.plugins?.entries?.["my-configurable"]?.config || {};
  const topic = cfg.targetTopic || "12";
  const lang = cfg.language || "en";
  const max = cfg.maxResults || 10;

  console.log(`[my-configurable] loaded (topic=${topic}, lang=${lang})`);
  // ...
}
```

---

## Plugin File Structure

```
my-plugin/
├── openclaw.plugin.json    # Manifest (required)
├── index.ts                # Entry point (required)
├── package.json            # If npm dependencies needed
└── node_modules/           # Dependencies (bun install)
```

**If npm dependencies are needed:**

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "form-data": "^4.0.0"
  }
}
```

```bash
cd ~/.openclaw/workspace/.openclaw/extensions/my-plugin
bun install   # or npm install
```

---

## Common Errors

### `plugin manifest requires configSchema`

**Cause:** `openclaw.plugin.json` is missing `configSchema`.
**Fix:** Add an empty schema:

```json
{
  "configSchema": {
    "type": "object",
    "properties": {},
    "additionalProperties": false
  }
}
```

### `missing register/activate export`

**Cause:** Plugin doesn't export a default function.
**Wrong:**
```typescript
export const tools = [...]    // DOES NOT WORK
```
**Correct:**
```typescript
export default function (api: PluginApi) {
  api.registerTool({ ... });  // WORKS
}
```

### Tools not appearing for the agent

**Check:**
1. Plugin loaded: `grep "Plugin loaded" /tmp/gw.log`
2. No errors: `grep -i error /tmp/gw.log | grep my-plugin`
3. Topic configured: `openclaw.json` -> `topics` -> topic ID -> `systemPrompt` mentions the tool
4. Gateway restarted after changes

### execSync hangs

**Cause:** Script waiting for stdin or running too long.
**Fix:**
```typescript
execSync(`...`, {
  timeout: 30_000,          // 30 sec max
  stdio: ['pipe', 'pipe', 'pipe'],  // Don't inherit stdin
});
```

---

## Binding to a Telegram Topic

To have the agent use plugin tools in a specific topic, add
instructions to the topic's `systemPrompt` in `openclaw.json`:

```json
{
  "topics": {
    "125": {
      "requireMention": false,
      "systemPrompt": "Bookmarks\n\nWhen user sends a link - use save_bookmark tool.\n\nCommands:\n- list - list_bookmarks\n- read #N - mark_bookmark_read"
    }
  }
}
```

The agent sees all registered tools, but systemPrompt hints
when and which to use.

---

## Debugging

```bash
# Gateway logs (all plugins)
tail -f /tmp/gw.log

# Runtime logs (detailed)
tail -f /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log

# Filter by plugin
grep "my-plugin" /tmp/gw.log

# Check loading
grep "Plugin loaded" /tmp/gw.log
```

**console.log** from plugins goes to `/tmp/gw.log`:
```typescript
console.log("[my-plugin] doing something");  // -> [my-plugin] doing something
console.error("[my-plugin] error:", err);     // -> visible in logs
```

---

## Security

1. **Don't read credentials directly** — load via `process.env` or `.env` parser
2. **Don't log secrets** — `console.log` writes to file
3. **Set timeout on execSync** — external scripts can hang
4. **Validate input** — tool parameters come from LLM, may contain injection
5. **Never use `eval()`** — never execute user strings as code

---

## Deployment

```bash
# Copy plugin to runtime location
cp -r extensions/my-plugin \
      ~/.openclaw/workspace/.openclaw/extensions/

# Install dependencies (if package.json exists)
cd ~/.openclaw/workspace/.openclaw/extensions/my-plugin
bun install

# Restart gateway
tmux send-keys -t gw C-c
# Gateway restarts automatically, or:
tmux send-keys -t gw 'cd ~/openclaw && source ~/.openclaw/credentials/.env && node openclaw.mjs gateway 2>&1 | tee /tmp/gw.log' Enter
```

---

## Compatibility

| OpenClaw | Plugin API | Changes |
|----------|-----------|---------|
| 2026.1.x | v1 | `configSchema` optional |
| 2026.2.x | v1 | **`configSchema` required** |
| 2026.3.x | v2 | Changed PluginApi interface |

---

## Existing Plugins (reference)

| Plugin | Tools | Description |
|--------|-------|-------------|
| `voice-transcriber` | `transcribe_audio` + event hook | Voice transcription (whisper.cpp) |
| `task-manager` | `done`, `status`, `priority` | Task management with priorities |
| `bookmarks` | `save_bookmark`, `list_bookmarks`, `mark_bookmark_read` | Web bookmarks |
| `telegram-digest` | `trigger_digest`, `list_digest_channels` | Telegram channel digest |
