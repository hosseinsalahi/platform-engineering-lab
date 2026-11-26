#!/usr/bin/env python3
import argparse
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Optional, Sequence, Set


@dataclass(frozen=True)
class ExamTooling:
    # Names align with scripts/provision-cluster.sh components.
    tools: List[str]
    challenges: List[str]


TOOL_ORDER: List[str] = [
    "argocd",
    "argo-rollouts",
    "tekton",
    "kyverno",
    "gatekeeper",
    "prometheus-stack",
    "jaeger",
    "crossplane",
    "istio",
    "external-secrets",
    "metrics-server",
    "opencost",
]


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[1]

def _resolve_exam_path(exam_arg: str) -> Path:
    root = _repo_root()

    candidates = [
        Path(exam_arg),
        root / exam_arg,
        root / "exams" / exam_arg,
        root / "exams" / f"{exam_arg}.yaml",
        root / "exams" / f"{exam_arg}.yml",
        root / "exams" / f"exam-{exam_arg}.yaml",
        root / "exams" / f"domain-{exam_arg}.yaml",
    ]

    for p in candidates:
        try:
            if p.is_file():
                return p.resolve()
        except OSError:
            continue

    raise SystemExit(f"ERROR: exam not found: {exam_arg}")


def _load_yaml(path: Path) -> object:
    try:
        import yaml  # type: ignore
    except Exception as e:  # pragma: no cover
        raise SystemExit(f"ERROR: PyYAML is required to parse exam files ({e}). Run `just check`.")

    try:
        with path.open("r", encoding="utf-8") as f:
            return yaml.safe_load(f)
    except OSError as e:
        raise SystemExit(f"ERROR: failed to read exam file: {path} ({e})")


def _as_list(value: object) -> List[object]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def _extract_challenges(exam_yaml: object) -> List[str]:
    if not isinstance(exam_yaml, dict):
        raise SystemExit("ERROR: exam YAML must be a mapping")
    sections = exam_yaml.get("sections")
    if not isinstance(sections, list):
        raise SystemExit("ERROR: exam YAML must contain `sections: []`")

    out: List[str] = []
    for s in sections:
        if not isinstance(s, dict):
            continue
        ch = s.get("challenge")
        if isinstance(ch, str) and ch.strip():
            out.append(ch.strip())
    if not out:
        raise SystemExit("ERROR: no challenges found under `.sections[].challenge`")
    return out


def _tools_from_challenge_path(challenge: str) -> Set[str]:
    # Fast-path mapping for cases where setup/asserts don’t include tool-specific kinds.
    tools: Set[str] = set()

    # Architecture domain (Istio, OpenCost, HPA)
    if challenge in (
        "1-architecture/istio-fault-injection",
        "1-architecture/service-mesh",
        "5-security/istio-mtls",
    ):
        tools.add("istio")
    if challenge == "1-architecture/cost-allocation":
        tools.add("opencost")
    if challenge == "1-architecture/hpa-cpu":
        tools.add("metrics-server")

    # GitOps domain
    if challenge.startswith("2-gitops/"):
        tools.add("argocd")
    if challenge in ("2-gitops/canary-rollout", "2-gitops/bluegreen"):
        tools.add("argo-rollouts")
    if challenge == "2-gitops/tekton-pipeline":
        tools.add("tekton")
    if challenge == "2-gitops/istio-canary":
        tools.update({"istio", "argocd"})

    # Platform APIs (Crossplane)
    if challenge == "3-apis/crossplane-workflow":
        tools.add("crossplane")

    # Observability domain (structured-logging uses only core Kubernetes APIs)
    if challenge.startswith("4-observability/") and challenge != "4-observability/structured-logging":
        tools.add("prometheus-stack")
    if challenge == "4-observability/jaeger-trace":
        tools.add("jaeger")

    # Security policy engines and pipeline security
    if challenge in ("5-security/kyverno-policy", "5-security/audit-compliance-policy", "7-devex/golden-path"):
        tools.add("kyverno")
    if challenge == "5-security/gatekeeper-constraint":
        tools.add("gatekeeper")
    if challenge == "5-security/pipeline-security-scan":
        tools.add("tekton")

    return tools


def _read_text_if_exists(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return ""


def _scan_yaml_texts_for_tools(texts: Iterable[str]) -> Set[str]:
    tools: Set[str] = set()
    combined = "\n".join([t for t in texts if t])
    if not combined.strip():
        return tools

    # Argo CD
    if re.search(r"(?m)^kind:\s*(Application|AppProject|ApplicationSet)\s*$", combined):
        tools.add("argocd")

    # Argo Rollouts
    if re.search(r"(?m)^kind:\s*Rollout\s*$", combined) or re.search(r"(?m)^apiVersion:\s*argoproj\\.io/", combined):
        tools.add("argo-rollouts")

    # Tekton
    if re.search(r"(?m)^apiVersion:\s*tekton\\.dev/", combined) or re.search(
        r"(?m)^kind:\s*(Pipeline|Task|PipelineRun|TaskRun|EventListener|TriggerTemplate|TriggerBinding)\s*$",
        combined,
    ):
        tools.add("tekton")

    # Istio
    if re.search(r"(?m)^apiVersion:\s*networking\\.istio\\.io/", combined) or re.search(
        r"(?m)^kind:\s*(VirtualService|DestinationRule|Gateway|ServiceEntry|Sidecar)\s*$",
        combined,
    ):
        tools.add("istio")
    if re.search(r"(?m)^apiVersion:\s*security\\.istio\\.io/", combined) or re.search(
        r"(?m)^kind:\s*(PeerAuthentication|AuthorizationPolicy|RequestAuthentication)\s*$",
        combined,
    ):
        tools.add("istio")

    # Prometheus Operator stack (incl. Grafana side)
    if re.search(r"(?m)^apiVersion:\s*monitoring\\.coreos\\.com/", combined) or re.search(
        r"(?m)^kind:\s*(ServiceMonitor|PodMonitor|PrometheusRule|Alertmanager|Prometheus)\s*$",
        combined,
    ):
        tools.add("prometheus-stack")

    # Jaeger Operator CRDs (if used directly)
    if re.search(r"(?m)^apiVersion:\s*jaegertracing\\.io/", combined) or re.search(r"(?m)^kind:\s*Jaeger\s*$", combined):
        tools.add("jaeger")

    # Crossplane
    if re.search(r"(?m)^apiVersion:\s*apiextensions\\.crossplane\\.io/", combined) or re.search(
        r"(?m)^kind:\s*(CompositeResourceDefinition|Composition)\s*$",
        combined,
    ):
        tools.add("crossplane")

    # Kyverno
    if re.search(r"(?m)^apiVersion:\s*kyverno\\.io/", combined) or re.search(r"(?m)^kind:\s*(ClusterPolicy|Policy)\s*$", combined):
        tools.add("kyverno")

    # Gatekeeper
    if re.search(r"(?m)^apiVersion:\s*(templates|constraints)\\.gatekeeper\\.sh/", combined) or re.search(
        r"(?m)^kind:\s*ConstraintTemplate\s*$",
        combined,
    ):
        tools.add("gatekeeper")

    # External Secrets Operator
    if re.search(r"(?m)^apiVersion:\s*external-secrets\\.io/", combined) or re.search(
        r"(?m)^kind:\s*(ExternalSecret|SecretStore|ClusterSecretStore)\s*$",
        combined,
    ):
        tools.add("external-secrets")

    # Metrics Server (in practice HPA requires it)
    if re.search(r"(?m)^kind:\s*HorizontalPodAutoscaler\s*$", combined) or re.search(r"(?m)^apiVersion:\s*autoscaling/", combined):
        tools.add("metrics-server")

    return tools


def infer_tools_for_exam(exam_path: Path) -> ExamTooling:
    exam = _load_yaml(exam_path)
    challenges = _extract_challenges(exam)

    repo = _repo_root()
    tools: Set[str] = set()

    for ch in challenges:
        tools |= _tools_from_challenge_path(ch)

        domain, name = ch.split("/", 1)
        challenge_dir = repo / "challenges" / domain / name
        texts: List[str] = []
        for fn in ("setup.yaml", "00-setup.yaml"):
            texts.append(_read_text_if_exists(challenge_dir / fn))
        for p in challenge_dir.glob("*-assert.yaml"):
            texts.append(_read_text_if_exists(p))
        tools |= _scan_yaml_texts_for_tools(texts)

    # Dependencies
    if "opencost" in tools:
        tools.add("prometheus-stack")
    if "istio" in tools:
        # provision-cluster.sh installs istio as base+istiod behind the "istio" tool name.
        pass

    ordered = [t for t in TOOL_ORDER if t in tools]
    return ExamTooling(tools=ordered, challenges=challenges)


def _format_tools(tools: Sequence[str], fmt: str) -> str:
    if fmt == "csv":
        return ",".join(tools)
    if fmt == "lines":
        return "\n".join(tools)
    raise SystemExit(f"ERROR: unknown format: {fmt}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Infer required cluster tooling for an exam YAML.")
    parser.add_argument("--exam", required=True, help="Exam identifier (e.g. exam-1) or path")
    parser.add_argument(
        "--format",
        choices=("csv", "lines"),
        default="lines",
        help="Output format for tool list (default: lines).",
    )
    parser.add_argument("--print-challenges", action="store_true", help="Also print inferred challenges to stderr.")
    args = parser.parse_args()

    exam_path = _resolve_exam_path(args.exam)

    tooling = infer_tools_for_exam(exam_path)

    if args.print_challenges:
        for ch in tooling.challenges:
            print(ch, file=os.sys.stderr)

    print(_format_tools(tooling.tools, args.format))


if __name__ == "__main__":
    main()
