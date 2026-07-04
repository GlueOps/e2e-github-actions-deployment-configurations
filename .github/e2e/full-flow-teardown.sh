#!/usr/bin/env bash
# Reset the full-flow suite's own state: close its flow-app deploy PRs, delete their
# branches, and delete its synthetic `flow-e2e-*` releases + tags. Scoped strictly to
# full-flow artifacts — it never touches the deterministic e2e.yml suite (test-app /
# other-app / e2e-* branches) or `main`. Idempotent; safe to run before and after a run.
#
# Env: GH_TOKEN, REPO.
set -euo pipefail

echo "full-flow teardown: closing flow-app deploy PRs + deleting flow-e2e releases/tags"

# Close open flow-app deploy PRs and delete their branches.
for pr in $(gh api "repos/$REPO/pulls?state=open&per_page=100" --jq '.[].number'); do
  branch=$(gh api "repos/$REPO/pulls/$pr" --jq '.head.ref')
  case "$branch" in
    */update-flow-app-*)
      echo "  closing flow-app PR #$pr ($branch)"
      gh api -X PATCH "repos/$REPO/pulls/$pr" -f state=closed >/dev/null 2>&1 || true
      gh api -X DELETE "repos/$REPO/git/refs/heads/$branch" >/dev/null 2>&1 || true
      ;;
  esac
done

# Delete synthetic releases and their tags.
for id in $(gh api "repos/$REPO/releases?per_page=100" \
    --jq '.[] | select(.tag_name | startswith("flow-e2e-")) | .id'); do
  tag=$(gh api "repos/$REPO/releases/$id" --jq '.tag_name')
  echo "  deleting release $tag (id $id)"
  gh api -X DELETE "repos/$REPO/releases/$id" >/dev/null 2>&1 || true
  gh api -X DELETE "repos/$REPO/git/refs/tags/$tag" >/dev/null 2>&1 || true
done

# Sweep any orphan flow-e2e tags whose release was already gone. `matching-refs` always
# returns an array (empty, not 404, when none match) — unlike `refs/tags/<prefix>`.
for ref in $(gh api "repos/$REPO/git/matching-refs/tags/flow-e2e-" --jq '.[].ref' 2>/dev/null || true); do
  echo "  deleting orphan tag ${ref#refs/tags/}"
  gh api -X DELETE "repos/$REPO/git/${ref}" >/dev/null 2>&1 || true
done

echo "✅ full-flow teardown complete"
