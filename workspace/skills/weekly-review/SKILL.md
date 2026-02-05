# Skill: weekly-review

> Weekly summary of tasks, ideas, voice insights, and trends.
> No external dependencies. No scripts. No network calls.

## Purpose

Generates a structured weekly review covering all topics. Complements the daily
digest with a broader perspective on progress and priorities.

---

## When This Skill Activates

- User says "week", "weekly review" in Daily topic
- Can be triggered by cron (Sunday evening) or manually

---

## Review Structure

```
Weekly Review: {start_date} — {end_date}

## Tasks
Completed: {N} out of {total}
- {completed task 1}
- {completed task 2}

Overdue: {N}
- {overdue task} @due({date})

New tasks added: {N}

## Ideas
New: {N}
- IDEA-{NNN}: {title}
- IDEA-{NNN}: {title}

Implemented: {N}

## Voice
Transcripts: {N}
Extracted: {N} tasks, {N} ideas

Key themes:
- {theme 1}
- {theme 2}

## Research
Active topics: {N}
- {research topic 1}: {status}

## Projects
{project 1}:
- Progress: {summary}
- Key decisions: {decisions}

## Trends
- Productivity: {comparison with last week}
- Focus: {most active topic}
- Blockers: {recurring issues}

## Focus for Next Week
- P1: {top priority}
- P2: {second priority}
- P3: {nice to have}
```

---

## Data Sources

| Section | Source Files |
|---------|-------------|
| Tasks | topics/tasks/TODO.md, DONE.md |
| Ideas | topics/ideas/IDEAS.md |
| Voice | topics/voice/transcripts/*.md, SUMMARY.md |
| Research | topics/research/*.md |
| Projects | topics/projects/*/NOTES.md |
| Daily context | memory/{dates}.md |

---

## Generating the Review

1. Read DONE.md — tasks completed this week (by @done date)
2. Read TODO.md — current active + overdue tasks
3. Read IDEAS.md — ideas created this week (by date)
4. Read voice transcripts for the week — count and extract themes
5. Read research files — check status updates
6. Read project notes — recent changes
7. Read daily logs — extract patterns and recurring themes
8. Compare with previous week if available

---

## Trend Analysis

Track week-over-week:
- Tasks completed (more/less/same)
- New tasks vs completed (backlog growing or shrinking?)
- Most active topic by message count
- Recurring blockers or postponed tasks
- Ideas-to-tasks conversion rate

---

## Output

- Post review to Daily topic
- Save to `memory/weekly/{YYYY-Wnn}.md`

---

## Rules

- Review covers Monday to Sunday
- Use only data from workspace files (no external sources)
- If a section has no data, show "No data" instead of skipping
- Keep the review under 50 lines in Telegram (summarize if needed)
- "Focus for next week" is based on overdue P1 + upcoming deadlines
- Never fabricate statistics — report only what's in the files
