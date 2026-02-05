# Skill: task-manager

> Structured task management with priorities, deadlines, and lifecycle.
> No external dependencies. No scripts. No network calls.

## Purpose

Manages tasks in the Tasks topic. Provides consistent format, priority system,
deadline tracking, recurring tasks, and status reports.

---

## When This Skill Activates

This skill applies in the Tasks topic and when other skills route tasks here.

---

## Task Format (TODO.md)

```markdown
- [ ] {description} @priority({P1|P2|P3}) @project({name}) @due({YYYY-MM-DD}) @created({YYYY-MM-DD})
```

### Priority Levels

| Priority | Meaning | Label |
|----------|---------|-------|
| P1 | Urgent + important. Blocks other work. | Red |
| P2 | Important, not urgent. This week. | Yellow |
| P3 | Nice to have. When time allows. | Green |

Default: P2 if not specified.

---

## File Structure

```
topics/tasks/
├── TODO.md        # Active tasks
├── DONE.md        # Completed (last 30 days)
└── RECURRING.md   # Recurring tasks
```

---

## Commands

| Command | Action |
|---------|--------|
| `task: {text}` | Create new task |
| `done: {text or #ID}` | Mark task complete, move to DONE.md |
| `today` | Show today's tasks (P1 + overdue + due today) |
| `week` | Show this week's tasks |
| `overdue` | Show overdue tasks |
| `all tasks` | Full TODO.md list |
| `cleanup` | Archive completed tasks older than 30 days |

---

## Creating Tasks

When the user says "task:" or routes a task from voice-router:

1. Parse description, project, priority, deadline
2. If priority not specified, ask or default to P2
3. If project mentioned, add @project() tag
4. Add @created() with today's date
5. Append to TODO.md in the correct priority section
6. Confirm with brief summary

---

## Completing Tasks

When the user says "done:" or marks a task:

1. Find the task in TODO.md
2. Add completion date: `@done({YYYY-MM-DD})`
3. Move to DONE.md (prepend, newest first)
4. Remove from TODO.md
5. Confirm completion

---

## Daily Report (command: "today")

```
Tasks for {date}:

P1 (Urgent):
- [ ] {task1}
- [ ] {task2}

Overdue:
- [ ] {task} @due({past date})

P2 (Due today):
- [ ] {task}

Total active: {N} | Overdue: {N}
```

---

## Recurring Tasks (RECURRING.md)

Format:
```markdown
- {description} @every({daily|weekly|monthly}) @day({mon|1}) @priority({P})
```

Examples:
```
- Check security logs @every(daily) @priority(P2)
- Weekly backup @every(weekly) @day(sun) @priority(P1)
- Credential rotation @every(monthly) @day(1) @priority(P1)
```

When a recurring task is due, add it to TODO.md if not already there.

---

## Rules

- Never delete tasks without confirmation
- Always move completed tasks to DONE.md (don't just delete)
- Keep TODO.md sorted: P1 first, then P2, then P3
- Overdue tasks always appear at the top of daily reports
- Tasks from voice-router inherit @project() if mentioned
- Maximum 20 active P1 tasks (warn if exceeded)
