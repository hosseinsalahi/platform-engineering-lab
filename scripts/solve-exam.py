#!/usr/bin/env python3
import argparse
import os
import re
import select
import subprocess
import sys
import time
from dataclasses import dataclass
from typing import List, Optional, Tuple


DEFAULT_TIMEOUT_SECONDS = 420


@dataclass(frozen=True)
class CommandResult:
    returncode: int
    stdout: str
    stderr: str


def _run(cmd: List[str], *, input_text: Optional[str] = None, timeout: Optional[int] = None) -> CommandResult:
    try:
        proc = subprocess.run(
            cmd,
            input=input_text,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as e:
        stdout = str(getattr(e, "stdout", "") or "")
        stderr = str(getattr(e, "stderr", "") or "")
        return CommandResult(124, stdout, stderr + f"\nTimed out after {timeout} seconds.\n")
    return CommandResult(proc.returncode, proc.stdout or "", proc.stderr or "")


def _run_stream(cmd: List[str], *, timeout: Optional[int] = None, debug: bool = False) -> int:
    start = time.time()
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    assert proc.stdout is not None
    
    def process_line(l: str) -> None:
        if not debug:
            return
        sys.stdout.write(l)
        sys.stdout.flush()

    try:
        while proc.poll() is None:
            # Check for output with a timeout so we can also check the global timeout
            rlist, _, _ = select.select([proc.stdout], [], [], 0.5)
            if rlist:
                line = proc.stdout.readline()
                if line:
                    process_line(line)
                else:
                    # EOF reached
                    break

            if timeout is not None and (time.time() - start) > timeout:
                proc.kill()
                proc.wait(timeout=10)
                sys.stdout.write(f"\nTimed out after {timeout} seconds.\n")
                return 124
        
        # Read any remaining output after process exit
        for line in proc.stdout:
            process_line(line)

        return proc.wait(timeout=10)
    finally:
        try:
            proc.stdout.close()
        except Exception:
            pass


def require_tool(name: str) -> None:
    res = _run(["bash", "-lc", f"command -v {name} >/dev/null 2>&1 && echo ok || echo missing"])
    if res.stdout.strip() != "ok":
        raise SystemExit(f"ERROR: required tool not found in PATH: {name}")


def require_kube_context(expected: Optional[str] = None) -> None:
    if expected is None:
        cluster = os.environ.get("CNPE_CLUSTER_NAME", "battleground")
        expected = f"kind-{cluster}"
    res = _run(["kubectl", "config", "current-context"])
    ctx = res.stdout.strip()
    if res.returncode != 0 or ctx != expected:
        raise SystemExit(
            f"ERROR: wrong kubectl context '{ctx or 'unknown'}' (expected '{expected}'). "
            f"Run `just provision` (or `just setup` on older versions)."
        )


def require_kuttl() -> None:
    res = _run(["bash", "-lc", "kubectl kuttl version >/dev/null 2>&1 || command -v kuttl >/dev/null 2>&1"])
    if res.returncode != 0:
        raise SystemExit(
            "ERROR: KUTTL not found. Install via `just install-cli` or see https://kuttl.dev/docs/cli.html"
        )


def repo_root() -> str:
    root = _run(["git", "rev-parse", "--show-toplevel"]).stdout.strip()
    if not root:
        raise SystemExit("ERROR: must run inside a git repository")
    return root


def parse_exercise_path(exercise_path: str) -> Tuple[str, str]:
    if "/" not in exercise_path:
        raise SystemExit(f"ERROR: expected <domain>/<challenge>, got: {exercise_path}")
    domain, challenge = exercise_path.split("/", 1)
    if not domain or not challenge:
        raise SystemExit(f"ERROR: expected <domain>/<challenge>, got: {exercise_path}")
    return domain, challenge


def _section_is_ignored(header: str) -> bool:
    h = header.lower().strip()
    ignore_terms = [
        "verify",
        "verification",
        "debug",
        "debugging",
        "troubleshooting",
        "notes",
        "tips",
        "one-liner",
        "one liner",
        "key concepts",
        "concepts",
        "reference",
        "summary",
        "best practices",
        "alternative",
        "diagnosis",
    ]
    return any(t in h for t in ignore_terms)


def extract_solution_script(answer_md_path: str) -> str:
    if not os.path.exists(answer_md_path):
        return ""

    with open(answer_md_path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    sections: List[Tuple[str, List[str]]] = []
    current_header = "initial"
    current_lines: List[str] = []
    in_fence = False

    for line in lines:
        if line.strip().startswith("```"):
            in_fence = not in_fence
            current_lines.append(line)
            continue

        if not in_fence and line.startswith("#"):
            sections.append((current_header, current_lines))
            current_header = line.strip("# \n").lower()
            current_lines = []
            continue

        current_lines.append(line)

    sections.append((current_header, current_lines))

    bash_blocks: List[str] = []
    yaml_blocks: List[str] = []

    for header, section_lines in sections:
        if _section_is_ignored(header):
            continue

        fence_lang: Optional[str] = None
        fence_buf: List[str] = []

        for line in section_lines:
            stripped = line.strip()
            if stripped.startswith("```"):
                if fence_lang is None:
                    fence_lang = stripped.strip("`").strip() or ""
                    fence_buf = []
                else:
                    content = "".join(fence_buf).rstrip() + "\n"
                    lang = (fence_lang or "").lower()
                    if lang in ("bash", "sh", "shell"):
                        bash_blocks.append(content)
                    elif lang in ("yaml", "yml"):
                        yaml_blocks.append(content)
                    fence_lang = None
                    fence_buf = []
                continue

            if fence_lang is not None:
                fence_buf.append(line)

    script_parts: List[str] = []

    # YAML blocks are applied directly (many solutions use inline manifests)
    for y in yaml_blocks:
        # Some answer.md files include YAML snippets that are not full Kubernetes objects
        # (e.g., partial spec fragments for `kubectl edit`). Only apply full manifests.
        if not re.search(r"(?m)^\s*apiVersion:\s*\S+\s*$", y):
            continue
        if not re.search(r"(?m)^\s*kind:\s*\S+\s*$", y):
            continue
        script_parts.append("kubectl apply -f - <<'EOF'\n")
        script_parts.append(y)
        script_parts.append("EOF\n\n")

    # Bash blocks are executed as-is (kubectl apply/patch/etc)
    script_parts.extend([b + "\n" for b in bash_blocks])

    script = "".join(script_parts)
    script += extract_watch_namespace_fix(answer_md_path)
    return sanitize_script(script)


def _extract_fenced_blocks(markdown: str) -> List[Tuple[str, str]]:
    blocks: List[Tuple[str, str]] = []
    lines = markdown.splitlines(keepends=True)
    in_fence = False
    fence_lang = ""
    buf: List[str] = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("```"):
            if not in_fence:
                in_fence = True
                fence_lang = stripped.strip("`").strip().lower()
                buf = []
            else:
                blocks.append((fence_lang, "".join(buf)))
                in_fence = False
                fence_lang = ""
                buf = []
            continue
        if in_fence:
            buf.append(line)
    return blocks


def _extract_heredoc_bodies_from_shell(shell_text: str) -> List[str]:
    bodies: List[str] = []
    lines = shell_text.splitlines(keepends=True)
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.search(r"<<\s*(['\"]?)([A-Za-z0-9_]+)\1", line)
        if not m:
            i += 1
            continue
        delim = m.group(2)
        i += 1
        buf: List[str] = []
        while i < len(lines):
            if lines[i].strip() == delim:
                break
            buf.append(lines[i])
            i += 1
        bodies.append("".join(buf))
        while i < len(lines) and lines[i].strip() != delim:
            i += 1
        if i < len(lines) and lines[i].strip() == delim:
            i += 1
    return bodies


def extract_crd_manifests(answer_md_path: str) -> List[str]:
    if not os.path.exists(answer_md_path):
        return []
    with open(answer_md_path, "r", encoding="utf-8") as f:
        md = f.read()

    manifests: List[str] = []
    for lang, content in _extract_fenced_blocks(md):
        text = content
        if lang in ("bash", "sh", "shell"):
            for body in _extract_heredoc_bodies_from_shell(content):
                if re.search(r"(?m)^\s*kind:\s*CustomResourceDefinition\s*$", body):
                    text = body
                    break
            else:
                continue
        elif lang not in ("yaml", "yml"):
            continue

        if not re.search(r"(?m)^\s*apiVersion:\s*\S+\s*$", text):
            continue
        if not re.search(r"(?m)^\s*kind:\s*CustomResourceDefinition\s*$", text):
            continue
        manifests.append(text.strip() + "\n")

    return manifests


def extract_crd_names(manifest_yaml: str) -> List[str]:
    names: List[str] = []
    docs = re.split(r"(?m)^\s*---\s*$", manifest_yaml)
    for doc in docs:
        if not re.search(r"(?m)^\s*kind:\s*CustomResourceDefinition\s*$", doc):
            continue
        m = re.search(r"(?ms)^\s*metadata:\s*\n(?:[ \t].*\n)*?\s*name:\s*([^\s]+)\s*$", doc)
        if m:
            names.append(m.group(1).strip())
    return sorted(set(names))


def wait_for_crds(crd_names: List[str], timeout_seconds: int = 60) -> None:
    for name in crd_names:
        res = _run(["kubectl", "wait", "--for=condition=Established", f"crd/{name}", f"--timeout={timeout_seconds}s"])
        if res.returncode != 0:
            raise SystemExit(res.stderr.strip() or f"ERROR: CRD not established: {name}")


def extract_crossplane_prereqs(answer_md_path: str) -> Tuple[str, List[str]]:
    """
    Some solutions apply a Crossplane XRD + Composition + a claim in one YAML heredoc.
    The claim kind won't exist until the XRD creates its generated CRD, so we pre-apply
    XRD/Composition docs and wait for the generated CRD(s) before running the full script.
    """
    if not os.path.exists(answer_md_path):
        return ("", [])
    with open(answer_md_path, "r", encoding="utf-8") as f:
        md = f.read()

    prereq_docs: List[str] = []
    generated_crds: List[str] = []

    for lang, content in _extract_fenced_blocks(md):
        yamls: List[str] = []
        if lang in ("yaml", "yml"):
            yamls = [content]
        elif lang in ("bash", "sh", "shell"):
            yamls = _extract_heredoc_bodies_from_shell(content)
        else:
            continue

        for y in yamls:
            docs = re.split(r"(?m)^\s*---\s*$", y)
            for doc in docs:
                if not re.search(r"(?m)^\s*apiVersion:\s*\S+\s*$", doc):
                    continue
                kind_m = re.search(r"(?m)^\s*kind:\s*([^\s]+)\s*$", doc)
                if not kind_m:
                    continue
                kind = kind_m.group(1).strip()

                if kind == "CompositeResourceDefinition":
                    prereq_docs.append(doc.strip())
                    group_m = re.search(r"(?m)^\s*group:\s*([^\s]+)\s*$", doc)
                    plural_m = re.search(
                        r"(?ms)^\s*claimNames:\s*\n(?:[ \t].*\n)*?\s*plural:\s*([^\s]+)\s*$",
                        doc,
                    )
                    if group_m and plural_m:
                        generated_crds.append(f"{plural_m.group(1).strip()}.{group_m.group(1).strip()}")
                elif kind == "Composition":
                    prereq_docs.append(doc.strip())

    if not prereq_docs:
        return ("", [])

    yaml = "---\n" + "\n---\n".join([d for d in prereq_docs if d]) + "\n"
    return (yaml, sorted(set(generated_crds)))


def sanitize_script(script: str) -> str:
    out: List[str] = []
    skip_continued = False
    for raw in script.splitlines():
        line = raw.rstrip("\n")
        stripped = line.strip()

        if skip_continued:
            if stripped.endswith("\\"):
                continue
            skip_continued = False
            continue

        if not stripped or stripped.startswith("#"):
            out.append(line)
            continue

        # Drop interactive/editor commands.
        if re.search(r"\b(kubectl\s+edit|vim|vi|nano|emacs)\b", stripped):
            continue

        # Drop multi-line auth checks (diagnostic, and can fail under `set -e`).
        if re.match(r"^\s*kubectl\s+auth\s+can-i\b", line):
            skip_continued = stripped.endswith("\\")
            continue

        # Keep diagnostics but never fail the solve on them.
        if (
            re.match(r"^\s*kubectl\s+(get|describe|logs|auth\s+can-i)\b", line)
            and "||" not in line
            and not stripped.endswith("\\")
        ):
            # Avoid `kubectl get ... -w` hangs; use bounded waits where possible.
            m_rollout_watch = re.match(
                r"^\s*kubectl\s+get\s+rollout\s+([^\s]+)\s+-n\s+([^\s]+)\s+(-w|--watch)\s*$",
                stripped,
            )
            if m_rollout_watch:
                name = m_rollout_watch.group(1)
                ns = m_rollout_watch.group(2)
                out.append(
                    "kubectl wait --for=jsonpath='{.status.phase}'=Healthy "
                    f"rollout/{name} -n {ns} --timeout=240s"
                )
                continue

            # If a solution uses watch on any resource, drop the watch so we don't hang forever.
            if re.search(r"\s(-w|--watch)\b", stripped):
                no_watch = re.sub(r"\s(-w|--watch)(=[^\\s]+)?\b", "", line).rstrip()
                out.append(f"{no_watch} || true")
                continue

            out.append(f"{line} || true")
            continue

        # Avoid nested "just" calls from solutions.
        if stripped.startswith("just "):
            continue

        # Avoid non-portable in-place sed usage; normalize `sed -i ...` to a helper.
        if re.match(r"^\s*sed\s+-i\b", line):
            rest = re.sub(r"^\s*sed\s+-i\b", "", line).lstrip()
            out.append(f"sedi {rest}".rstrip())
            continue

        # Avoid requiring jq for JSON string escaping in solutions.
        if "jq -Rs" in line or re.search(r"^\s*JSON=\$\(", line):
            continue
        if re.search(r"^\s*kubectl\s+patch\s+configmap\b", line) and "jq -Rs" in line:
            continue

        # Make `kubectl run` idempotent for common "test pod" patterns in answers.
        m = re.match(r"^\s*kubectl\s+run\s+([^\s]+)\b.*\s-n\s+([^\s]+)\b", line)
        if m:
            pod = m.group(1)
            ns = m.group(2)
            out.append(f"kubectl delete pod {pod} -n {ns} --ignore-not-found=true >/dev/null 2>&1 || true")
            out.append(line)
            continue

        out.append(line)

    return "\n".join(out).strip() + "\n"


def extract_watch_namespace_fix(answer_md_path: str) -> str:
    if not os.path.exists(answer_md_path):
        return ""
    with open(answer_md_path, "r", encoding="utf-8") as f:
        md = f.read()

    if "WATCH_NAMESPACE" not in md:
        return ""

    # If the answer instructs editing a deployment to fix WATCH_NAMESPACE, generate an automatable equivalent.
    m = re.search(r"(?m)^\s*kubectl\s+edit\s+deployment\s+([^\s]+)\s+-n\s+([^\s]+)\s*$", md)
    if not m:
        return ""

    deploy = m.group(1)
    ns = m.group(2)

    # Prefer setting to the correct namespace (safe alternative to deleting the variable).
    return f"kubectl set env deployment/{deploy} -n {ns} WATCH_NAMESPACE={ns} --overwrite\n"


def get_timeout_seconds(domain_dir: str) -> int:
    # Prefer the domain config if present.
    cfg = os.path.join(domain_dir, "kuttl-test.yaml")
    if not os.path.exists(cfg):
        return DEFAULT_TIMEOUT_SECONDS
    with open(cfg, "r", encoding="utf-8") as f:
        for line in f:
            m = re.match(r"^\s*timeout:\s*(\d+)\s*$", line)
            if m:
                return int(m.group(1))
    return DEFAULT_TIMEOUT_SECONDS


def extract_namespace_from_setup(setup_yaml_path: str) -> str:
    if not os.path.exists(setup_yaml_path):
        return ""
    with open(setup_yaml_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Look for an explicit Namespace object first.
    parts = re.split(r"(?m)^\s*---\s*$", content)
    for doc in parts:
        if not re.search(r"(?m)^\s*kind:\s*Namespace\s*$", doc):
            continue
        # Find the first name in that document (usually metadata.name).
        m = re.search(r"(?m)^\s*name:\s*([a-z0-9]([-a-z0-9]*[a-z0-9])?)\s*$", doc)
        if m:
            return m.group(1)

    # Fallback: infer from a namespace: field (common in manifests).
    m2 = re.search(r"(?m)^\s*namespace:\s*([a-z0-9]([-a-z0-9]*[a-z0-9])?)\s*$", content)
    return m2.group(1) if m2 else ""


def extract_owned_namespace(setup_yaml_path: str) -> str:
    """Namespace the challenge creates itself, and may therefore delete on cleanup.

    Unlike extract_namespace_from_setup, this never falls back to a bare `namespace:`
    reference: challenges that place resources in a shared platform namespace (such as
    `monitoring`) must not delete it, or cleanup takes the platform down with it.
    """
    if not os.path.exists(setup_yaml_path):
        return ""
    with open(setup_yaml_path, "r", encoding="utf-8") as f:
        content = f.read()

    for doc in re.split(r"(?m)^\s*---\s*$", content):
        if not re.search(r"(?m)^\s*kind:\s*Namespace\s*$", doc):
            continue
        m = re.search(r"(?m)^\s*name:\s*([a-z0-9]([-a-z0-9]*[a-z0-9])?)\s*$", doc)
        if m:
            return m.group(1)
    return ""


def kubectl_apply(file_path: str) -> None:
    validate_disabled = False
    res = _run(["kubectl", "apply", "-f", file_path])
    if res.returncode != 0 and re.search(r"failed to download openapi|error validating data", res.stderr or ""):
        # Some environments block kubectl OpenAPI schema download; fall back to client-side validation disabled.
        validate_disabled = True
        res = _run(["kubectl", "apply", "-f", file_path, "--validate=false"])
    if res.returncode == 0:
        return

    # If the file includes CRDs, kubectl may fail applying subsequent CRs until the CRD is Established.
    # Retry once after waiting for CRDs in the same file.
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            content = f.read()
    except OSError:
        content = ""

    crd_names = extract_crd_names(content) if content else []
    if crd_names and re.search(r"no matches for kind|ensure CRDs are installed first", (res.stderr or "")):
        wait_for_crds(crd_names)
        res2 = (
            _run(["kubectl", "apply", "-f", file_path, "--validate=false"])
            if validate_disabled
            else _run(["kubectl", "apply", "-f", file_path])
        )
        if res2.returncode == 0:
            return
        raise SystemExit(res2.stderr.strip() or f"ERROR: kubectl apply failed after CRD wait: {file_path}")

    raise SystemExit(res.stderr.strip() or f"ERROR: kubectl apply failed: {file_path}")


def kubectl_delete(file_path: str) -> None:
    _run(["kubectl", "delete", "-f", file_path, "--ignore-not-found=true"])


def kubectl_delete_namespace(ns: str) -> None:
    if not ns:
        return
    _run(["kubectl", "delete", "namespace", ns, "--ignore-not-found=true", "--wait=false"])


def run_script(script: str, timeout_seconds: Optional[int]) -> None:
    if not script.strip():
        raise SystemExit("ERROR: extracted solution script is empty")
    prelude = """set -euo pipefail
sedi() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}
"""
    full = prelude + script + "\n"
    res = _run(["bash", "-s"], input_text=full, timeout=timeout_seconds)
    if res.returncode != 0:
        raise SystemExit(res.stderr.strip() or f"ERROR: solution script failed (rc={res.returncode})")


def run_kuttl(domain_dir: str, challenge: str, timeout_seconds: int, namespace: str, debug: bool) -> None:
    cmd = [
        "kubectl",
        "kuttl",
        "test",
        domain_dir,
        "--config",
        os.path.join(domain_dir, "kuttl-test.yaml"),
        "--test",
        challenge,
        "--timeout",
        str(timeout_seconds),
    ]
    if namespace:
        cmd.extend(["--namespace", namespace])
    rc = _run_stream(cmd, timeout=timeout_seconds + 60, debug=debug)
    if rc != 0:
        raise SystemExit(f"ERROR: KUTTL failed (rc={rc})")


def challenges_from_exam(exam_yaml_path: str) -> List[str]:
    try:
        import yaml  # type: ignore
    except Exception:
        require_tool("yq")
        res = _run(["yq", "-r", ".sections[].challenge", exam_yaml_path])
        if res.returncode != 0:
            raise SystemExit(res.stderr.strip() or f"ERROR: failed to parse exam file: {exam_yaml_path}")
        out: List[str] = []
        for line in res.stdout.splitlines():
            p = line.strip()
            if p:
                out.append(p)
        return out

    try:
        with open(exam_yaml_path, "r", encoding="utf-8") as f:
            exam = yaml.safe_load(f)
    except OSError as e:
        raise SystemExit(f"ERROR: failed to read exam file: {exam_yaml_path} ({e})")

    if not isinstance(exam, dict) or not isinstance(exam.get("sections"), list):
        raise SystemExit(f"ERROR: invalid exam YAML (expected mapping with `sections` list): {exam_yaml_path}")

    out: List[str] = []
    for section in exam["sections"]:
        if not isinstance(section, dict):
            continue
        ch = section.get("challenge")
        if isinstance(ch, str) and ch.strip():
            out.append(ch.strip())
    if not out:
        raise SystemExit(f"ERROR: no challenges found under `.sections[].challenge`: {exam_yaml_path}")
    return out


def solve_challenge(exercise_path: str, *, validate: bool, cleanup: bool, exec_timeout: Optional[int], debug: bool) -> None:
    root = repo_root()
    domain, challenge = parse_exercise_path(exercise_path)

    domain_dir = os.path.join(root, "challenges", domain)
    exercise_dir = os.path.join(domain_dir, challenge)
    setup_yaml = os.path.join(exercise_dir, "setup.yaml")
    answer_md = os.path.join(exercise_dir, "answer.md")

    if not os.path.isdir(exercise_dir):
        raise SystemExit(f"ERROR: challenge not found: {exercise_dir}")
    if not os.path.exists(setup_yaml):
        raise SystemExit(f"ERROR: missing setup file: {setup_yaml}")

    ns = extract_namespace_from_setup(setup_yaml)
    owned_ns = extract_owned_namespace(setup_yaml)

    print(f"==> {exercise_path}")
    kubectl_apply(setup_yaml)

    try:
        crd_manifests = extract_crd_manifests(answer_md)
        if crd_manifests:
            crd_names: List[str] = []
            for m in crd_manifests:
                res = _run(["kubectl", "apply", "-f", "-"], input_text=m, timeout=exec_timeout)
                if res.returncode != 0 and re.search(r"failed to download openapi|error validating data", res.stderr or ""):
                    res = _run(
                        ["kubectl", "apply", "-f", "-", "--validate=false"], input_text=m, timeout=exec_timeout
                    )
                if res.returncode != 0:
                    raise SystemExit(res.stderr.strip() or "ERROR: failed to apply CRD manifest")
                crd_names.extend(extract_crd_names(m))
            if crd_names:
                wait_for_crds(crd_names)

        prereq_yaml, generated_crds = extract_crossplane_prereqs(answer_md)
        if prereq_yaml:
            res = _run(["kubectl", "apply", "-f", "-"], input_text=prereq_yaml, timeout=exec_timeout)
            if res.returncode != 0 and re.search(r"failed to download openapi|error validating data", res.stderr or ""):
                res = _run(
                    ["kubectl", "apply", "-f", "-", "--validate=false"], input_text=prereq_yaml, timeout=exec_timeout
                )
            if res.returncode != 0:
                raise SystemExit(res.stderr.strip() or "ERROR: failed to apply Crossplane prereqs")
            if generated_crds:
                wait_for_crds(generated_crds, timeout_seconds=120)

        script = extract_solution_script(answer_md)
        if not script.strip():
            raise SystemExit(f"ERROR: no runnable solution found in {answer_md}")

        run_script(script, timeout_seconds=exec_timeout)

        if validate:
            timeout = get_timeout_seconds(domain_dir)
            print("  [Validate] Running KUTTL...")
            run_kuttl(domain_dir, challenge, timeout_seconds=timeout, namespace=ns, debug=debug)
            print("  ✅ PASS")
    finally:
        if cleanup:
            kubectl_delete(setup_yaml)
            kubectl_delete_namespace(owned_ns)


def main() -> None:
    parser = argparse.ArgumentParser(description="Auto-solve challenges by replaying answer.md and running KUTTL.")
    parser.add_argument("target", nargs="?", help="Challenge (domain/name) or Exam (exam-1) to solve.")
    group = parser.add_mutually_exclusive_group(required=False)
    group.add_argument("--challenge", help="Solve a single challenge: <domain>/<challenge>")
    group.add_argument("--exam", help="Solve all challenges in an exam YAML (e.g. exams/exam-1.yaml)")
    group.add_argument("--all-exams", action="store_true", help="Solve all exam YAMLs under exams/*.yaml")
    parser.add_argument("--no-validate", action="store_true", help="Skip KUTTL validation")
    parser.add_argument("--no-cleanup", action="store_true", help="Skip cleanup after solving")
    parser.add_argument(
        "--exec-timeout",
        type=int,
        default=300,
        help="Timeout (seconds) for executing the extracted solution script (default: 300).",
    )
    parser.add_argument(
        "--print-script",
        action="store_true",
        help="Print extracted solution script for --challenge (does not execute).",
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Enable verbose output (disable log filtering).",
    )
    args = parser.parse_args()

    root = repo_root()

    if args.print_script:
        target = args.target or args.challenge
        if not target:
            raise SystemExit("--print-script requires a challenge")
        domain, challenge = parse_exercise_path(target)
        answer_md = os.path.join(root, "challenges", domain, challenge, "answer.md")
        script = extract_solution_script(answer_md)
        print("--- extracted script ---")
        print(script.rstrip())
        print("--- end script ---")
        raise SystemExit(0 if script.strip() else 1)

    require_tool("kubectl")
    require_kube_context()
    require_kuttl()

    validate = not args.no_validate
    cleanup = not args.no_cleanup
    exec_timeout = int(args.exec_timeout) if args.exec_timeout else None
    debug = args.debug

    exercise_paths: List[str] = []

    # Determine target from positional arg or flags
    target_challenge = args.challenge
    target_exam = args.exam
    
    if args.target:
        if "/" in args.target:
            target_challenge = args.target
        else:
            target_exam = args.target

    if target_challenge:
        exercise_paths = [target_challenge]
    elif target_exam:
        exam_path = target_exam if os.path.isabs(target_exam) else os.path.join(root, target_exam)
        
        # Try resolving exam path if it doesn't exist
        if not os.path.exists(exam_path):
            candidates = [
                os.path.join(root, "exams", target_exam),
                os.path.join(root, "exams", f"{target_exam}.yaml"),
                os.path.join(root, "exams", f"exam-{target_exam}.yaml"),
                os.path.join(root, "exams", f"domain-{target_exam}.yaml"),
            ]
            for cand in candidates:
                if os.path.exists(cand):
                    exam_path = cand
                    break
                    
        exercise_paths = challenges_from_exam(exam_path)
    elif args.all_exams:
        exam_dir = os.path.join(root, "exams")
        exams = sorted([os.path.join(exam_dir, f) for f in os.listdir(exam_dir) if f.endswith(".yaml")])
        for exam in exams:
            exercise_paths.extend(challenges_from_exam(exam))
    else:
        parser.print_help()
        raise SystemExit(1)

    for ex in exercise_paths:
        solve_challenge(ex, validate=validate, cleanup=cleanup, exec_timeout=exec_timeout, debug=debug)


if __name__ == "__main__":
    main()
