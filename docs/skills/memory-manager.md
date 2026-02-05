# memory-manager

## Purpose

Organization, archiving, and search across the workspace memory system.
Prevents chaotic file growth.

## Activation

- When writing to any memory file
- On user command (search, cleanup)
- During maintenance routines

## Memory Structure

| File/folder | Contents | Retention |
|-------------|----------|-----------|
| MEMORY.md | Key facts, preferences | Permanent (max 200 lines) |
| memory/{date}.md | Daily logs | 14 days |
| topics/voice/transcripts/ | Transcripts | 30 days |
| topics/tasks/DONE.md | Completed tasks | 30 days |
| topics/ideas/IDEAS.md | Ideas | Permanent (implemented -> archive) |
| topics/research/ | Research | Permanent |
| shared/ | Preferences, contacts | Permanent |

## Writing Rules

### MEMORY.md
- Only **facts**, not narratives
- Format: `- {fact} (added {date})`
- Categories: preferences, projects, contacts, technical setup
- Max 200 lines — consolidate when exceeded

### Daily Logs
- Header: `# {YYYY-MM-DD}`
- Sections: Summary, Key Events, Decisions, Follow-up
- Keep it brief — max 30 lines per day

## Commands

| Command | Action |
|---------|--------|
| `find {query}` | Search across all files |
| `memory {query}` | Search MEMORY.md and logs |
| `what happened {date}` | Show day's log |
| `memory stats` | File sizes, last updated dates |
| `memory cleanup` | Full maintenance routine |
| `archive logs` | Archive logs older than 14 days |
| `archive tasks` | Archive DONE.md older than 30 days |
| `archive voice` | Archive transcripts older than 30 days |

## Archiving

1. Create summary from content being archived
2. Save summary to MEMORY.md or SUMMARY.md
3. Delete original file
4. User confirmation required before bulk operations

## Interaction with Other Skills

- **task-manager**: archives old DONE.md entries
- **voice-router**: transcripts subject to rotation
- **weekly-review**: uses data from all files for the review
