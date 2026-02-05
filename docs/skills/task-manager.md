# task-manager

## Purpose

Structured task management: unified format, priorities, deadlines,
recurring tasks, reports.

## Activation

In the Tasks topic (11) and when other skills (voice-router) route tasks.

## File Structure

```
topics/tasks/
├── TODO.md        # Active tasks (P1 -> P2 -> P3)
├── DONE.md        # Completed (last 30 days)
└── RECURRING.md   # Recurring tasks
```

## Priorities

| Level | Meaning | When to use |
|-------|---------|-------------|
| P1 | Urgent + important | Blocks work, deadline today/tomorrow |
| P2 | Important | This week |
| P3 | Nice to have | When there's time |

Default: P2.

## Record Format

```
- [ ] {description} @priority(P2) @project(my-project) @due(2026-02-10) @created(2026-02-03)
```

## Commands

| Command | Action |
|---------|--------|
| `task: {text}` | Create task |
| `done: {text}` | Complete (-> DONE.md) |
| `today` | P1 + overdue + due today |
| `week` | Current week's tasks |
| `overdue` | All overdue tasks |
| `all tasks` | Full TODO.md |
| `cleanup` | Archive >30 days from DONE.md |

## Recurring Tasks

```
- Check logs @every(daily) @priority(P2)
- Backup @every(weekly) @day(sun) @priority(P1)
- Credential rotation @every(monthly) @day(1) @priority(P1)
```

## Interaction with Other Skills

- **voice-router**: receives tasks with @project and @due from voice transcripts
- **weekly-review**: reads TODO.md and DONE.md for the weekly report
- **memory-manager**: DONE.md is archived after 30 days
