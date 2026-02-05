# weekly-review

## Purpose

Weekly review: task progress, new ideas, voice topics,
trends, and focus for the next week.

## Activation

- Command "week", "weekly review" in Daily topic (12)
- Can be triggered by cron (Sunday evening)

## Data Sources

| Section | Files |
|---------|-------|
| Tasks | topics/tasks/TODO.md, DONE.md |
| Ideas | topics/ideas/IDEAS.md |
| Voice | topics/voice/transcripts/*.md, SUMMARY.md |
| Research | topics/research/*.md |
| Projects | topics/projects/*/NOTES.md |
| Context | memory/{dates}.md |

## Report Format

```
Weekly Report: {start} - {end}

Tasks: {completed}/{total} completed
- {task1}
- {task2}
Overdue: {N}

Ideas: {N} new
- IDEA-{N}: {title}

Voice: {N} transcripts
Topics: {theme1}, {theme2}

Trends
- Productivity: {up/down/stable} vs last week
- Focus: {most active topic}
- Backlog: {growing/shrinking}

Next Week
- P1: {top priority}
- P2: {second}
```

## Trend Analysis

Compares with previous week:
- Tasks completed (more/fewer)
- Backlog (TODO growing or shrinking)
- Ideas -> tasks (conversion rate)
- Recurring blockers

## Output

- Published to Daily topic (12)
- Saved to `memory/weekly/{YYYY-Wnn}.md`

## Interaction with Other Skills

- **task-manager**: reads TODO.md and DONE.md
- **memory-manager**: weekly files are not subject to auto-archiving
- **voice-router**: counts extracted items for the week
