# Plugin System

## Upstream vs Custom Separation

```
~/openclaw/                     READ-ONLY (git pull only)
├── dist/                       Compiled code
├── extensions/                 Official extensions
├── skills/                     Official skills
└── src/                        Source code

~/.openclaw/                    READ-WRITE (your data)
├── openclaw.json               Configuration
├── credentials/                API keys
└── workspace/
    ├── MEMORY.md               Global memory
    ├── topics/                 Topic memories
    └── .openclaw/              CUSTOMIZATIONS
        ├── extensions/         Your plugins
        └── skills/             Your skills
```

Updated via `git pull` | Preserved via `backup.sh` (GPG)

## Plugin Discovery Order

Gateway discovers plugins in this order:

1. **Custom paths** from `plugins.load.paths` in openclaw.json
   `~/.openclaw/workspace/.openclaw/extensions/`

2. **Bundled extensions** from `~/openclaw/extensions/`
   memory-core, telegram, discord, matrix

3. **NPM packages** `@openclaw/*`

4. **Enable/disable** via `plugins.entries`

## Custom Plugin Structure

```
~/.openclaw/workspace/.openclaw/extensions/
├── bookmarks/
│   ├── openclaw.plugin.json    # Manifest (required)
│   └── index.ts                # Entry point (required)
└── my-integrations/
    ├── openclaw.plugin.json
    └── index.ts
```

### openclaw.plugin.json

```json
{
  "id": "bookmarks",
  "name": "Bookmarks Manager",
  "version": "1.0.0",
  "description": "Save, list, and summarize web bookmarks"
}
```

## Plugin Configuration (openclaw.json)

```json
{
  "plugins": {
    "load": {
      "paths": ["~/.openclaw/workspace/.openclaw/extensions"]
    },
    "entries": {
      "bookmarks": {
        "enabled": true,
        "config": {
          "topicId": 125
        }
      }
    }
  }
}
```

## Customization Versioning

Store plugins in a separate Git repository:

```
github.com/YOU/openclaw-config/
├── workspace/
│   └── .openclaw/
│       ├── extensions/     # Custom plugins
│       └── skills/         # Custom skills
├── scripts/
│   └── backup.sh
└── openclaw.json
```

Deploy:
```bash
rsync -av repo/workspace/.openclaw/ ~/.openclaw/workspace/.openclaw/
```

## Version Compatibility

| OpenClaw Version | Plugin API | Notes |
|-----------------|-----------|-------|
| 2026.1.x | v1 | - |
| 2026.2.x | v1 | configSchema required |
| 2026.3.x | v2 | Changed PluginApi interface |

Specify minimum version in `openclaw.plugin.json`:
```json
{ "peerDependencies": { "openclaw": ">=2026.2.0" } }
```
