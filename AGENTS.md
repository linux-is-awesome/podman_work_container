# Agent Instructions

This repository keeps a persistent context file for AI agents:

- `agents/AGENT_CONTEXT.md`

## Required startup step for any agent

Before making changes or giving implementation advice, read `agents/AGENT_CONTEXT.md` and use it as the baseline for:
- project intent
- previously accepted decisions
- constraints and guardrails

## Priority order

1. Direct user instruction in the current session
2. `agents/AGENT_CONTEXT.md`
3. Default agent behavior

If user instructions conflict with `agents/AGENT_CONTEXT.md`, follow the user and then update `agents/AGENT_CONTEXT.md` if needed.
