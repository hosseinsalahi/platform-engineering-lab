# AGENTS.md

Guidance for AI coding agents working in this repo. Human-facing docs are
[README.md](README.md) (setup, challenge list) and [CONTRIBUTING.md](CONTRIBUTING.md)
(layout, the `answer.md` contract, checks). Read `CONTRIBUTING.md` before changing
anything under `challenges/`; this file only records what is easy to get wrong.

## Verification

Run without a cluster, and always before finishing:

```bash
just preflight     # challenge setup.yaml / *-assert.yaml shape and invariants
just check-docs    # relative markdown links resolve
just lint-sh       # shellcheck -x scripts/*.sh
yamllint -c .yamllint .
```

Everything else — `just <challenge>`, `just solve`, `just solve-all` — needs a
provisioned kind cluster (`just provision`, ~10-15 min, podman running). If you do not
have one, say the change is **not verified** rather than asserting the challenge works.
`just solve <domain>/<challenge> --print-script` inspects the extracted solver script
without a cluster and is the cheapest check on an `answer.md` edit.

When something fails and the cause is unclear, `just doctor` reports the toolchain, the
kind cluster and context, which platform components are installed and ready, and leftover
state from an interrupted run. `just doctor --exam <exam>` narrows it to the components
that exam actually needs.

## Invariants

1. **`answer.md` is executable, not just prose.** `scripts/solve-exam.py` applies every
   fenced `yaml` block containing both `apiVersion:` and `kind:`, then runs every `bash`
   block. Adding an illustrative manifest to an answer changes what the solver does.
   Put diagnostics under a skipped heading (`Verify`, `Debugging`, `Notes`, …) — full
   rules in [CONTRIBUTING.md](CONTRIBUTING.md#the-answermd-contract).
2. **Answers must not modify tracked files.** Copy to a scratch directory and work
   there, or the first solve leaves the challenge permanently fixed in the working tree.
   Pattern: `challenges/7-packaging/helm-templating/answer.md`.
3. **Never declare a shared namespace in `setup.yaml`.** Cleanup runs
   `kubectl delete -f setup.yaml`, so declaring `monitoring` uninstalls
   kube-prometheus-stack. Use a `cnpe-*` name and select shared namespaces by label.
   Enforced by `RESERVED_NAMESPACES` in `scripts/preflight.py`.
4. **Do not widen `extract_owned_namespace`** in `scripts/solve-exam.py` — it deliberately
   deletes only a namespace the challenge declares itself.
5. **Adding a challenge is a four-part change**, not one directory: the challenge files,
   a `justfile` recipe using `_run`, an entry in `exams/`, and a README bullet plus the
   challenge count. A challenge missing from `exams/` is unreachable.
6. **Pin versions.** Chart versions live in `scripts/chart-versions.env`; renovate tracks
   them. Do not introduce floating tags.
7. **Shell scripts must run on bash 3.2**, the version macOS ships. CI runs Ubuntu's
   bash 5, so it will not catch `mapfile`, `declare -A`, `${var,,}` or `wait -n`.
   Check with `/bin/bash -n scripts/<file>.sh` on macOS.
8. Comment injected bugs in `setup.yaml` (`# BUG 1: ...`), and link only to official
   upstream docs under "Allowed Documentation".

## Scope

Challenges are deliberately broken. Do not "fix" a `setup.yaml` because it looks wrong —
check `answer.md` and the asserts first to see whether the breakage is the exercise.
