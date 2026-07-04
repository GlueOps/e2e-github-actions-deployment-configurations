# Related repos

| Repo | Role |
|------|------|
| [github-actions-bump-deployment-tag](https://github.com/GlueOps/github-actions-bump-deployment-tag) | The **bump** action under test — mints a scoped GitHub App token, edits `image.tag` (comment-preserving), opens/updates a deploy PR. Also hosts the one-click App-install page under `docs/` (served via GitHub Pages). |
| [github-actions-cleanup-deployment-prs](https://github.com/GlueOps/github-actions-cleanup-deployment-prs) | The **cleanup** action under test — closes superseded deploy PRs (by marker) and deletes their branches. Takes `pr_number` + `gh_token` inputs. |
| [github-actions-create-container-tags](https://github.com/GlueOps/github-actions-create-container-tags) | Produces the image tag the build actually pushes. bump's `sanitizeTag` **must stay byte-identical** to this action's bash sanitization, or the config tag won't match the pushed image — bump has a golden parity test guarding it. |

## What runs when the e2e runs

By default the workflow uses `@main` of **bump** and **cleanup**. To validate an unmerged
change without merging, dispatch with the `bump_ref` / `cleanup_ref` inputs pointed at a
branch, PR (`refs/pull/N/head`), or SHA — the action is checked out at that ref and run via a
local `uses: ./_actions/...`. The ref's **committed `dist/`** is what executes (the actions
ship a prebuilt bundle). See [TESTING.md](../TESTING.md) §8–10.
