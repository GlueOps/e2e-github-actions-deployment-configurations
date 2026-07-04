#!/usr/bin/env bash
# Event-driven full-flow orchestration + assertions. Drives the REAL production cascade
# (release -> on:release bump -> deploy PR -> on:pull_request cleanup) and proves the parts
# the synchronous e2e.yml can't. See full-flow.yml for the diagram and the token rationale.
#
# Env: GH_TOKEN  MUST be an App-installation token (its events trigger workflows;
#                GITHUB_TOKEN's do not — the whole cascade hinges on this).
#      REPO      owner/name.
#      TAG1,TAG2 two distinct, already-valid container tags (lowercase [a-z0-9-]) so bump's
#                sanitizeTag is identity and each deploy PR's marker tag == the release tag.
set -euo pipefail

APP=flow-app
ENVX=prod
VALUES="apps/$APP/envs/$ENVX/values.yaml"
HERE="$(cd "$(dirname "$0")" && pwd)"

: "${GH_TOKEN:?}"; : "${REPO:?}"; : "${TAG1:?}"; : "${TAG2:?}"

pr_body()   { gh api "repos/$REPO/pulls/$1" --jq '.body // ""'; }
pr_state()  { gh api "repos/$REPO/pulls/$1" --jq '.state'; }
pr_branch() { gh api "repos/$REPO/pulls/$1" --jq '.head.ref'; }

# Echo the open flow-app/prod deploy PR whose marker tag == $1, or return 1.
find_pr() {
  local want="glueops-deploy:{\"app\":\"$APP\",\"env\":\"$ENVX\",\"tag\":\"$1\"}" pr
  for pr in $(gh api "repos/$REPO/pulls?state=open&per_page=100" --jq '.[].number'); do
    if pr_body "$pr" | grep -qF "$want"; then echo "$pr"; return 0; fi
  done
  return 1
}

# Poll up to 5 min (30 x 10s) for a condition; args: <description> <fn> [fn-args...].
# The fn must echo a result on success (captured + echoed here) and return 0.
wait_for() {
  local desc="$1"; shift
  local out
  for _ in $(seq 1 30); do
    if out=$("$@" 2>/dev/null); then echo "$out"; return 0; fi
    sleep 10
  done
  echo "TIMEOUT waiting for: $desc" >&2
  return 1
}

create_release() {
  gh api -X POST "repos/$REPO/releases" \
    -f tag_name="$1" -f name="$1" -f target_commitish=main \
    -F prerelease=true -f body="full-flow e2e synthetic release (safe to delete)" \
    --jq '.id' >/dev/null
  echo "created release $1"
}

assert_values() { # <branch> <tag>
  local file
  file=$(gh api "repos/$REPO/contents/$VALUES?ref=$1" --jq '.content' | base64 -d)
  printf '%s' "$file" | grep -Eq "tag:[[:space:]]*[\"']?$2[\"']?" \
    || { echo "❌ image.tag was not updated to $2 on $1"; exit 1; }
  printf '%s' "$file" | grep -q 'flow-sentinel-comment' \
    || { echo "❌ comment was NOT preserved by the YAML edit on $1"; exit 1; }
}

branch_exists() { gh api "repos/$REPO/git/ref/heads/$1" >/dev/null 2>&1; }

echo "== full flow: TAG1=$TAG1  TAG2=$TAG2 =="
bash "$HERE/full-flow-teardown.sh"   # clean slate

# ── Release #1 → on:release bump opens the first deploy PR ────────────────────────────
create_release "$TAG1"
PR1=$(wait_for "deploy PR for $TAG1 (on:release bump)" find_pr "$TAG1") \
  || { echo "❌ bump never opened a deploy PR — the release did not trigger full-flow-bump"; exit 1; }
BR1=$(pr_branch "$PR1")
echo "✅ bump opened deploy PR #$PR1 (branch $BR1)"
# The marker tag equals the release name — so bump took the release-name path, NOT the
# sha[:7] fallback that every schedule/dispatch run of e2e.yml is stuck with.
echo "✅ tag computed from the release name (not the sha fallback): $TAG1"
assert_values "$BR1" "$TAG1"
echo "✅ values.yaml on #$PR1 has image.tag=$TAG1 with its comment preserved"

# ── Release #2 → a newer deploy PR, whose `pull_request` event drives cleanup ─────────
create_release "$TAG2"
PR2=$(wait_for "deploy PR for $TAG2 (on:release bump)" find_pr "$TAG2") \
  || { echo "❌ second release did not open a deploy PR"; exit 1; }
BR2=$(pr_branch "$PR2")
[ "$PR2" != "$PR1" ] || { echo "❌ second release reused PR #$PR1 instead of opening a new one"; exit 1; }
[ "$PR2" -gt "$PR1" ] || { echo "❌ PR #$PR2 is not newer than #$PR1 — supersession can't apply"; exit 1; }
echo "✅ second deploy PR #$PR2 (branch $BR2)"

# The core proof: NOTHING in this script closes PR1. Only full-flow-cleanup, fired by the
# real `pull_request` event on PR2, can — via the App-token-triggers-workflows property.
echo "waiting for the pull_request event on #$PR2 to drive cleanup to close #$PR1..."
wait_for "cleanup to close superseded PR #$PR1" bash -c \
  "[ \"\$(gh api repos/$REPO/pulls/$PR1 --jq .state)\" = closed ] && echo closed" \
  || { echo "❌ superseded PR #$PR1 was never closed — the pull_request->cleanup cascade did not fire"; exit 1; }
echo "✅ event-driven cleanup closed superseded PR #$PR1"

# Superseded branch deleted; the newer PR and its branch survive.
! branch_exists "$BR1" || { echo "❌ superseded branch $BR1 should have been deleted"; exit 1; }
[ "$(pr_state "$PR2")" = "open" ] || { echo "❌ newer PR #$PR2 should still be open"; exit 1; }
branch_exists "$BR2" || { echo "❌ newer branch $BR2 should still exist"; exit 1; }
echo "✅ superseded branch deleted; newer PR #$PR2 + branch survive"

echo "🎉 full flow passed: release → bump (release-name tag) → deploy PR → event-driven cleanup"
