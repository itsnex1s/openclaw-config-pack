# Skill: voice-router

> Routes extracted content from voice transcripts to appropriate topics.
> No external dependencies. No scripts. No network calls.

## Purpose

Processes voice transcripts in the Voice topic and routes extracted items
to the correct topic files: tasks to Tasks, ideas to Ideas, research questions
to Research.

---

## When This Skill Activates

This skill applies when processing a voice message transcript in the Voice topic.

---

## Extraction Rules

After transcription, analyze the text and extract:

### 1. Tasks (action items)

Indicators:
- "need to", "must", "do", "add", "fix", "repair"
- "task:", "todo:"
- Imperative verbs: "update", "write", "check", "create", "delete"
- Deadlines: "by Friday", "tomorrow", "this week"

Format for TODO.md:
```
- [ ] {task description} @project({project}) @due({date if mentioned})
```

### 2. Ideas (creative, features, improvements)

Indicators:
- "idea:", "what if", "it would be cool", "we could"
- "feature:", "wish we had"
- Hypothetical/conditional language

Format for IDEAS.md:
```
### IDEA-{NNN}: {short title}
**Date:** {date}
**Description:** {idea essence}
**Related:** {project if mentioned}
```

### 3. Research (questions, unknowns)

Indicators:
- "how does it work", "what is", "need to figure out", "study"
- "compare", "what are the options", "alternatives"
- Questions about technologies, tools, approaches

Format for research/{topic}.md:
```
## {question}
**Date:** {date}
**Context:** {from transcript}
**Status:** new
```

### 4. Notes (everything else worth saving)

General observations, reminders, thoughts that don't fit above categories.
Save to the Voice topic SUMMARY.md.

---

## Routing Procedure

1. Present the full transcript in the Voice topic
2. List all extracted items grouped by type
3. Ask the user for confirmation before routing:
   ```
   Extracted from voice:
   Tasks (2): ...
   Ideas (1): ...
   Research (1): ...

   Route to topics?
   ```
4. On confirmation, save items to the appropriate files
5. Report what was saved and where

---

## Rules

- Never auto-route without confirmation
- Preserve original wording where possible
- If unsure about category, ask the user
- One transcript may produce items for multiple topics
- Always save the raw transcript to `topics/voice/transcripts/{date}.md`
- If a project is mentioned, tag the task with @project()
- Increment IDEA-NNN based on the last number in IDEAS.md
