# e2e-github-actions-deployment-configurations

**Throwaway end-to-end test fixture** for the GlueOps Deployment GitHub Actions:

- [`github-actions-bump-deployment-tag`](https://github.com/GlueOps/github-actions-bump-deployment-tag)
- [`github-actions-cleanup-deployment-prs`](https://github.com/GlueOps/github-actions-cleanup-deployment-prs)

This repo is **disposable**. The [`e2e`](.github/workflows/e2e.yml) workflow runs the
`@main` of both actions against a fake `apps/test-app/envs/prod/values.yaml` fixture
and **deletes branches / closes PRs** on every run — never point real automation at it,
and never store anything of value here.

## What the e2e proves (against real GitHub)

1. **bump** mints a scoped App installation token, edits `image.tag` in `values.yaml`
   **preserving comments**, and opens a PR carrying the `glueops-deploy` marker.
2. Re-running **bump** is idempotent — it reuses the same PR (`updated-pr`), no duplicate.
3. **cleanup** (running on `GITHUB_TOKEN`, exactly like production) closes a superseded
   deploy PR and deletes its branch, leaving the newer PR open.

## Running it

- **Manually:** Actions tab → `e2e` → "Run workflow".
- **Nightly:** scheduled at 07:00 UTC.

## Required configuration (already set up)

| Kind | Name | Purpose |
|------|------|---------|
| Org variable | `GLUEOPS_DEPLOYMENT_APP_ID` | App ID of the dedicated e2e test App |
| Org secret | `GLUEOPS_DEPLOYMENT_APP_PRIVATE_KEY` | private key of that App |
| App install | `e2e-tests-glueops-deployment-v1` | installed on this repo (contents + PR write) |

`GITHUB_TOKEN` (automatic) covers setup/teardown and the cleanup step; nothing else to store.
