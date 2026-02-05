# OpenClaw Skills

## Overview

Skills are Markdown files with instructions that extend agent behavior.
They are loaded automatically from `~/.openclaw/workspace/.openclaw/skills/`.

## All Skills

### Security

| Skill | File | Purpose |
|-------|------|---------|
| prompt-guard | `prompt-guard/SKILL.md` | Input message defense: canary detection, content quarantine, encoding awareness |
| skill-guard | `skill-guard/SKILL.md` | Third-party skill audit: red flags, permissions, scope analysis |

### Workflow

| Skill | File | Purpose |
|-------|------|---------|
| voice-router | `voice-router/SKILL.md` | Parse voice transcripts -> tasks, ideas, research |
| task-manager | `task-manager/SKILL.md` | Task management: P1/P2/P3 priorities, deadlines, recurring |
| memory-manager | `memory-manager/SKILL.md` | Memory organization: archiving, cleanup, cross-topic search |
| weekly-review | `weekly-review/SKILL.md` | Weekly review: progress, trends, next week's focus |

## Topic Mapping

```
Topic              Primary Skills
-----              --------------
General (1)        prompt-guard
Voice (7)          voice-router, prompt-guard
Ideas (8)          voice-router (routing target)
Tasks (11)         task-manager, voice-router (routing target)
Daily (12)         weekly-review
Security (50)      prompt-guard
MyProject (13)     task-manager (project tasks)
Research (15)      voice-router (routing target)

Cross-topic:       memory-manager (all topics)
Pre-install:       skill-guard (on demand)
```

## Data Flow Between Skills

```
Voice message
    |
    v
[voice-router] --parse--> tasks  --> [task-manager] --> TODO.md
                      |--> ideas  --> IDEAS.md
                      '--> research --> research/{topic}.md
                                            |
                                            v
[memory-manager] <-- archiving, cleanup, search across all files
                                            |
                                            v
[weekly-review]  <-- reads all topic files --> Weekly report to Daily (12)
```

## Deployment

```bash
# From config pack to runtime:
cp -r workspace/skills/* ~/.openclaw/workspace/.openclaw/skills/

# Verify loading:
# Gateway logs should show all skills loaded
```

## Principles

1. **No external dependencies** — Markdown instructions only
2. **No scripts** — no exec, curl, eval
3. **No network calls** — everything local to workspace
4. **User confirmation** — bulk actions only after confirm
5. **Audit before install** — third-party skills checked by skill-guard
