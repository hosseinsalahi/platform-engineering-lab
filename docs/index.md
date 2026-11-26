# Platform Engineering Lab

Hands-on challenges for cloud-native platform engineering. Each challenge puts a broken
or incomplete platform component on a real Kubernetes cluster and validates your fix with
[KUTTL](https://kuttl.dev/) assertions on a timer.

38 challenges across 7 practical domains. This is a hands-on lab rather than an exam
simulator — see the README for how it maps to the hands-on
[CNPE](https://www.cncf.io/training/certification/cnpe/) and multiple-choice
[CNPA](https://www.cncf.io/training/certification/cnpa/) certifications, and which of their
domains are not covered here.

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

See the [README](https://github.com/hosseinsalahi/platform-engineering-lab#readme)
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
| 1 | Platform Architecture and Infrastructure | 15% | 8 |
| 2 | GitOps and Continuous Delivery | 25% | 6 |
| 3 | Platform APIs and Self-Service Capabilities | 25% | 4 |
| 4 | Observability and Operations | 20% | 7 |
| 5 | Security and Policy Enforcement | 15% | 10 |
| 6 | Packaging | bonus | 2 |
| 7 | Developer Experience | bonus | 1 |

Run a whole domain with `just domain-architecture`, `just domain-gitops`, `just domain-security`, and so on, or list
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
