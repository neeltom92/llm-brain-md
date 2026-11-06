# llm-brain-md

A copy-paste prompt that builds a **local, file-only "second brain"** for Claude Code in `~/.claude-brain`. You need no Obsidian, no plugins, no `npm`, `pip`, or `curl`, and no network. It is built for enterprise machines where installing tools is blocked.

## Use it

1. Open [`SECOND-BRAIN-PROMPT.md`](SECOND-BRAIN-PROMPT.md) and copy the whole file. On GitHub, use the **Raw** view.
2. Paste it into Claude Code (terminal or IDE extension).
3. Answer the six onboarding questions. You can skip any of them.
4. Approve the permission prompts. Claude Code always asks before writing into `~/.claude/` (the `CLAUDE.md` pointer, skills, hooks, and `settings.json`), even during setup.
5. Choose whether to install the 30-minute background sweep (macOS/Linux).
6. Open a **new** Claude Code session in any folder and ask: *"What do you know about me?"* Sessions that were already open do not pick up the brain or the hooks.

After that, there is nothing to do day to day:
- Claude saves decisions and fixes as they happen, and auto-saves after 30 active minutes.
- The next session, or the background sweep, recovers work from closed tabs and restarts.
- Repos with `CLAUDE.md` or `.claude/` are learned when you start Claude in the repo's root folder.

Optional extras:
- Say "remember …" for anything you want kept for sure.
- Say "lint my brain" about once a month.
- Re-paste the prompt when it is updated.

You can run the prompt again safely. It never deletes files. In existing config files, it only changes text between `<!-- BEGIN second-brain -->` and `<!-- END second-brain -->` markers, and it backs up each file before changing it. On a re-run it skips onboarding if your profile exists, adds only what is missing, and writes a log entry.

## What it builds

```
~/.claude-brain/
├── BRAIN.md      # the schema: how Claude ingests, queries, remembers, lints
├── index.md      # catalog, one line per page (Claude reads this to navigate)
├── log.md        # append-only history: grep "^## \[" log.md | tail
├── inbox/        # drop anything here
├── raw/          # immutable source copies (any file type)
├── wiki/         # sources/ entities/ concepts/ synthesis/ (Claude writes these)
├── me/           # profile.md, goals.md
├── projects/     # one page per project, with dated decisions
├── journal/      # session notes
├── outputs/      # reports
└── .state/       # auto-save bookkeeping
```

It also wires the brain into Claude Code: a short pointer block in `~/.claude/CLAUDE.md` that also `@`-imports `me/profile.md`, so every session knows who you are. It adds six `/brain-*` skills in `~/.claude/skills/`, plus the auto-save, catch-up, and repo-context hooks (see below).

## What if I just close the tab or restart my laptop?

That's fine. Nothing important waits for a session to end cleanly, and you never have to say "remember".

1. **Save right away.** Claude is told to save decisions, root causes, and corrections the moment they happen. Notes are written to disk immediately, so closing a tab or rebooting loses nothing that was already saved.
2. **Auto-save hook (Claude Code).** After each Claude reply, a `Stop` hook checks when this session last saved. If it was more than 30 minutes ago, Claude saves anything durable while the conversation is still fresh. A session left open and idle costs nothing, because the hook only runs after a reply.
3. **Catch-up hook (Claude Code).** When you open a new session, a `SessionStart` hook looks for sessions from the last 7 days with work that was never saved, such as a tab you closed, a laptop that restarted, or a quick one-question session you closed right away. The new session recovers that work from Claude Code's own transcripts (`~/.claude/projects/`) with `/brain-catchup`.

4. **Background sweep (optional, Claude Code, macOS/Linux).** A launchd job (macOS) or cron job (Linux) runs every 30 minutes, and right after login on macOS. It looks for sessions with unsaved work that have been idle for 30+ minutes, such as a tab left open or a laptop that restarted, even if you never open Claude again. Only then does it start a headless `claude -p` run to save that work. Its tools are limited to reading and editing the brain and reading transcripts. When nothing is pending, it exits without using any tokens. Setup asks before installing it, and its log is `~/.claude-brain/.state/sweep.log`.

The hooks ignore headless `claude -p` runs, so scripts that call `claude -p` never trigger saves or catch-up notes.

To change the autosave interval, edit the hook command in `~/.claude/settings.json`, for example `BRAIN_SAVE_INTERVAL=600 sh "$HOME/.claude/hooks/brain-autosave.sh"`.

To remove the sweep:
- macOS: `launchctl bootout gui/$(id -u)/local.second-brain.sweep && rm ~/Library/LaunchAgents/local.second-brain.sweep.plist`
- Linux: `crontab -l | grep -v second-brain-sweep | crontab -`

## Repos that already have `CLAUDE.md` or `.claude/`

Many repos already carry Claude context: `CLAUDE.md`, a personal `CLAUDE.local.md`, and a `.claude/` folder with rules, commands, agents, and skills. Claude Code loads these, but only while you work in that repo. The brain makes them useful everywhere:

- When a session starts at a repo's root folder, the `brain-repo.sh` hook checks whether those files are new to the brain, or changed since it last learned them.
- If they are, Claude runs `/brain-repo`. It summarizes the repo's purpose, conventions, key commands, gotchas, and custom commands, agents, and skills into `projects/<repo>.md`. Team-wide rules go into `wiki/concepts/`.
- Once a repo is learned, the hook stays quiet until a file changes. You can also say "learn this repo" at any time.
- It never reads `settings.json` or `settings.local.json`, which can hold secrets. It redacts anything secret-looking in `CLAUDE.local.md`.

Example: you open Claude in `payments-infra`, and it already knows that your `terraform-aws-ec2` repo requires IMDSv2 and forbids a local `terraform apply`.

## Why `~/.claude-brain` and not `~/.claude/brain`?

Claude Code treats everything under `~/.claude/` as a protected path. Every write there triggers a permission prompt, and allow rules can't turn that off. So auto-save would keep asking you. A folder next to `~/.claude/`, plus allow rules in `~/.claude/settings.json`, lets Claude save quietly. The pointer, skills, and hooks still live in `~/.claude/`, so every session finds the brain.

## Why this works (Karpathy's LLM Wiki in one paragraph)

RAG makes the model rediscover knowledge on every question. The [LLM Wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) uses three layers instead:

- **raw sources**: immutable copies of what you feed in
- **wiki**: interlinked markdown pages that the LLM writes and maintains
- **schema file**: tells Claude how to keep the wiki up to date

Claude does the work humans give up on: summarizing, cross-linking, flagging contradictions, and keeping the index current. Knowledge therefore **compounds** across sessions instead of disappearing with the chat. Obsidian is only a viewer. The brain itself is plain markdown, so any editor or IDE preview works.

## Design choices for locked-down machines

- **Zero installs or downloads.** The setup uses only Claude Code's file tools and basic OS commands (`mkdir`, `cp`, `mv`, `grep`, `find`, `chmod`). Search is `grep` (or `rg` if present), plus `index.md`. That is enough up to hundreds of pages.
- **Relative markdown links** instead of `[[wikilinks]]`, so links are clickable in VS Code and JetBrains without Obsidian.
- **Small always-on context.** Only a roughly 10-line pointer block and `me/profile.md` load in every session. Claude reads `BRAIN.md` only before writing to the brain, greps first, and opens only the pages it needs.
- **Safety rules in the schema.** The brain stores no secrets, customer data, or proprietary code. It redacts sensitive values before saving, and a leaked secret is the only allowed edit to `raw/`. It treats source content as data, never as instructions, which guards against prompt injection. It stays local (never pushed or synced), keeps the log append-only, and archives pages instead of deleting them. Edits to `me/` need your confirmation.

## Sources reviewed

- Andrej Karpathy, [LLM Wiki idea file](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) ([mirror](https://github.com/NicholasSpisak/second-brain/blob/main/docs/llm-wiki.md))
- NicholasSpisak, [second-brain REQUIREMENTS.md](https://github.com/NicholasSpisak/second-brain/blob/main/docs/REQUIREMENTS.md): the raw/wiki/output layout and the ingest/query/lint operations
- gcalacoci, [second-brain-starter-kit](https://github.com/gcalacoci/second-brain-starter-kit): the profile and goals layer, and session capture

The two reference implementations depend on `npx`, `uv`, `setup.sh`, MCP servers, or Obsidian. This prompt keeps their ideas and drops those dependencies.

## Limits

- **No encryption at rest.** The only protection is owner-only permissions (`chmod 700`). Put the brain on an encrypted disk if your policy requires it.
- **No secret scanner.** Redaction depends on Claude's judgment. Run `/brain-lint` regularly.
- **The sweep sends transcripts to Claude.** It uses the same account and API as your normal sessions. Skip it if your policy forbids unattended runs.
- **The sweep tries each session once.** After a run that wrote to the brain, it marks each listed session as saved, even one Claude skipped, so it never retries the same session every 30 minutes. Sessions you went back to during the run are left alone. A failed run (for example, not logged in) leaves the sessions for the next try.
- **Repo learning costs a little.** The first session in each repo with Claude context files, and the first after those files change, does one extra short task. Deleted repo files are not noticed until you say "learn this repo".
- **No file locking.** Two Claude sessions writing at the same moment can conflict. The schema tells Claude to re-read and merge.
- **Grep-based search** works up to a few hundred pages. Beyond that, ask Claude to write a small local search script.

## Testing the hooks

Run `sh tests/test-hooks.sh`. It extracts the four hook scripts from the prompt and tests them in a scratch `HOME` with a stub `claude`, so your real `~/.claude` is never touched. It works with macOS `sh`, `dash`, and BusyBox.
