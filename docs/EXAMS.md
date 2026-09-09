# Exams

Two timed practice sets are provided under `exams/`. They bundle challenges into a single
sitting with a per-task budget; they are not simulations of the CNPA exam, which is
multiple-choice.

## Usage

1. Create the lab cluster:

```bash
just provision
# or (lighter): install only the tools required by the exam
just provision-exam exam-1
```

2. List sections:

```bash
just exams
just exam-1 --list
just exam-2 --list
```

3. Start an exam (interactive):

```bash
just exam-1
just exam-2
```

## Domain-Specific Drills

In addition to full mock exams, you can run focused drills for specific domains:

```bash
just domain-gitops
just domain-platform
just domain-observability
just domain-architecture
just domain-security
just domain-scalability
just domain-packaging
```

These run all challenges in a specific domain sequentially using the interactive runner.

Notes:
- Each section runs the corresponding challenge via `scripts/run-exercise.sh`.
- The exam runner passes a per-section `--timeout` to the challenge runner.
