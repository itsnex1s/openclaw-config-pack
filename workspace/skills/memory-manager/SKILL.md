# Skill: memory-manager

> Memory organization, archiving, cleanup, and cross-topic search.
> No external dependencies. No scripts. No network calls.

## Purpose

Maintains the workspace memory system: consistent formatting, archiving old content,
preventing unbounded growth, and helping find information across topics.

---

## When This Skill Activates

This skill applies when:
- Writing to any memory file (MEMORY.md, topic files, daily logs)
- User asks to find, search, or organize information
- Daily/weekly maintenance routines run

---

## Memory Structure

```
workspace/
├── MEMORY.md              # Global long-term memory (key facts, preferences)
├── memory/
│   └── {YYYY-MM-DD}.md   # Daily interaction logs
├── topics/
│   ├── voice/transcripts/ # Voice transcripts by date
│   ├── ideas/IDEAS.md     # All ideas with IDs
│   ├── tasks/TODO.md      # Active tasks
│   ├── tasks/DONE.md      # Completed tasks
│   ├── research/{name}.md # Research topics
│   └── projects/{name}/   # Project contexts
└── shared/
    ├── PREFERENCES.md     # User preferences
    ├── CONTACTS.md        # Contacts and links
    └── GLOSSARY.md        # Terminology
```

---

## Writing Rules

### MEMORY.md (Global)

Only store **persistent facts** that are relevant across sessions:
- User preferences and work patterns
- Key project decisions
- Important contacts and accounts
- Technical setup details

Format:
```markdown
## {Category}
- {fact} (added {YYYY-MM-DD})
```

Do NOT store: temporary tasks, conversation details, transient context.
Max size: ~200 lines. If exceeding, consolidate or archive.

### Daily Logs (memory/{date}.md)

Auto-created for each day of interaction.

Format:
```markdown
# {YYYY-MM-DD}

## Summary
{1-3 sentence summary of the day}

## Key Events
- {event 1}
- {event 2}

## Decisions
- {decision and rationale}

## Follow-up
- {items to revisit}
```

### Topic Files

Each topic has its own format (defined by respective skills).
memory-manager ensures cross-references between topics use consistent linking:
```
→ see topics/tasks/TODO.md#task-name
→ see topics/ideas/IDEAS.md#IDEA-042
```

---

## Archiving Rules

### Daily Logs
- Keep last 14 days in memory/
- Older logs: summarize key points into MEMORY.md, then delete the daily file
- Archive command: `archive logs`

### Completed Tasks (DONE.md)
- Keep last 30 days
- Older: remove individual entries, keep monthly summary at the bottom
- Archive command: `archive tasks`

### Ideas (IDEAS.md)
- Implemented ideas → move to `topics/ideas/archive/` with result notes
- Rejected ideas → add `**Status:** rejected ({reason})`, keep in main file
- Archive command: `archive ideas`

### Voice Transcripts
- Keep last 30 days
- Older: delete raw transcripts, keep only SUMMARY.md entries
- Archive command: `archive voice`

---

## Search Commands

| Command | Action |
|---------|--------|
| `find {query}` | Search across all topic files |
| `memory {query}` | Search MEMORY.md and daily logs |
| `what happened {date}` | Show daily log for specific date |
| `memory stats` | File sizes, entry counts, last updated |

### Cross-Topic Search

When searching, check in order:
1. MEMORY.md (global facts)
2. Daily logs (recent context)
3. Topic files (ideas, tasks, research)
4. Shared files (preferences, contacts)
5. QMD index (if available via MCP)

Report findings with file path and date.

---

## Maintenance Command: "cleanup memory"

Run through this checklist:
1. Daily logs older than 14 days → summarize and archive
2. DONE.md entries older than 30 days → summarize and archive
3. Voice transcripts older than 30 days → archive
4. Check MEMORY.md size (warn if > 200 lines)
5. Report what was cleaned and current memory stats

---

## Rules

- Never delete content without creating a summary first
- Always confirm before bulk archiving
- Keep MEMORY.md concise — facts, not narratives
- Date format: always YYYY-MM-DD
- Cross-references must use relative paths from workspace/
- If a file doesn't exist yet, create it with the correct format header
