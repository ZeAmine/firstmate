#!/usr/bin/env bash
# Product-level transcript of the T3 contribution: drives the real
# bin/fm-t3-mcp.mjs CLI over the real MCP streamable-HTTP transport against the
# disposable tests/t3-fake-server.mjs (synthetic T3 0.1.3 compact catalog and
# T3 0.1.0 legacy catalog). No real T3 credential, server, or personal account
# is used.
set -u
REPO=${1:?repo root}
# shellcheck source=tests/lib.sh
. "$REPO/tests/lib.sh"
# shellcheck source=tests/t3-fake-lib.sh
. "$REPO/tests/t3-fake-lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-t3-transcript)
trap 't3_fake_stop; fm_test_cleanup' EXIT
CRED="$TMP_ROOT/config/t3code-token"
WT="$TMP_ROOT/worktree"
mkdir -p "$WT" "$TMP_ROOT/proj"

field() { node -e 'const d=JSON.parse(process.argv[1]); const v=process.argv[2].split(".").reduce((o,k)=>o==null?o:o[k], d); process.stdout.write(v==null?"":typeof v==="object"?JSON.stringify(v):String(v))' "$1" "$2"; }

mcp() {
  echo "\$ fm-t3-mcp $*"
  OUT=$(node "$REPO/bin/fm-t3-mcp.mjs" "$@" --token-file "$CRED" 2>"$TMP_ROOT/err"); RC=$?
  ERR=$(cat "$TMP_ROOT/err")
  echo "  exit=$RC"
  [ -s "$TMP_ROOT/err" ] && sed 's/^/  stderr: /' "$TMP_ROOT/err"
  [ -n "$OUT" ] && printf '  %s\n' "$OUT"
}

t3_fake_start "$TMP_ROOT/server"
t3_fake_case "$TMP_ROOT/cases/main"
t3_fake_credential "$CRED"

echo '=== T3 0.1.3 (merged t3_thread_configure + t3_pending_request, compact catalog with omittedModels)'
t3_fake_set 'w.omitModels = ["claude-sonnet-5"]'
t3_fake_set 'w.threads = { "thread-q": { threadId: "thread-q", projectId: "p", status: "running", activeRunId: "run-q", archived: false, worktreePath: null, items: [],
  runs: [{ runId: "run-q", ordinal: 1, status: "running" }],
  runtimeRequests: [{ id: "req-question", kind: "user_input", status: "pending", questions: [{ id: "q1", header: "Pick", question: "Which?" }] }] } }'
mcp status
mcp project-ensure --root "$TMP_ROOT/proj"
project=$(field "$OUT" projectId)
FM_T3_ID="$project" t3_fake_set 'w.projects.find((p) => p.id === process.env.FM_T3_ID).defaultModelSelection = { instanceId: "claudeAgent", model: "claude-sonnet-5", options: [{ id: "fastMode", value: true }] }'
mcp resolve-selection --harness claude --instance claudeAgent --model default --effort high --project "$project"
mcp launch --project "$project" --title probe --model-selection '{"instanceId":"claudeAgent","model":"claude-sonnet-5","options":[{"id":"effort","value":"high"}]}' --worktree "$WT"
mcp requests --thread thread-q
printf '{"q1":"a"}' > "$TMP_ROOT/answers"
mcp respond --thread thread-q --request req-question --answers-file "$TMP_ROOT/answers"
echo '  -- server saw configuration/answer tools:'
echo "  t3_thread_configure: $(t3_fake_calls t3_thread_configure | tr '\n' ' ')"
echo "  t3_pending_request actions: $(t3_fake_calls t3_pending_request | node -e 'process.stdout.write(require("fs").readFileSync(0,"utf8").trim().split("\n").filter(Boolean).map((l)=>JSON.parse(l).action).join(" "))')"
echo "  search for omitted model: $(t3_fake_calls orchestrator_capabilities | grep -c '"search":"claude-sonnet-5"') capability call(s)"
echo

echo '=== refusals the compact catalog must enforce'
mcp resolve-selection --harness claude --instance claudeAgent --model claude-haiku-5-5 --effort ultra --project "$project"
mcp resolve-selection --harness claude --instance claudeAgent --model claude-none --effort default --project "$project"
echo

echo '=== T3 0.1.0 legacy world (typed type/options catalog, separate pending-request tools)'
t3_fake_set 'w.legacy = true'
t3_fake_set 'w.threads["thread-q"].runtimeRequests = [{ id: "req-question", kind: "user_input", status: "pending", questions: [{ id: "q1", header: "Pick", question: "Which?" }] }]'
mcp status
mcp launch --project "$project" --title legacy-probe --model-selection '{"instanceId":"claudeAgent","model":"claude-sonnet-5","options":[{"id":"effort","value":"high"}]}' --worktree "$WT"
mcp requests --thread thread-q
mcp respond --thread thread-q --request req-question --answers-file "$TMP_ROOT/answers"
mcp resolve-selection --harness claude --instance claudeAgent --model claude-sonnet-5 --effort high --project "$project"
echo '  -- server saw legacy tools:'
echo "  t3_thread_configuration: $(t3_fake_calls t3_thread_configuration | tr '\n' ' ')"
echo "  t3_pending_request_respond answers: $(t3_fake_calls t3_pending_request_respond)"
