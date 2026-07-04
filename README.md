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
3. **Monorepo:** a second app (`other-app`) bumped from the same repo gets its own
   **distinct, app-named** PR (`chore(deploy): other-app …`, not the repo name).
4. **cleanup** (running on `GITHUB_TOKEN`, exactly like production) closes **only** the
   superseded same-app-and-env PR and deletes its branch — a **different app**
   (`other-app/prod`) and a **different env** (`test-app/staging`) stay open (isolation).
5. **Human/bot safety:** a marker-less PR (no `glueops-deploy` marker, standing in for a
   human or unrelated-bot PR) is **never touched** by cleanup — it stays open.

## Running it

- **Manually:** Actions tab → `e2e` → "Run workflow".
- **Hourly:** scheduled every hour (at :17 UTC).
- **Against an unmerged action change (no merge needed):** dispatch with `bump_ref` /
  `cleanup_ref` set to a branch, PR (`refs/pull/N/head`), or SHA — e.g.
  `gh workflow run e2e.yml -f bump_ref=my-branch`. Defaults to `main`. See
  [TESTING.md](./TESTING.md).

## Editing or extending the tests

See **[TESTING.md](./TESTING.md)** — a full maintainer's map of the suite: the design
rules (never touch `main`, one deterministic job, self-cleaning), a step-by-step
walkthrough, the variables passed between steps, editing gotchas, a recipe for adding new
cases, and a debugging table of common failures.

## How this repo is configured

The e2e authenticates as a **dedicated GitHub App scoped to only this repository**, with
its credentials stored as **repo-level** variable/secret (not org-level). This keeps the
test fully isolated: least-privilege blast radius (one throwaway repo) and immune to
production App churn on the org-level `GLUEOPS_DEPLOYMENT_*` values.

| Kind | Where | Name | Value |
|------|-------|------|-------|
| Variable | **this repo** (Settings → Secrets and variables → Actions → Variables) | `GLUEOPS_DEPLOYMENT_APP_ID` | the App's numeric App ID |
| Secret | **this repo** (Settings → Secrets and variables → Actions → Secrets) | `GLUEOPS_DEPLOYMENT_APP_PRIVATE_KEY` | the App's `.pem` private key |
| App install | **this repo only** | the dedicated e2e App | Contents R/W · Pull requests R/W · Metadata RO |

`GITHUB_TOKEN` (automatic) covers setup/teardown and the cleanup step — nothing else to store.

### Reproducing the setup from scratch

1. **Create the App** with the one-click installer:
   <https://glueops.github.io/github-actions-bump-deployment-tag/> — enter the `GlueOps`
   org and create the App (give it a distinct name, e.g. `e2e-tests-glueops-deployment`,
   so it never collides with the production Deployment App). The page shows the **App ID**
   and a one-time **private key** — keep both handy.
2. **Install it on ONLY this repository.** On the App's install screen choose
   **Only select repositories → `e2e-github-actions-deployment-configurations`**. Do not
   grant it any other repo. (Permissions are already Contents + Pull requests write,
   Metadata read.) Skipping this is the #1 cause of a `404 ... /installation` failure in
   the bump step.
3. **Store the credentials at the REPO level** on this repo (not org-level):
   - Variable `GLUEOPS_DEPLOYMENT_APP_ID` = the App ID from step 1
   - Secret `GLUEOPS_DEPLOYMENT_APP_PRIVATE_KEY` = the full `.pem` contents from step 1

   > Repo-level values take precedence over any org-level variable/secret of the same
   > name, so this fixture stays pinned to its own App regardless of what the org does.

> **Why not the org-level defaults?** The two GlueOps consumer examples read the
> *org-level* `GLUEOPS_DEPLOYMENT_*`. Reusing those here would couple the e2e to the
> production App — re-provisioning prod (new App ID/key) would silently break this test.
> Repo-level + single-repo install keeps the two independent.
