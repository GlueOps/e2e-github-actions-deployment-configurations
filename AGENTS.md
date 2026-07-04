# AGENTS.md

Throwaway **end-to-end test fixture** for the GlueOps Deployment GitHub Actions —
[bump](https://github.com/GlueOps/github-actions-bump-deployment-tag) and
[cleanup](https://github.com/GlueOps/github-actions-cleanup-deployment-prs). This repo is
**disposable**: the `e2e` workflow opens/closes PRs and deletes branches on every run.

## Before you touch anything

- **Never commit to, merge into, or reset `main`.** The suite's determinism depends on the
  `main` baseline (`apps/**/values.yaml`) staying constant. This is the #1 way to break it.
- The whole test is **one deterministic, self-cleaning job** — no async event cascades. Keep
  it that way.
- `cleanup` only ever acts on PRs carrying the `glueops-deploy` marker — **never** on human
  or unrelated-bot PRs. Don't weaken that guarantee.

## Where to look

- **Editing or adding tests → read [TESTING.md](./TESTING.md) first.** It is the full map:
  design rules, a step-by-step walkthrough, the cross-step variable flow, editing gotchas, a
  recipe for adding cases, and a failure-debugging table.
- **Setup, how to run (incl. testing an unmerged action ref), credentials →
  [README.md](./README.md).**
- **Deeper agent-oriented context → [`.ai/`](./.ai/)** (imported essentials below).

@.ai/context.md
@.ai/glossary.md
