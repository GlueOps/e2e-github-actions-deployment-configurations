# Context: what this repo tests

This repo is the **live end-to-end smoke test** ("P2") for GlueOps' Continuous Delivery
GitHub Actions. It exists because those actions' own test suites are fully mocked — this is
the only layer that exercises them against **real GitHub**: real GitHub App token minting,
real Octokit API calls, real PR and branch operations.

## The system under test

GlueOps CD moves an app's newly-built image tag into a GitOps config repo:

1. An app repo cuts a release/tag → the **bump** action mints a *scoped GitHub App token*
   and updates `image.tag` in the `deployment-configurations` repo
   (`apps/<app>/envs/<env>/values.yaml`), opening a PR (or committing directly).
2. The **cleanup** action (in production runs inside the config repo on `pull_request`,
   using `GITHUB_TOKEN`) closes superseded deploy PRs and deletes their branches.
3. ArgoCD watches the config repo and deploys whatever `image.tag` is on the default branch.

**This repo stands in for a `deployment-configurations` repo** and drives both actions from a
single workflow ([`.github/workflows/e2e.yml`](../.github/workflows/e2e.yml)).

## The marker contract (why cleanup is safe)

`bump` writes a hidden HTML comment into every deploy PR body:

```
<!-- glueops-deploy:{"app":"<app>","env":"<env>","tag":"<tag>"} -->
```

`cleanup` classifies deploy PRs **solely** by this marker and closes one only when it has the
**same app + same env, a different tag, and a lower PR number** than the trigger PR. A PR
without the marker (a human or unrelated-bot PR) is never touched. The e2e proves all of
this live — including that a marker-less PR survives.

## How the e2e is built

One deterministic, self-cleaning job; no async event cascades (the key enabler is that
`cleanup` takes an explicit `pr_number` input, so it's driven synchronously). It never
modifies `main`. It defaults to `@main` of both actions but can run any branch/PR/SHA via the
`bump_ref` / `cleanup_ref` workflow inputs. Full details in [TESTING.md](../TESTING.md).

Sibling repos and how they connect: [related-repos.md](./related-repos.md).
