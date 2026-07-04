#!/usr/bin/env bash
# Open a deploy-style PR carrying a glueops-deploy marker, for e2e isolation controls.
# The file diff is irrelevant — cleanup identifies deploy PRs solely by the body marker.
#
# Usage: open-deploy-pr.sh <branch> <app> <env> <tag>
# Env:   GH_TOKEN, REPO   Prints the new PR number to stdout.
set -euo pipefail

branch="$1"; app="$2"; env="$3"; tag="$4"

base=$(gh api "repos/$REPO/git/ref/heads/main" --jq '.object.sha')
gh api -X POST "repos/$REPO/git/refs" -f ref="refs/heads/$branch" -f sha="$base" >/dev/null

# A throwaway commit so the branch differs from main (a PR needs a diff).
path="e2e/markers/${app}-${env}.txt"
content=$(printf 'e2e marker holder: %s [%s] -> %s\n' "$app" "$env" "$tag" | base64 -w0)
gh api -X PUT "repos/$REPO/contents/$path" \
  -f message="chore(deploy): ${app} [${env}] -> ${tag}" \
  -f content="$content" -f branch="$branch" >/dev/null

marker="<!-- glueops-deploy:{\"app\":\"${app}\",\"env\":\"${env}\",\"tag\":\"${tag}\"} -->"
body=$(printf 'e2e deploy PR for %s [%s] -> %s\n\n%s\n' "$app" "$env" "$tag" "$marker")
gh api -X POST "repos/$REPO/pulls" \
  -f title="chore(deploy): ${app} [${env}] -> ${tag}" \
  -f head="$branch" -f base=main -f body="$body" --jq '.number'
