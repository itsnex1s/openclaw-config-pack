# voice-router

## Purpose

Parses voice transcripts and routes extracted items to appropriate topics.

## Activation

Automatically in the Voice topic (7) after voice message transcription.

## What It Extracts

| Type | Indicators | Routes to |
|------|-----------|-----------|
| Tasks | "need to", "fix", "implement", imperatives | topics/tasks/TODO.md |
| Ideas | "idea:", "what if", "it would be cool" | topics/ideas/IDEAS.md |
| Research | "how does", "study", "compare" | topics/research/{topic}.md |
| Notes | Everything else | topics/voice/SUMMARY.md |

## Workflow

1. Show full transcript
2. Show list of extracted items with categories
3. Ask for confirmation
4. Save to corresponding topic files
5. Report: what was saved where

## Task Format

```
- [ ] {description} @project({name}) @due({date}) @created({date})
```

## Idea Format

```
### IDEA-{NNN}: {title}
**Date:** {date}
**Description:** {text}
```

## Interaction with Other Skills

- **task-manager**: tasks are routed in its format (P1/P2/P3, @project, @due)
- **memory-manager**: transcripts subject to archiving after 30 days

## Constraints

- Does NOT route automatically — always asks for confirmation
- Does NOT modify existing entries — only appends new ones
- IDEA-NNN numbering continues from the last number in IDEAS.md
