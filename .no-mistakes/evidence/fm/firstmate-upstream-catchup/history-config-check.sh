#!/usr/bin/env bash
# Evidence driver for the private upstream catch-up:
#  - the local cmux repair, the audited upstream head and every T3 commit stay ancestors of HEAD
#  - the cmux adapter blob is byte-identical to the local repair commit
#  - personal configuration paths stay git-ignored for the real git consumer
#  - the future private main can still advance by fast-forward from 60099843 with the
#    REAL install command (git merge --ff-only) in a disposable clone
set -u
REPO=${1:?repo root}
LAB=$(mktemp -d "${TMPDIR:-/tmp}/history-check.XXXXXX")
trap 'rm -rf "$LAB"' EXIT
GIT_IDENT=(-c user.email=evidence@example.invalid -c user.name=evidence)

echo "=== required ancestors of $(git -C "$REPO" rev-parse --short HEAD)"
failed=0
for c in 60099843e469d84bcd2465d97635dfedfe200d6a \
         bf05a4fcd69b8bb27f261177eac4abb57f98aa1b \
         b144b6db38ec51cfd07c019ed1fe82cd14dccba8 \
         fb2fc28784aa6e0a347f054175d884b509dd4caa \
         08eea7268cc3cb2f955ab9215617b6f135a0a341 \
         62030a560e87d7640b4e26118f1f1de1e17277a6; do
  if git -C "$REPO" merge-base --is-ancestor "$c" HEAD; then
    printf 'ancestor OK  %s  %s\n' "$c" "$(git -C "$REPO" log -1 --format=%s "$c")"
  else
    printf 'ancestor MISSING  %s\n' "$c"
    failed=1
  fi
done

echo
echo "=== cmux adapter blob at 60099843 vs HEAD"
before=$(git -C "$REPO" rev-parse 60099843e469d84bcd2465d97635dfedfe200d6a:bin/backends/cmux.sh)
after=$(git -C "$REPO" rev-parse HEAD:bin/backends/cmux.sh)
printf '60099843: %s\nHEAD    : %s\n' "$before" "$after"
if [ "$before" = "$after" ]; then echo 'cmux blob IDENTICAL'; else echo 'cmux blob CHANGED'; failed=1; fi

echo
echo "=== personal configuration paths stay ignored (real git consumer: git check-ignore)"
for p in .env config/tools.json data/report.md state/afk projects/foo .no-mistakes/run; do
  if out=$(git -C "$REPO" check-ignore -v --no-index "$p"); then
    printf '%-24s -> %s\n' "$p" "$out"
  else
    printf '%-24s -> NOT IGNORED\n' "$p"
    failed=1
  fi
done

echo
echo "=== fast-forward install path in a disposable clone (real git consumer)"
git clone -q --local --no-hardlinks "$REPO" "$LAB/clone" || { echo 'clone failed'; exit 1; }
git -C "$LAB/clone" "${GIT_IDENT[@]}" checkout -q -B main 60099843e469d84bcd2465d97635dfedfe200d6a
printf 'start: %s\n' "$(git -C "$LAB/clone" rev-parse --short HEAD)"
git -C "$LAB/clone" "${GIT_IDENT[@]}" merge --ff-only -q HEAD@{upstream} >/dev/null 2>&1 \
  || git -C "$LAB/clone" "${GIT_IDENT[@]}" merge --ff-only -q "$(git -C "$REPO" rev-parse HEAD)" \
  || { echo 'merge --ff-only FAILED'; exit 1; }
printf 'after: %s\n' "$(git -C "$LAB/clone" rev-parse --short HEAD)"
if git -C "$LAB/clone" merge-base --is-ancestor 60099843e469d84bcd2465d97635dfedfe200d6a HEAD; then
  echo 'fast-forward to the validated head SUCCEEDED (60099843 remains an ancestor)'
else
  echo 'fast-forward broke ancestry'
  failed=1
fi
exit "$failed"
