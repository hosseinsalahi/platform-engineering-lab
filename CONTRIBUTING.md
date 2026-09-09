# Contributing

## Local checks

Run these before opening a PR; CI runs the same four:

```bash
just preflight     # validates challenge setup.yaml and *-assert.yaml files
just check-docs    # relative markdown links resolve
just lint-sh       # shellcheck -x scripts/*.sh
yamllint -c .yamllint .
```

`preflight` needs PyYAML (`pip install pyyaml`). CI additionally provisions a minimal
kind cluster and runs the `0-test/simple-pod` smoke test.

## Repository layout

```
challenges/<domain>/<challenge>/   the challenge itself
exams/                             exam and per-domain drill definitions
scripts/                           runners, provisioning, validation
docs/                              TechDocs site (mkdocs.yml at the repo root)
solutions/                         standalone solution manifests
```

Domains are numbered directories (`1-gitops` … `7-packaging`), each with a
`kuttl-test.yaml` TestSuite that sets the 7-minute per-challenge timeout.

## Adding a challenge

Create `challenges/<domain>/<name>/` with:

| File | Required | Purpose |
|------|----------|---------|
| `setup.yaml` | yes | Manifests that create the broken state |
| `00-assert.yaml` | yes | KUTTL assertion for the first phase |
| `NN-assert.yaml` | no | Further phases, applied in order |
| `README.md` | yes | Context, task, verification, allowed documentation |
| `answer.md` | yes | Worked solution (see the contract below) |
| `steps.txt` | no | Hints, one per line, formatted `0:First step description` |

New domains need a `kuttl-test.yaml` in the domain directory (copy an existing one) and an `exams/domain-<name>.yaml` so `just domain-<name>` has something to run.

Then wire it up:

1. Add a recipe to the `justfile` in the matching domain section, using `_run`:
   `mydomain-thing: (_run "4-architecture" "my-challenge")`
2. Add a section to the relevant file in `exams/` so the challenge is reachable from a
   drill or exam. Every challenge should appear in at least one exam YAML.
3. Add a bullet to the domain list in `README.md` and update the challenge count.

A challenge may place resources in a shared platform namespace (`monitoring`, for
instance), but it must never **declare** one. Cleanup runs `kubectl delete -f setup.yaml`,
so a setup that contains `kind: Namespace` named `monitoring` uninstalls
kube-prometheus-stack when the challenge finishes. Use a challenge-scoped name (`cnpe-*`)
and select the namespace by label if the scenario needs to reference it. `just preflight`
enforces this against a list of reserved names.

Relatedly, the namespace-delete step only ever removes a namespace the challenge declares
itself — see `extract_owned_namespace` in `scripts/solve-exam.py`. Never widen that.

`setup.yaml` must not carry a top-level `status:` block, and any custom resource must
appear after its CRD in the same file — `just preflight` enforces both.

## The `answer.md` contract

`answer.md` is read by humans *and* executed by `scripts/solve-exam.py`
(`just solve <domain>/<challenge>`), which is how a challenge is proven solvable. The
extractor walks the file section by section and builds a shell script:

- **Fenced `yaml` blocks** become `kubectl apply -f -` heredocs, in document order — but
  only if the block contains both `apiVersion:` and `kind:`. Partial snippets meant to
  illustrate an edit are skipped, so a fragment shown for `kubectl edit` is safe to
  include.
- **Fenced `bash`, `sh`, or `shell` blocks** are executed as-is, after all YAML blocks.
- **Untagged fenced blocks are ignored** — use them for expected output and diffs.
- **Sections are skipped entirely** when the heading contains any of: `verify`,
  `verification`, `debug`, `debugging`, `troubleshooting`, `notes`, `tips`, `one-liner`,
  `key concepts`, `concepts`, `reference`, `summary`, `best practices`, `alternative`,
  `diagnosis`. Put diagnostic and explanatory commands under such a heading.
- The script runs under `set -euo pipefail` from wherever the user invoked `just`, so
  begin any path-dependent block with `cd "$(git rev-parse --show-toplevel)"`.
- Interactive commands (`kubectl edit`, `vim`, …) and nested `just` calls are stripped;
  `kubectl get/describe/logs` get `|| true` appended. An answer whose only executable
  content is diagnostics extracts to a script that cannot pass the asserts.

Check what your answer produces before pushing:

```bash
just solve <domain>/<challenge> --print-script   # inspect, no cluster needed
just solve <domain>/<challenge>                  # execute, then validate with KUTTL
```

The extracted script must produce the state every `NN-assert.yaml` asserts, including
any resource the user is expected to create by hand. Make it idempotent
(`helm upgrade --install`, `kubectl apply`) so a re-solve behaves the same.

If a challenge is solved by editing files tracked in the repo, have the answer copy them
to a scratch directory and work there — otherwise the first solve leaves the challenge
permanently fixed in the working tree. See
`challenges/7-packaging/helm-templating/answer.md`.

## Style

- One challenge per directory; keep the broken state minimal and the bug discoverable.
- Comment the injected bug in `setup.yaml` (`# BUG 1: ...`) — it documents intent for
  reviewers, and the file is not shown to the person taking the challenge.
- Link only to official upstream documentation under "Allowed Documentation".
