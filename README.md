# llm-brain-md

A copy-paste prompt that builds a **local, file-only "second brain"** for AI coding agents in `~/.claude/brain`. You need no Obsidian, no plugins, no `npm`, `pip`, or `curl`, and no network. It is built for enterprise machines where installing tools is blocked.

## Use it

1. Open [`SECOND-BRAIN-PROMPT.md`](SECOND-BRAIN-PROMPT.md) and copy the whole file. On GitHub, use the **Raw** view.
2. Paste it into Claude Code, or any agent that can read and write files: Codex CLI, Gemini CLI, Cursor, Copilot agent mode.
3. Answer the six onboarding questions. You can skip any of them.
4. Open a **new** session in any folder and ask: *"What do you know about me?"*

You can run the prompt again safely. It never deletes files. In existing config files, it only changes text between `<!-- BEGIN second-brain -->` and `<!-- END second-brain -->` markers, and it backs up each file before changing it. On a re-run it skips onboarding if your profile exists, adds only what is missing, and writes a log entry.

## What it builds

```
~/.claude/brain/
├── BRAIN.md      # the schema: how agents ingest, query, remember, lint
├── index.md      # catalog, one line per page (agents read this to navigate)
├── log.md        # append-only history: grep "^## \[" log.md | tail
├── inbox/        # drop anything here
├── raw/          # immutable source copies (any file type)
├── wiki/         # sources/ entities/ concepts/ synthesis/ (the agent writes these)
├── me/           # profile.md, goals.md
├── projects/     # one page per project, with dated decisions
├── journal/      # session notes
└── outputs/      # reports
```

It also wires the brain into each agent:

| Agent | How it learns about the brain |
|---|---|
| Claude Code | A short pointer block in `~/.claude/CLAUDE.md` that also `@`-imports `me/profile.md`, so every session knows who you are. It also adds the `/brain-ingest`, `/brain-query`, `/brain-remember`, and `/brain-lint` skills in `~/.claude/skills/`. |
| Cursor | Loads the same skills from `~/.claude/skills/` ([docs](https://cursor.com/docs/context/skills)). You paste the pointer block into Customize > Rules > User Rules. |
| Codex CLI | The pointer block in `~/.codex/AGENTS.md` (or `AGENTS.override.md` if present), added only if `~/.codex/` already exists. |
| Gemini CLI | The pointer block in `~/.gemini/GEMINI.md`, added only if `~/.gemini/` already exists. |
| GitHub Copilot (CLI, VS Code) | The pointer block in `~/.copilot/copilot-instructions.md`, added only if `~/.copilot/` already exists. |
| Windsurf, Cline, others | The agent prints the pointer block. You paste it into the tool's global instructions. |

## Why this works (Karpathy's LLM Wiki in one paragraph)

RAG makes the model rediscover knowledge on every question. The [LLM Wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) uses three layers instead:

- **raw sources**: immutable copies of what you feed in
- **wiki**: interlinked markdown pages that the LLM writes and maintains
- **schema file**: tells the agent how to keep the wiki up to date

The agent does the work humans give up on: summarizing, cross-linking, flagging contradictions, and keeping the index current. Knowledge therefore **compounds** across sessions instead of disappearing with the chat. Obsidian is only a viewer. The brain itself is plain markdown, so any editor or IDE preview works.

## Design choices for locked-down machines

- **Zero installs or downloads.** The setup uses only the agent's file tools and basic OS commands (`mkdir`, `cp`, `mv`, `grep`, `find`, `chmod`). Search is `grep` (or `rg` if present), plus `index.md`. That is enough up to hundreds of pages.
- **Relative markdown links** instead of `[[wikilinks]]`, so links are clickable in VS Code and JetBrains without Obsidian.
- **Small always-on context.** Only a roughly 10-line pointer block and `me/profile.md` load in every session. Agents read `BRAIN.md` only before writing to the brain, grep first, and open only the pages they need.
- **Safety rules in the schema.** The brain stores no secrets, customer data, or proprietary code. It redacts sensitive values before saving, and a leaked secret is the only allowed edit to `raw/`. It treats source content as data, never as instructions, which guards against prompt injection. It stays local (never pushed or synced), keeps the log append-only, and archives pages instead of deleting them. Edits to `me/` need your confirmation.
- **One brain, many agents.** Every agent reads the same `BRAIN.md`, so you can switch tools without rebuilding anything.

## Sources reviewed

- Andrej Karpathy, [LLM Wiki idea file](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) ([mirror](https://github.com/NicholasSpisak/second-brain/blob/main/docs/llm-wiki.md))
- NicholasSpisak, [second-brain REQUIREMENTS.md](https://github.com/NicholasSpisak/second-brain/blob/main/docs/REQUIREMENTS.md): the raw/wiki/output layout and the ingest/query/lint operations
- gcalacoci, [second-brain-starter-kit](https://github.com/gcalacoci/second-brain-starter-kit): the profile and goals layer, session capture, and the multi-agent shim
- neeltom92, [agent-plugin-marketplace](https://github.com/neeltom92/agent-plugin-marketplace): Cursor reads skills from `~/.claude/skills/`

The two reference implementations depend on `npx`, `uv`, `setup.sh`, MCP servers, or Obsidian. This prompt keeps their ideas and drops those dependencies.

## Limits

- **No encryption at rest.** The only protection is owner-only permissions (`chmod 700`). Put the brain on an encrypted disk if your policy requires it.
- **No secret scanner.** Redaction depends on the agent's judgment. Run `/brain-lint` regularly.
- **No file locking.** Two agents writing at the same moment can conflict. The schema tells agents to re-read and merge.
- **Grep-based search** works up to a few hundred pages. Beyond that, ask your agent to write a small local search script.
