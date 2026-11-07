#!/usr/bin/env bash
# Evidence driver for the cmux 0.65.2 post-create workspace-lookup race.
# Drives the REAL adapter (bin/backends/cmux.sh) against a fake `cmux` CLI that
# reproduces 0.65.2's documented behavior: `new-workspace` returns before the
# new workspace appears in `workspace list`. No real cmux app or socket is used.
set -u
REPO=${1:?repo root}
LAB=$(mktemp -d "${TMPDIR:-/tmp}/cmux-retry.XXXXXX")
trap 'rm -rf "$LAB"' EXIT
mkdir -p "$LAB/bin" "$LAB/state"

cat > "$LAB/bin/cmux" <<'SH'
#!/usr/bin/env bash
set -u
state=$FM_FAKE_STATE
printf '%s\n' "$*" >> "$state/log"
case "${1:-}" in
  version) printf 'cmux 0.65.2 (99) [abcdef1]\n'; exit 0 ;;
  ping) printf 'PONG\n'; exit 0 ;;
  workspace)
    # `workspace list --json --id-format uuids`
    if [ "$(cat "$state/created" 2>/dev/null || echo 0)" = 0 ]; then
      printf '{"workspaces":[]}\n'; exit 0
    fi
    hidden=$(cat "$state/hidden" 2>/dev/null || echo 0)
    if [ "$hidden" -gt 0 ]; then
      echo $((hidden - 1)) > "$state/hidden"
      printf '{"workspaces":[]}\n'          # 0.65.2 lag: created but not listed yet
      exit 0
    fi
    printf '{"workspaces":[{"id":"%s","title":"%s"}]}\n' \
      "$(cat "$state/wsid")" "$(cat "$state/title")"
    exit 0
    ;;
  new-workspace)
    echo 0 > "$state/hidden"     # reset, set below from env
    echo "${FM_FAKE_HIDE:-0}" > "$state/hidden"
    echo 1 > "$state/created"
    shift
    while [ $# -gt 0 ]; do
      case "$1" in --name) echo "$2" > "$state/title"; shift 2 ;; *) shift ;; esac
    done
    exit 0
    ;;
  list-panes)
    printf '{"panes":[{"selected_surface_id":"%s","surface_ids":["%s"]}]}\n' \
      "$(cat "$state/sfid")" "$(cat "$state/sfid")"
    exit 0
    ;;
esac
exit 1
SH
chmod +x "$LAB/bin/cmux"

run_case() {  # <name> <hidden-lookups> [adapter-path]
  local name=$1 hide=$2 adapter=${3:-} start end out rc
  rm -f "$LAB/state/log" "$LAB/state/created" "$LAB/state/hidden"
  echo 'bbbbbbbb-1111-1111-1111-111111111111' > "$LAB/state/wsid"
  echo 'cccccccc-2222-2222-2222-222222222222' > "$LAB/state/sfid"
  start=$(python3 -c 'import time;print(time.time())')
  out=$(FM_FAKE_STATE="$LAB/state" FM_FAKE_HIDE="$hide" PATH="$LAB/bin:$PATH" \
    bash -c '. "$1"; fm_backend_cmux_create_task fm-race /tmp/proj' _ "${adapter:-$REPO/bin/backends/cmux.sh}" 2>&1)
  rc=$?
  end=$(python3 -c 'import time;print(time.time())')
  echo "=== case: $name (new workspace hidden from $hide immediate list lookups)"
  echo "exit=$rc"
  echo "stdout+stderr: $out"
  echo "elapsed_ms=$(python3 -c "print(round(($end-$start)*1000))")"
  echo "workspace-list calls: $(grep -c '^workspace list' "$LAB/state/log")"
  echo "new-workspace calls: $(grep -c '^new-workspace' "$LAB/state/log")"
  echo "list-panes calls: $(grep -c '^list-panes' "$LAB/state/log")"
  echo
}

PREFIX_ADAPTER=${PREFIX_ADAPTER:-}
run_case "race: workspace becomes visible after 3 lagging lookups" 3
run_case "adversarial: workspace never becomes visible (bounded, no hang)" 999
run_case "control: pre-fix adapter with one immediate lookup, same 3-lookup lag" 3 "$PREFIX_ADAPTER"
