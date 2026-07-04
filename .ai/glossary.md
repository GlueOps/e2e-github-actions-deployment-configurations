# Glossary

- **deploy PR** — a PR opened by the bump action that changes `image.tag`. Identified by the
  `glueops-deploy` marker in its body (not by branch name or title).
- **marker** — the hidden `<!-- glueops-deploy:{"app","env","tag"} -->` HTML comment in a
  deploy PR body. The **only** thing cleanup keys off. Its exact byte format is a contract
  shared with the bump action and the [`open-deploy-pr.sh`](../.github/e2e/open-deploy-pr.sh)
  helper.
- **superseded** — a deploy PR made obsolete by a newer one for the same app + env. cleanup
  closes it. Rule (`isSuperseded`): same app, same env, different tag, and a lower PR number
  than the trigger PR.
- **control PR** — a PR the e2e fabricates to prove isolation: the *superseding* PR
  (same app+env, newer), the *different-env* PR, the *different-app* PR (from a second bump),
  and the marker-less *human* PR that must be left untouched.
- **fixture** — `apps/<app>/envs/<env>/values.yaml`, the file bump edits. Contains an
  `e2e-sentinel-comment` used to assert the YAML edit preserved comments.
- **the App** — the dedicated GitHub App (installed on this repo only) whose scoped
  installation token bump uses. Credentials are repo-level: variable
  `GLUEOPS_DEPLOYMENT_APP_ID`, secret `GLUEOPS_DEPLOYMENT_APP_PRIVATE_KEY`.
- **`bump_ref` / `cleanup_ref`** — workflow inputs selecting which ref of each action to
  test (default `main`); used to validate an unmerged branch/PR without merging.
