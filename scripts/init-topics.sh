#!/bin/bash
# init-topics.sh - Initialize OpenClaw workspace topic structure
#
# Creates directories and template files for:
# - Voice (voice messages)
# - Ideas
# - Tasks
# - Projects
# - Shared (common resources)

set -e

# Configuration
WORKSPACE="${OPENCLAW_HOME:-$HOME/.openclaw}/workspace"
DATE=$(date +%Y-%m-%d)

echo "=== OpenClaw Topics Structure Initialization ==="
echo "Workspace: $WORKSPACE"
echo ""

# Create main directories
echo "Creating directories..."

mkdir -p "$WORKSPACE"/{memory,shared}
mkdir -p "$WORKSPACE"/topics/voice/transcripts
mkdir -p "$WORKSPACE"/topics/ideas/archive
mkdir -p "$WORKSPACE"/topics/tasks
mkdir -p "$WORKSPACE"/topics/daily/weekly
mkdir -p "$WORKSPACE"/topics/research
mkdir -p "$WORKSPACE"/topics/projects/{my-project}

# ============================================================
# MEMORY.md - Global memory
# ============================================================
if [ ! -f "$WORKSPACE/MEMORY.md" ]; then
    cat > "$WORKSPACE/MEMORY.md" << 'EOF'
# Long-term Memory

This file contains important long-term information.
Loaded only in private sessions.

## About the user

<!-- Preferences, context, important facts -->

## Current priorities

<!-- Main goals and focus areas -->

## Important decisions

<!-- Key decisions that affect everything -->

## Key links

<!-- Frequently used resources -->
EOF
    echo "  Created: MEMORY.md"
fi

# ============================================================
# Voice Topic
# ============================================================
if [ ! -f "$WORKSPACE/topics/voice/SUMMARY.md" ]; then
    cat > "$WORKSPACE/topics/voice/SUMMARY.md" << 'EOF'
# Voice Summary

Summary of voice messages.

## Statistics
- Total voice messages: 0
- Last: -

## Key themes

<!-- Auto-updated based on transcripts -->

## Ideas from voice

<!-- Ideas extracted from voice messages -->

## Tasks from voice

<!-- Tasks extracted from voice messages -->
EOF
    echo "  Created: topics/voice/SUMMARY.md"
fi

# Today's transcript file
if [ ! -f "$WORKSPACE/topics/voice/transcripts/$DATE.md" ]; then
    cat > "$WORKSPACE/topics/voice/transcripts/$DATE.md" << EOF
# Voice Messages - $DATE

<!-- Voice message transcripts for today -->

EOF
    echo "  Created: topics/voice/transcripts/$DATE.md"
fi

# ============================================================
# Ideas Topic
# ============================================================
if [ ! -f "$WORKSPACE/topics/ideas/IDEAS.md" ]; then
    cat > "$WORKSPACE/topics/ideas/IDEAS.md" << 'EOF'
# Ideas

## New ideas

<!-- Fresh ideas, need review -->

## In progress

<!-- Ideas being developed -->

## Approved for implementation

<!-- Ideas ready to implement -->

## In work

<!-- Ideas being implemented -->
EOF
    echo "  Created: topics/ideas/IDEAS.md"
fi

# ============================================================
# Tasks Topic
# ============================================================
if [ ! -f "$WORKSPACE/topics/tasks/TODO.md" ]; then
    cat > "$WORKSPACE/topics/tasks/TODO.md" << 'EOF'
# TODO

## P1 Urgent (today)

<!-- Tasks for today -->

## P2 This week

<!-- Tasks for current week -->

## P3 Backlog

<!-- Tasks without deadline -->
EOF
    echo "  Created: topics/tasks/TODO.md"
fi

if [ ! -f "$WORKSPACE/topics/tasks/DONE.md" ]; then
    cat > "$WORKSPACE/topics/tasks/DONE.md" << 'EOF'
# Completed tasks

<!-- Archive of completed tasks with dates -->

EOF
    echo "  Created: topics/tasks/DONE.md"
fi

if [ ! -f "$WORKSPACE/topics/tasks/RECURRING.md" ]; then
    cat > "$WORKSPACE/topics/tasks/RECURRING.md" << 'EOF'
# Recurring tasks

## Daily
<!-- - [ ] Task @every(day) -->

## Weekly
<!-- - [ ] Task @every(week) @day(monday) -->

## Monthly
<!-- - [ ] Task @every(month) @day(1) -->
EOF
    echo "  Created: topics/tasks/RECURRING.md"
fi

# ============================================================
# Projects
# ============================================================
create_project() {
    local name="$1"
    local display_name="$2"
    local dir="$WORKSPACE/topics/projects/$name"

    if [ ! -f "$dir/CONTEXT.md" ]; then
        cat > "$dir/CONTEXT.md" << EOF
# Project: $display_name

## Description

<!-- Brief project description -->

## Tech Stack

| Category | Technologies |
|----------|------------|
| Frontend  |            |
| Backend   |            |
| Database  |            |
| DevOps    |            |

## Architecture

\`\`\`
<!-- High-level diagram -->
\`\`\`

## Links

- **Repository:**
- **Documentation:**
- **Production:**
- **Staging:**
- **CI/CD:**
EOF
        echo "  Created: topics/projects/$name/CONTEXT.md"
    fi

    if [ ! -f "$dir/DECISIONS.md" ]; then
        cat > "$dir/DECISIONS.md" << EOF
# Technical Decisions - $display_name

<!-- Archive of important technical decisions -->

## Decision Template

\`\`\`
## YYYY-MM-DD - Decision title

**Context:** Why this came up

**Decision:** What was decided

**Alternatives:**
1. Option A - why rejected
2. Option B - why rejected

**Consequences:** What this changes
\`\`\`

---

EOF
        echo "  Created: topics/projects/$name/DECISIONS.md"
    fi

    if [ ! -f "$dir/NOTES.md" ]; then
        cat > "$dir/NOTES.md" << EOF
# Notes - $display_name

<!-- Technical notes, research, links -->

EOF
        echo "  Created: topics/projects/$name/NOTES.md"
    fi
}

create_project "my-project" "MyProject"

# ============================================================
# Shared Resources
# ============================================================
if [ ! -f "$WORKSPACE/shared/PREFERENCES.md" ]; then
    cat > "$WORKSPACE/shared/PREFERENCES.md" << 'EOF'
# User Preferences

## Communication Style

- Brief, to-the-point answers
- Technical language
- No unnecessary emojis
- Code with comments

## Technical Preferences

### Languages
- Primary: TypeScript
- Backend: Python, Go
- Scripts: Bash

### Code Style
- Functional approach
- Immutability where possible
- Typing required
- Tests required

### Tools
- Editor: VS Code
- Terminal: your terminal
- Git: conventional commits
EOF
    echo "  Created: shared/PREFERENCES.md"
fi

if [ ! -f "$WORKSPACE/shared/CONTACTS.md" ]; then
    cat > "$WORKSPACE/shared/CONTACTS.md" << 'EOF'
# Contacts

<!-- Important contacts and resources -->

## Services

| Service | URL | Notes |
|---------|-----|-------|
| GitHub  |     |       |

## API Keys

Do not store keys here! Use .env files.
EOF
    echo "  Created: shared/CONTACTS.md"
fi

# ============================================================
# Daily Digest
# ============================================================
if [ ! -f "$WORKSPACE/topics/daily/README.md" ]; then
    cat > "$WORKSPACE/topics/daily/README.md" << 'EOF'
# Daily Digests

Archive of daily digests.

## Structure
- `YYYY-MM-DD.md` - daily digests
- `weekly/YYYY-Www.md` - weekly reviews

## Cron
```
0 8 * * * ~/.openclaw/scripts/daily-digest.sh
0 20 * * * ~/.openclaw/scripts/daily-digest.sh --evening
0 10 * * 0 ~/.openclaw/scripts/daily-digest.sh --weekly
```
EOF
    echo "  Created: topics/daily/README.md"
fi

# ============================================================
# Research
# ============================================================
if [ ! -f "$WORKSPACE/topics/research/INDEX.md" ]; then
    cat > "$WORKSPACE/topics/research/INDEX.md" << 'EOF'
# Research Index

## Active research

<!-- Current research topics -->

## Completed

<!-- Research with conclusions -->

---

Results in separate files: `{topic}.md`
EOF
    echo "  Created: topics/research/INDEX.md"
fi

# ============================================================
# Permissions
# ============================================================
echo ""
echo "Setting permissions..."
chmod 700 "$WORKSPACE"
find "$WORKSPACE" -type d -exec chmod 700 {} \;
find "$WORKSPACE" -type f -exec chmod 600 {} \;

# ============================================================
# Done
# ============================================================
echo ""
echo "=== Structure created successfully! ==="
echo ""
echo "Directory tree:"
find "$WORKSPACE" -type f -name "*.md" | head -20 | sed "s|$WORKSPACE|.|g"
echo "..."
echo ""
echo "Total files: $(find "$WORKSPACE" -type f | wc -l)"
echo "Total size: $(du -sh "$WORKSPACE" | cut -f1)"
