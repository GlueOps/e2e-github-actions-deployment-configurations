# The e2e suite, explained

This document explains **every part** of the end-to-end test in this repo so a future
human or agent can confidently edit, refactor, or extend it. It complements the
[README](./README.md) (which covers purpose + setup); this file is the maintainer's map
of the test itself.

Everything lives in one workflow: [`.github/workflows/e2e.yml`](./.github/workflows/e2e.yml),
with one helper script [`.github/e2e/open-deploy-pr.sh`](./.github/e2e/open-deploy-pr.sh)
and two fixture files under [`apps/`](./apps).

---

## 1. Design principles (read this before editing)

These are the rules the whole test is built on. Break one and the suite becomes flaky or
destructive.

1. **One deterministic job, no async.** The entire flow is a single job that runs steps
   top-to-bottom. It never waits on a webhook/event cascade. The key enabler: the
   **cleanup action accepts an explicit `pr_number` input**, so we drive it synchronously
   instead of triggering it via `on: pull_request`.
2. **Never modify `main`.** `bump` and `cleanup` only ever touch *feature branches*, so the
   `main` baseline (the fixture `values.yaml` files) stays constant across runs. This is
   what makes the test re-runnable and deterministic. **Do not add a step that commits to,
   merges into, or resets `main`.** If you think you need to, you're probably about to
   break determinism — reconsider.
3. **Self-cleaning + idempotent.** `Setup` clears leftovers from a prior (possibly failed)
   run *before* doing anything, and `Teardown` (`if: always()`) closes/deletes everything
   at the end. A run must leave the repo exactly as it found it.
4. **Serialized.** `concurrency: { group: e2e }` ensures only one run mutates the repo at a
   time. Never remove this — two concurrent runs would corrupt each other's PR/branch state.
5. **Assertions fail loud.** Every check is `test … || { echo "why"; exit 1; }`. A failed
   assertion must fail the job with a message that says what was expected.

---

## 2. The two actions under test

You need this much of their behavior to understand the assertions.

### `bump` — `GlueOps/github-actions-bump-deployment-tag@main`
Opens/updates a deploy PR (or direct-commits) that bumps `image.tag` in
`apps/<app>/envs/<env>/values.yaml`.

- **Inputs we use:** `ENV`, `CREATE_PR` (`"true"` = PR mode), `DEPLOYMENT_CONFIGS_REPO`
  (target repo name), `DEPLOYMENT_CONFIGS_APP_NAME` (the **app** — overrides the `apps/<…>`
  folder + marker + title; without it, the app defaults to the *source repo* name),
  `app-id` + `private-key` (the scoped GitHub App).
- **The tag** is computed from the trigger event. Under `workflow_dispatch`/`schedule`
  (how this test runs) there is no release/tag ref, so bump falls back to the
  **7-char short SHA** of the run's commit — i.e. `steps.bump.outputs.tag` is a SHA, not a
  semver. This is expected; the tag *value* is orthogonal to what we're testing.
- **Outputs we read:** `action` (`created-pr` | `updated-pr` | `committed` | `noop`),
  `pr-number`, `tag`.
- **Branch it creates:** `<sourceRepo>/update-<app>-<env>-image-tag-<tag>` (the app segment
  only appears when `DEPLOYMENT_CONFIGS_APP_NAME` is set).
- **PR title / commit subject:** `chore(deploy): <app> [<env>] -> <tag>` (uses the **app
  name**, so monorepo apps are distinguishable — this is asserted in step *bump_other*).
- **Idempotency:** re-running with the same inputs while the base branch is unchanged does
  **not** open a second PR — it reuses the open one and reports `updated-pr`.

### `cleanup` — `GlueOps/github-actions-cleanup-deployment-prs@main`
Closes superseded deploy PRs and deletes their branches. Runs on `GITHUB_TOKEN` (exactly
like production, where it runs *inside* the config repo).

- **Inputs:** `pr_number` (the "trigger" PR) and `gh_token`.
- **It only ever touches PRs carrying the deploy marker** (see §3). Anything without the
  marker — human PRs, other bots — is ignored entirely.
- **Supersession rule** (`isSuperseded`): a candidate open PR is closed **iff** it has the
  marker **and** `same app` **and** `same env` **and** `different tag` **and**
  `candidate PR number < trigger PR number`. So the trigger PR supersedes *older*
  same-app+env deploy PRs.

---

## 3. The deploy marker (the contract everything hinges on)

`bump` writes a hidden HTML comment into each deploy PR body:

```
<!-- glueops-deploy:{"app":"<app>","env":"<env>","tag":"<tag>"} -->
```

`cleanup` finds and classifies deploy PRs **solely by this marker** — never by branch name
or title. Consequences for the test:

- The `open-deploy-pr.sh` helper writes this **exact** format (byte-for-byte). If bump's
  marker format ever changes, update the helper to match, or the isolation controls won't
  be recognized as deploy PRs.
- A PR **without** the marker is, by definition, a "human/bot" PR that cleanup must not
  touch — that's the `HUMAN_PR` control in step *Setup isolation controls*.

---

## 4. Fixtures (`apps/`)

Two apps, so we can prove **cross-app** isolation:

| File | Represents |
|------|-----------|
| `apps/test-app/envs/prod/values.yaml` | the primary app (prod) |
| `apps/other-app/envs/prod/values.yaml` | a **second** app from the same repo (monorepo) |

Both contain an `image.tag` and a comment tagged **`e2e-sentinel-comment`**. The assertion
in step *bump created* greps for that sentinel to prove the YAML edit **preserved comments**
(bump uses a comment-preserving YAML editor). If you rename the sentinel, update the grep.

> There is **no** `staging` fixture. The cross-env control PR (`test-app/staging`) is a
> marker-only PR created by the helper — it doesn't need a real `values.yaml` because
> cleanup reads the marker, not the file.

---

## 5. The helper: `open-deploy-pr.sh`

```
open-deploy-pr.sh <branch> <app> <env> <tag>   # env: GH_TOKEN, REPO → prints new PR number
```

Creates a branch off `main`, commits a throwaway file (a PR needs a diff; the content is
irrelevant because cleanup reads the marker), and opens a PR whose body carries the
`glueops-deploy` marker for `<app>/<env>/<tag>`. Used to fabricate **control** deploy PRs
(the superseding PR and the different-env PR) deterministically, without running `bump`.

The human/bot control PR is **not** made with this helper — it's created inline in the
*Setup isolation controls* step precisely so it has **no** marker.

---

## 6. Step-by-step walkthrough

The job runs these steps in order. "Sets" / "Reads" refer to variables passed between steps
via `$GITHUB_ENV` (see §7).

| # | Step | What it does / asserts |
|---|------|------------------------|
| 1 | **Checkout** (×3) | Checks out this repo (for `open-deploy-pr.sh`), then the **bump** and **cleanup** action repos at `bump_ref` / `cleanup_ref` (default `main`) into `_actions/bump` and `_actions/cleanup`. Later steps run them via `uses: ./_actions/…`. |
| 2 | **Setup: clear leftovers** | Before doing anything, closes every open PR that has the marker **or** whose head branch starts with `e2e/` (catches the marker-less human control), and deletes the known `e2e/*` control branches. Makes the run idempotent against prior failures. |
| 3 | **Bump** (`id: bump`) | Runs `bump` for `test-app/prod`, PR mode. Mints the scoped App token, edits `values.yaml`, opens a deploy PR. |
| 4 | **Assert bump created** | Asserts `action == created-pr`; the PR body has the correct marker; the branch's `values.yaml` has the new tag **and** still contains `e2e-sentinel-comment` (comment preservation). **Sets** `BUMP_PR`, `BUMP_TAG`, `BUMP_BRANCH`. |
| 5 | **Bump again** (`id: bump2`) | Re-runs the identical bump. |
| 6 | **Assert idempotent** | Asserts `action == updated-pr` and the PR number equals `BUMP_PR` (no duplicate PR). |
| 7 | **Bump second app** (`id: bump_other`) | Runs `bump` for **`other-app`/prod** (monorepo — same repo, different app via `DEPLOYMENT_CONFIGS_APP_NAME`). |
| 8 | **Assert second app** | Asserts `created-pr`; the PR **title contains `other-app`** (validates bump's app-name-in-title behavior); the marker is `app=other-app`. **Sets** `OTHER_PR`, `OTHER_BRANCH`. ⚠️ depends on the bump `appName` fix being on `@main` (see §8). |
| 9 | **Setup isolation controls** | Creates three control PRs: `SUPER_PR` (helper: `test-app/prod`, tag `e2e-super` — **newer** than `BUMP_PR`, so it supersedes it), `STAGING_PR` (helper: `test-app/staging` — different env), and `HUMAN_PR` (inline, **no marker** — a human/bot PR). Asserts `SUPER_PR > BUMP_PR`. **Sets** `SUPER_PR`, `STAGING_PR`, `HUMAN_PR`. |
| 10 | **Cleanup** | Runs `cleanup` with `pr_number = SUPER_PR` (the trigger), on `GITHUB_TOKEN`. |
| 11 | **Assert isolation** | The heart of the test. Asserts cleanup **closed only** the superseded `BUMP_PR` (and deleted `BUMP_BRANCH`), while **all** of these stayed open: `SUPER_PR` (the trigger), `OTHER_PR` (different app), `STAGING_PR` (different env), `HUMAN_PR` (no marker). |
| 12 | **Teardown** (`if: always()`) | Closes every marker/`e2e/`-branch PR and deletes the control branches. Runs even if an earlier step failed, so the repo is always left clean. |

### The five properties proven (map to the README)
1. Scoped-token bump + comment preservation + marker → steps 3–4
2. Idempotency (`updated-pr`) → steps 5–6
3. Monorepo app-named PR → steps 7–8
4. Cross-app + cross-env isolation → steps 9–11 (`OTHER_PR`, `STAGING_PR`)
5. Human/bot safety (marker-less PR untouched) → steps 9–11 (`HUMAN_PR`)

---

## 7. Variables passed between steps

Job-level `env` (constant): `GH_TOKEN`, `REPO`, `CONFIG_REPO`, `VALUES_PATH`,
`SUPER_BRANCH` (`e2e/super`), `STAGING_BRANCH` (`e2e/ctrl-staging`),
`HUMAN_BRANCH` (`e2e/ctrl-human`).

Run-scoped, written to `$GITHUB_ENV` by one step and read by a later one:

| Variable | Set by (step) | Read by |
|----------|---------------|---------|
| `BUMP_PR`, `BUMP_TAG`, `BUMP_BRANCH` | 4 (Assert bump created) | 6, 9, 11 |
| `OTHER_PR`, `OTHER_BRANCH` | 8 (Assert second app) | 11 |
| `SUPER_PR` | 9 (Setup controls) | 10 (cleanup trigger), 11 |
| `STAGING_PR`, `HUMAN_PR` | 9 (Setup controls) | 11 |

If you add a step that produces a value a later step needs, append it to `$GITHUB_ENV` the
same way (`echo "NAME=value" >> "$GITHUB_ENV"`), never rely on shell variables surviving
across steps (each step is a fresh shell).

---

## 8. Invariants & gotchas when editing

- **Which action code runs (the `bump_ref` / `cleanup_ref` inputs).** The actions are
  **checked out at a ref and run locally** via `uses: ./_actions/bump` and
  `./_actions/cleanup` (see §9's "test an unmerged change"). Defaults + `schedule` use
  `main`. Because `uses:` can't take an expression, this checkout-then-local-`uses` pattern
  is the mechanism — don't revert it to `uses: <org>/<repo>@main`, or you lose the ability
  to test unmerged refs. Note assertions test whatever ref you point at: e.g. step 8's
  "title contains `other-app`" only passes on a ref that has the bump `appName`-in-title
  behavior.
- **The ref's committed `dist/` is what runs.** These actions ship a prebuilt `dist/`
  bundle and GitHub runs *that*, not the source. So testing a branch/PR runs its
  **committed** `dist/` — if the branch's source changed but `dist/` wasn't rebuilt, you're
  testing stale code. (Each action's `build-dist` workflow keeps `dist/` current on its
  PRs, so this is normally a non-issue.)
- **Tag is a SHA here.** Because we trigger via `workflow_dispatch`/`schedule`, the bumped
  tag is a 7-char SHA, and it's the **same** for `test-app` and `other-app` in one run
  (same commit). That's fine — apps are distinguished by app+env, not tag. Don't assert on
  a specific tag value.
- **PR-number ordering is the supersession clock.** `SUPER_PR` must be created **after**
  (`>`) `BUMP_PR` to supersede it — step 9 asserts this. If you reorder steps so the
  superseding PR is created first, cleanup won't close the bump PR and step 11 fails.
- **Monorepo apps need `DEPLOYMENT_CONFIGS_APP_NAME`.** Two apps from one repo must each set
  a distinct app name, or they collide on the same `apps/<…>` path and branch. The test
  sets `test-app` / `other-app` for exactly this reason.
- **Marker byte-format.** `open-deploy-pr.sh`'s marker must match bump's `formatMarker`
  output exactly, and step-4/8 marker greps must match too. Change one, change all.
- **Setup/teardown reap logic.** Deploy PRs are reaped by marker; the marker-less human
  control is reaped by its `e2e/` branch prefix. If you add a new control PR, give it an
  `e2e/…` branch (or a marker) so setup/teardown clean it up — otherwise it leaks across
  runs.
- **Credentials & App install.** The bump steps read `vars.GLUEOPS_DEPLOYMENT_APP_ID` +
  `secrets.GLUEOPS_DEPLOYMENT_APP_PRIVATE_KEY` (repo-level; see README) and the App must be
  installed on **this** repo. A `404 … /installation` in a bump step means the App isn't
  installed here (not a code bug).
- **Permissions.** The job's `GITHUB_TOKEN` needs `contents: write` + `pull-requests: write`
  (declared at job top) for setup/teardown and the cleanup step. Don't narrow these.

---

## 9. How to add a new test

**Add a new isolation case** (e.g., prove a `prod` deploy doesn't close a `dev` PR):
1. In step 9, create a control PR with the helper:
   `dev=$(bash .github/e2e/open-deploy-pr.sh e2e/ctrl-dev test-app dev v-dev)` and add
   `echo "DEV_PR=$dev" >> "$GITHUB_ENV"`.
2. Use an `e2e/…` branch name so setup/teardown reap it automatically.
3. In step 11, assert it survived:
   `test "$(gh api "repos/$REPO/pulls/$DEV_PR" --jq '.state')" = "open" || { echo "…"; exit 1; }`.

**Add a new bump scenario** (e.g., direct-commit mode, `CREATE_PR: "false"`):
- Note this would commit to `main` — which violates §1.2. If you test it, do it on a
  throwaway branch you reset, and think hard about determinism first. Prefer covering such
  paths in the actions' own unit tests.

**Add a new app/env fixture:** add `apps/<app>/envs/<env>/values.yaml` with an
`e2e-sentinel-comment`, then a bump step with the matching `DEPLOYMENT_CONFIGS_APP_NAME`
and `ENV`.

Always: keep the marker format in sync, pass cross-step values via `$GITHUB_ENV`, and make
sure `Teardown` cleans up whatever you create. Then `actionlint` the workflow and
`shellcheck` the helper before opening a PR (see §10).

---

## 10. Running & debugging

- **Run it:** Actions tab → `e2e` → **Run workflow** (`workflow_dispatch`), or wait for the
  hourly `schedule`. From the CLI: `gh workflow run e2e.yml`.
- **Test an unmerged action change (no merge required):** dispatch with the ref inputs
  pointed at the branch/PR/SHA you want to validate — the action is checked out there and
  run locally, so you get a full real-GitHub run *before* merging:
  ```
  # test a bump feature branch
  gh workflow run e2e.yml -f bump_ref=my-feature-branch
  # test a bump PR directly, and a cleanup branch at the same time
  gh workflow run e2e.yml -f bump_ref=refs/pull/42/head -f cleanup_ref=some-branch
  ```
  Omitted inputs default to `main`. Reminder: the ref's **committed `dist/`** is what runs
  (see §8).
- **Test a change to THIS workflow (no merge required):** `workflow_dispatch` can run the
  workflow file from any branch — push your branch and
  `gh workflow run e2e.yml --ref my-workflow-branch [-f bump_ref=…]`. (`schedule` only ever
  runs the default branch.)
- **Lint before pushing:** `actionlint .github/workflows/e2e.yml` (it also shellchecks the
  embedded `run:` scripts) and `shellcheck .github/e2e/open-deploy-pr.sh`.
- **Common failures and what they mean:**

  | Symptom | Likely cause |
  |---------|--------------|
  | Bump step: `404 … /installation` | the App (`GLUEOPS_DEPLOYMENT_APP_ID`) isn't installed on this repo, or the var/secret points at the wrong App. Not a code bug. |
  | Bump step: `401` on token mint | the private key doesn't match the App ID. |
  | Step 8: "title does not name the app 'other-app'" | the bump `appName`-in-title fix isn't on `@main`. |
  | Step 11: "CROSS-APP/ENV ISOLATION FAILED" | cleanup closed a PR it shouldn't have — a real `isSuperseded` regression. Inspect the marker on the wrongly-closed PR. |
  | Step 11: "HUMAN-PR SAFETY FAILED" | cleanup closed a marker-less PR — a serious safety regression in cleanup's marker gating. |
  | A red **GlueOps Standard Checks** on a transient deploy PR | expected/harmless — the org's conventional-commit check runs on the deploy PRs bump opens; those PRs are closed by cleanup/teardown. It does **not** fail the e2e job. |
