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

## Consistency rules (must follow)

- Keep behavior consistent across `run`, `service-start`, `service-status`, and installed runtime under `/usr/local/lib/work_container`.
- For config-driven features, use the same pattern as VPN:
  - host templates/configs under `config/`
  - runtime-rendered configs under `/etc/...` inside container
  - do not introduce one-off runtime config locations when an established pattern exists.
- Status output must report real runtime state (health/socket/process/log-backed checks), not optimistic/configured values.
- Log messages should be plain text without custom bracketed prefixes unless user explicitly asks for a prefix format.
- When a user asks for consistency changes, update both:
  - implementation files, and
  - agent context/rules (`agents/AGENT_CONTEXT.md` and/or this file) so future agents keep the same conventions.
