# Platform Engineer Battleground

Hands-on challenges for cloud-native platform engineering. Each challenge puts a broken
or incomplete platform component on a real Kubernetes cluster and validates your fix with
[KUTTL](https://kuttl.dev/) assertions on a timer.

32 challenges across 7 domains, weighted to the CNPE curriculum.

## Quick Start

```bash
just check                                  # verify required tooling
just provision                              # kind cluster + all platform tools (~10-15 min)
just gitops-fix                             # run a single challenge
just destroy                                # cleanup
```

Lighter alternatives to a full provision:

```bash
just provision-exam exam-1                  # only the tools that exam needs
just provision-minimal                      # cluster only
```

See the [README](https://github.com/Liquid-Reply/platform-engineer-battleground#readme)
for prerequisites, CLI installation, and Podman setup on macOS.

## How a Challenge Works

Each challenge directory contains:

| File | Purpose |
|------|---------|
| `setup.yaml` | Creates the broken state; applied first |
| `NN-assert.yaml` | Progressive KUTTL assertions, one per phase |
| `README.md` | Scenario, task, and allowed documentation |
| `steps.txt` | Optional hints, `"0:First step description"` |
| `answer.md` | Worked solution — also the machine-executable answer |

KUTTL applies `setup.yaml`, then waits for each assertion to become true while you work
in another terminal. The default timeout is 7 minutes per challenge, matching exam
conditions. Resources are cleaned up when the test completes.

## Domains

| # | Domain | Weight | Challenges |
|---|--------|--------|-----------|
| 1 | GitOps and Continuous Delivery | 25% | 6 |
| 2 | Platform APIs and Self-Service | 25% | 4 |
| 3 | Observability and Operations | 20% | 6 |
| 4 | Platform Architecture | 15% | 6 |
| 5 | Security and Policy Enforcement | 15% | 7 |
| 6 | Scalability | bonus | 1 |
| 7 | Packaging | bonus | 2 |

Run a whole domain with `just domain-gitops`, `just domain-security`, and so on, or list
everything with `just list`.

## Where To Go Next

- **[Exams](EXAMS.md)** — timed mock exams and per-domain drills
- **[Solutions Guide](SOLUTIONS.md)** — the concepts behind each domain, with answers

## Platform Components

`just provision` installs ArgoCD, Argo Rollouts, Tekton, Kyverno, Gatekeeper, External
Secrets, Prometheus, Grafana, Jaeger, Istio, Crossplane, and OpenCost onto a local kind
cluster (1 control-plane + 2 workers).

## Notes

This is a learning environment. Treat outputs as untrusted and never use real secrets.
