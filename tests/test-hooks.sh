#!/bin/sh
# Tests for the hook scripts embedded in SECOND-BRAIN-PROMPT.md.
# Usage: sh tests/test-hooks.sh            (extracts the scripts from the prompt)
#        sh tests/test-hooks.sh <dir>      (tests brain-*.sh files in <dir>)
# Runs in a scratch HOME with a stub `claude`; never touches your real ~/.claude.
# Works with macOS sh, dash, bash --posix, and BusyBox.
if [ -z "$1" ]; then
  S=$(mktemp -d /tmp/brain-scripts.XXXXXX)
  awk -v out="$S" '
  /^`~\/\.claude\/hooks\/brain-[a-z]+\.sh`:$/ {name=$0; gsub(/[`:]/,"",name); sub(/.*\//,"",name); want=1; next}
  /^2\. If `~\/\.claude\/hooks\/brain-sweep\.sh`/ {name="brain-sweep.sh"; want=1; next}
  want && /^ *```sh$/ {on=1; want=0; ind=match($0,/`/)-1; f=out "/" name; printf "" > f; next}
  on && /^ *```$/ {on=0; close(f); next}
  on {print substr($0, ind+1) >> f}' "$(dirname "$0")/../SECOND-BRAIN-PROMPT.md"
  [ "$(ls "$S"/brain-*.sh | wc -l)" -eq 4 ] || { echo "FAIL could not extract 4 scripts"; exit 1; }
  for f in "$S"/brain-*.sh; do sh -n "$f" || { echo "FAIL syntax $f"; exit 1; }; done
  set -- "$S"; CLEAN="$S"
fi
S="$1"
export HOME=$(mktemp -d /tmp/sbqhome.XXXXXX)
mkdir -p "$HOME/.claude-brain/.state" "$HOME/.claude/hooks" "$HOME/t"
cp "$S"/brain-*.sh "$HOME/.claude/hooks/"
ST="$HOME/.claude-brain/.state"
pass=0; fail=0
ok() { pass=$((pass+1)); echo "PASS $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
ago() { e=$(( $(date +%s) - $1 )); date -d "@$e" +%Y%m%d%H%M.%S 2>/dev/null || date -r "$e" +%Y%m%d%H%M.%S; }
AS="$HOME/.claude/hooks/brain-autosave.sh"; CU="$HOME/.claude/hooks/brain-catchup.sh"
RP="$HOME/.claude/hooks/brain-repo.sh"; SW="$HOME/.claude/hooks/brain-sweep.sh"

# --- autosave
T="$HOME/t/s1.jsonl"; echo '{}' > "$T"
in1="{\"session_id\":\"s1\",\"transcript_path\":\"$T\",\"stop_hook_active\":false}"
out=$(printf '%s' "$in1" | BRAIN_SAVE_INTERVAL=0 sh "$AS")
check "autosave first turn silent" '[ -z "$out" ]'
check "autosave first turn never-saved" 'grep -q "^never-saved$" "$ST/s1.saved"'
out=$(printf '%s' "$in1" | sh "$AS")
check "autosave under interval silent" '[ -z "$out" ]'
out=$(printf '%s' "$in1" | BRAIN_SAVE_INTERVAL=0 sh "$AS")
check "autosave over interval blocks" 'printf "%s" "$out" | grep -q "\"decision\":\"block\""'
in2="{\"session_id\":\"s1\",\"transcript_path\":\"$T\",\"stop_hook_active\":true}"
out=$(printf '%s' "$in2" | BRAIN_SAVE_INTERVAL=0 sh "$AS")
check "autosave continuation silent" '[ -z "$out" ]'
check "autosave continuation clears never-saved" '! grep -q never-saved "$ST/s1.saved"'
check "autosave marker line 1 = transcript" '[ "$(head -n 1 "$ST/s1.saved")" = "$T" ]'
# another Stop hook blocks on the very first turn: must not count as saved
T2="$HOME/t/s2.jsonl"; echo '{}' > "$T2"
printf '{"session_id":"s2","transcript_path":"%s","stop_hook_active":true}' "$T2" | sh "$AS" >/dev/null
check "foreign block on first turn keeps never-saved" 'grep -q "^never-saved$" "$ST/s2.saved" 2>/dev/null'
# another Stop hook blocks later: must not reset the save clock
printf '{"session_id":"s2","transcript_path":"%s","stop_hook_active":false}' "$T2" | sh "$AS" >/dev/null
touch -t "$(ago 4000)" "$ST/s2.saved"
printf '{"session_id":"s2","transcript_path":"%s","stop_hook_active":true}' "$T2" | sh "$AS" >/dev/null
m=$(date -r "$ST/s2.saved" +%s 2>/dev/null || stat -c %Y "$ST/s2.saved")
check "foreign block later keeps old save time" '[ $(( $(date +%s) - m )) -ge 3900 ]'
check "autosave sweep env no-op" '[ -z "$(printf "%s" "$in1" | BRAIN_SWEEP=1 BRAIN_SAVE_INTERVAL=0 sh "$AS")" ]'
check "autosave claude -p no-op" '[ -z "$(printf "%s" "$in1" | CLAUDE_CODE_ENTRYPOINT=sdk-cli BRAIN_SAVE_INTERVAL=0 sh "$AS")" ]'
# interrupted save: block asked, tab closed before the save turn finished
T3="$HOME/t/s3.jsonl"; echo '{}' > "$T3"
in3="{\"session_id\":\"s3\",\"transcript_path\":\"$T3\",\"stop_hook_active\":false}"
printf '%s' "$in3" | sh "$AS" >/dev/null; touch -t "$(ago 4000)" "$ST/s3.saved"
out=$(printf '%s' "$in3" | sh "$AS")
check "interrupted save: blocked" 'printf "%s" "$out" | grep -q block'
check "interrupted save: keeps never-saved + asked" 'grep -q "^never-saved$" "$ST/s3.saved" && grep -q "^asked$" "$ST/s3.saved"'
m=$(date -r "$ST/s3.saved" +%s 2>/dev/null || stat -c %Y "$ST/s3.saved")
check "interrupted save: keeps old save time" '[ $(( $(date +%s) - m )) -ge 3900 ]'
check "interrupted save: asks again next turn" 'printf "%s" "$in3" | sh "$AS" | grep -q block'
check "interrupted save: asked flag not duplicated" '[ "$(grep -c "^asked$" "$ST/s3.saved")" = 1 ]'
touch "$T3"; out=$(printf '{"session_id":"other"}' | sh "$CU")
check "interrupted save: catch-up lists it from session start" 'printf "%s" "$out" | grep -q "session s3, unsaved since session start"'
printf '{"session_id":"s3","transcript_path":"%s","stop_hook_active":true}' "$T3" | sh "$AS" >/dev/null
check "save turn done: flags cleared" '! grep -Eq "^(asked|never-saved)$" "$ST/s3.saved"'
check "autosave no brain dir: no-op" 'H2=$(mktemp -d); [ -z "$(printf "%s" "$in1" | HOME=$H2 sh "$AS")" ] && [ ! -e "$H2/.claude-brain" ]; r=$?; rm -rf "$H2"; [ $r = 0 ]'
rm -f "$ST"/*.saved

# --- catchup
mk() { # sid transcript_age marker_age never
  echo '{}' > "$HOME/t/$1.jsonl"
  if [ "$4" = never ]; then printf '%s\nnever-saved\n' "$HOME/t/$1.jsonl" > "$ST/$1.saved"
  else printf '%s\n' "$HOME/t/$1.jsonl" > "$ST/$1.saved"; fi
  touch -t "$(ago "$2")" "$HOME/t/$1.jsonl"; touch -t "$(ago "$3")" "$ST/$1.saved"; }
mk saved 100 50 ""          # saved after last activity
mk grace 100 200 ""         # activity within grace
mk unsaved 100 4000 ""      # activity long after save
mk short 100 150 never      # short session never saved
mk cur 100 4000 ""          # the current session
out=$(printf '{"session_id":"cur"}' | sh "$CU")
check "catchup lists unsaved" 'printf "%s" "$out" | grep -q "session unsaved, unsaved since .*(UTC)"'
check "catchup lists never-saved short" 'printf "%s" "$out" | grep -q "session short, unsaved since session start"'
check "catchup skips saved/grace/current" '! printf "%s" "$out" | grep -Eq "session (saved|grace|cur),"'
check "catchup count 2" 'printf "%s" "$out" | grep -q "^Brain catch-up: 2 earlier"'
out=$(printf '{"session_id":"cur"}' | BRAIN_MIN_IDLE=1800 sh "$CU")
check "catchup MIN_IDLE skips recent" '[ -z "$out" ]'
check "catchup sweep env no-op" '[ -z "$(printf "{}" | BRAIN_SWEEP=1 sh "$CU")" ]'
check "catchup claude -p no-op" '[ -z "$(printf "{}" | CLAUDE_CODE_ENTRYPOINT=sdk-cli sh "$CU")" ]'
rm -f "$ST"/*.saved

# --- repo
R="$HOME/work/repo"; mkdir -p "$R/.git" "$R/sub" "$R/.claude/rules"; echo x > "$R/CLAUDE.md"; echo y > "$R/.claude/rules/a.md"
out=$(printf '{"cwd":"%s"}' "$R" | sh "$RP")
check "repo root note" 'printf "%s" "$out" | grep -q "^Brain repo context: this repo ($R)"'
check "repo lists rule file" 'printf "%s" "$out" | grep -q "^- .claude/rules/a.md$"'
mk_marker=$(printf '%s' "$out" | sed -n 's/.*only line of \(.*\)\. Keep it brief\./\1/p')
check "repo marker dir exists" '[ -d "$(dirname "$mk_marker")" ]'
touch -t "$(ago 600)" "$R/CLAUDE.md" "$R/.claude/rules/a.md"; date > "$mk_marker"
check "repo quiet after learned" '[ -z "$(printf "{\"cwd\":\"%s\"}" "$R" | sh "$RP")" ]'
echo z >> "$R/CLAUDE.md"; touch "$R/CLAUDE.md"; touch -t "$(ago 60)" "$mk_marker"
check "repo note after change" '[ -n "$(printf "{\"cwd\":\"%s\"}" "$R" | sh "$RP")" ]'
check "repo subfolder quiet" '[ -z "$(printf "{\"cwd\":\"%s\"}" "$R/sub" | sh "$RP")" ]'
check "repo home quiet" '[ -z "$(printf "{\"cwd\":\"%s\"}" "$HOME" | sh "$RP")" ]'
check "repo claude -p no-op" '[ -z "$(printf "{\"cwd\":\"%s\"}" "$R" | CLAUDE_CODE_ENTRYPOINT=sdk-cli sh "$RP")" ]'
mkdir -p "$HOME/empty/.git"
check "repo without files quiet" '[ -z "$(printf "{\"cwd\":\"%s\"}" "$HOME/empty" | sh "$RP")" ]'

# --- sweep with stub claude
mkdir -p "$HOME/bin"; cat > "$HOME/bin/claude" <<'EOF'
#!/bin/sh
echo "CALLED BRAIN_SWEEP=$BRAIN_SWEEP pwd=$(pwd)" >> "$HOME/stub.log"
for a in "$@"; do echo "ARG $a" >> "$HOME/stub.log"; done
[ -n "$STUB_TOUCH" ] && sleep 1 && touch "$STUB_TOUCH"
[ -n "$STUB_WRITE" ] && sleep 1 && echo "## [x] remember | stub" >> "$HOME/.claude-brain/log.md"
exit ${STUB_EXIT:-0}
EOF
chmod +x "$HOME/bin/claude"
PATH="$HOME/bin:$PATH" sh "$SW"
check "sweep nothing pending: no call" '[ ! -f "$HOME/stub.log" ]'
mk idle 4000 8000 ""; mk busy 60 8000 ""
STUB_WRITE=1 PATH="$HOME/bin:$PATH" sh "$SW"
check "sweep calls claude once" '[ "$(grep -c ^CALLED "$HOME/stub.log")" = 1 ]'
check "sweep sets BRAIN_SWEEP, cwd brain" 'grep -q "^CALLED BRAIN_SWEEP=1 pwd=.*/.claude-brain$" "$HOME/stub.log"'
check "sweep note drops interactive-only line" '! grep -q "In the same reply" "$HOME/stub.log"'
check "sweep note has idle, not busy" 'grep -q "session idle," "$HOME/stub.log" && ! grep -q "session busy," "$HOME/stub.log"'
check "sweep lock released" '[ ! -d "$ST/sweep.lock" ]'
check "sweep log line" 'grep -q "sweep: 1 session(s)" "$ST/sweep.log"'
check "sweep marks skipped session after success" '[ "$ST/idle.saved" -nt "$HOME/t/idle.jsonl" ] && ! grep -q never "$ST/idle.saved"'
check "sweep leaves busy session alone" '! [ "$ST/busy.saved" -nt "$HOME/t/busy.jsonl" ]'
check "sweep second run: nothing pending" 'rm -f "$HOME/stub.log"; PATH="$HOME/bin:$PATH" sh "$SW"; [ ! -f "$HOME/stub.log" ]'
mk nowrite 4000 8000 never
PATH="$HOME/bin:$PATH" sh "$SW"
check "sweep exit 0 without brain write keeps session pending" 'grep -q "^never-saved$" "$ST/nowrite.saved"'
rm -f "$ST/nowrite.saved"
mk fail1 4000 8000 never
STUB_WRITE=1 STUB_EXIT=1 PATH="$HOME/bin:$PATH" sh "$SW"
check "sweep failure keeps session pending" 'grep -q "^never-saved$" "$ST/fail1.saved"'
rm -f "$ST/fail1.saved"
mk back 4000 8000 never
STUB_WRITE=1 STUB_TOUCH="$HOME/t/back.jsonl" PATH="$HOME/bin:$PATH" sh "$SW"
check "sweep: session reopened during run stays pending" 'grep -q "^never-saved$" "$ST/back.saved"'
rm -f "$ST/back.saved"
mk idle2 4000 8000 ""; mkdir "$ST/sweep.lock"; rm -f "$HOME/stub.log"
PATH="$HOME/bin:$PATH" sh "$SW"
check "sweep respects fresh lock" '[ ! -f "$HOME/stub.log" ]'
touch -t "$(ago 4000)" "$ST/sweep.lock"
PATH="$HOME/bin:$PATH" sh "$SW"
check "sweep breaks stale lock" '[ -f "$HOME/stub.log" ] && [ ! -d "$ST/sweep.lock" ]'

echo "RESULT pass=$pass fail=$fail"
rm -rf "$HOME" ${CLEAN:+"$CLEAN"}
[ "$fail" = 0 ]
