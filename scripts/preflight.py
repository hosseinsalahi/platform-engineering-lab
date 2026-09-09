#!/usr/bin/env python3
import argparse
import sys
from pathlib import Path
import yaml


def iter_setup_files(root: Path):
    # Validate both legacy `setup.yaml` (used by run-exercise.sh) and
    # KUTTL step-compatible `00-setup.yaml` (used by `kubectl kuttl test`).
    for p in root.rglob('setup.yaml'):
        # only consider under challenges/
        try:
            p.relative_to(root / 'challenges')
        except Exception:
            continue
        yield p

    for p in (root / 'challenges').rglob('00-setup.yaml'):
        yield p


def iter_assert_files(root: Path):
    for p in (root / 'challenges').rglob('*-assert.yaml'):
        # exclude kuttl suite configs
        if p.name.endswith('kuttl-test.yaml'):
            continue
        yield p


def flatten_keys(d, path=None):
    if path is None:
        path = []
    if isinstance(d, dict):
        for k, v in d.items():
            yield path + [str(k)], v
            yield from flatten_keys(v, path + [str(k)])
    elif isinstance(d, list):
        for i, v in enumerate(d):
            yield from flatten_keys(v, path + [str(i)])


def load_docs(p: Path):
    try:
        with p.open() as f:
            return list(yaml.safe_load_all(f))
    except Exception as e:
        return None


# Namespaces owned by the platform install (or by Kubernetes itself). A challenge
# that declares one of these in setup.yaml also deletes it on cleanup, because
# cleanup runs `kubectl delete -f setup.yaml` - which uninstalls whatever lives
# there. 4-architecture/network-policy did exactly this to `monitoring`, taking
# kube-prometheus-stack with it and breaking three other challenges.
RESERVED_NAMESPACES = {
    'monitoring', 'istio-system', 'argocd', 'argo-rollouts', 'kyverno',
    'gatekeeper-system', 'jaeger', 'opencost', 'crossplane-system',
    'external-secrets', 'tekton-pipelines', 'tekton-pipelines-resolvers',
    'kube-system', 'kube-public', 'kube-node-lease', 'default',
    'local-path-storage',
}


def check_reserved_namespace(doc):
    """Return the reserved namespace this doc declares, if any."""
    if not isinstance(doc, dict) or doc.get('kind') != 'Namespace':
        return None
    name = (doc.get('metadata') or {}).get('name')
    return name if name in RESERVED_NAMESPACES else None


def check_status_block(doc):
    # Top-level status in applied manifests is almost always invalid
    return isinstance(doc, dict) and 'status' in doc


def find_invalid_field(doc):
    # Heuristic: any key literally named 'invalidField'
    for keys, _ in flatten_keys(doc):
        if keys and keys[-1] == 'invalidField':
            return True
    return False


def collect_crd_groups(docs):
    crd_groups = []
    for idx, doc in enumerate(docs):
        if not isinstance(doc, dict):
            continue
        if doc.get('kind') == 'CustomResourceDefinition':
            spec = doc.get('spec', {})
            group = spec.get('group')
            names = spec.get('names', {})
            kind = names.get('kind')
            if group:
                crd_groups.append((idx, group, kind))
    return crd_groups


def apigroup_from_apiversion(api_version: str):
    # core group has no '/'
    if not api_version:
        return None
    if '/' not in api_version:
        return ''
    return api_version.split('/')[0]


def check_crd_order(docs):
    errors = []
    crds = collect_crd_groups(docs)
    if not crds:
        return errors
    for idx, doc in enumerate(docs):
        if not isinstance(doc, dict):
            continue
        if doc.get('kind') == 'CustomResourceDefinition':
            continue
        api_group = apigroup_from_apiversion(doc.get('apiVersion', ''))
        if api_group is None:
            continue
        for crd_idx, group, _ in crds:
            if api_group == group and idx < crd_idx:
                errors.append(
                    f"CR of group '{group}' appears before its CRD (doc {idx+1} before {crd_idx+1})"
                )
    return errors


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Validate challenge setup and assert YAMLs for common issues."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Repository root (defaults to repo containing this script).",
    )
    args = parser.parse_args(argv)

    repo = args.root.resolve()
    challenges = repo / 'challenges'
    if not challenges.exists():
        print('No challenges directory found', file=sys.stderr)
        return 1

    error_count = 0
    warn_count = 0

    for setup in iter_setup_files(repo):
        docs = load_docs(setup)
        if docs is None:
            print(f"ERROR: Failed to parse YAML: {setup}")
            error_count += 1
            continue

        file_errors = []
        file_warnings = []

        # status blocks
        for i, d in enumerate(docs):
            if check_status_block(d):
                file_errors.append(f"doc {i+1}: top-level 'status' not allowed in setup manifests")

        # shared namespaces the challenge would delete on cleanup
        for i, d in enumerate(docs):
            reserved = check_reserved_namespace(d)
            if reserved:
                file_errors.append(
                    f"doc {i+1}: declares the shared namespace '{reserved}'. Cleanup deletes "
                    f"everything in setup.yaml, so this would uninstall whatever the platform "
                    f"runs there. Use a challenge-scoped name (cnpe-*) instead."
                )

        # invalidField heuristic
        for i, d in enumerate(docs):
            try:
                if isinstance(d, dict) and find_invalid_field(d):
                    file_warnings.append(f"doc {i+1}: contains key 'invalidField' (likely schema-invalid)")
            except Exception:
                continue

        # CRD order
        crd_errors = check_crd_order(docs)
        file_errors.extend(crd_errors)

        if file_errors or file_warnings:
            print(f"== {setup}")
            for msg in file_errors:
                print(f"ERROR: {msg}")
            for msg in file_warnings:
                print(f"WARN: {msg}")

        error_count += len(file_errors)
        warn_count += len(file_warnings)

    # Validate assert files
    for af in iter_assert_files(repo):
        docs = load_docs(af)
        if docs is None:
            print(f"ERROR: Failed to parse YAML: {af}")
            error_count += 1
            continue

        file_errors = []
        file_warnings = []

        for i, d in enumerate(docs):
            if not isinstance(d, dict):
                continue
            api = d.get('apiVersion', '') or ''
            kind = d.get('kind', '') or ''

            # Skip KUTTL TestAssert/TestStep resources
            if kind in ('TestAssert', 'TestStep') and api.startswith('kuttl.dev/'):
                continue

            # Resource assertions should have apiVersion/kind/metadata
            if not api:
                file_errors.append(f"doc {i+1}: missing apiVersion")
            if not kind:
                file_errors.append(f"doc {i+1}: missing kind")
            md = d.get('metadata', {}) if isinstance(d.get('metadata'), dict) else {}
            if not md.get('name'):
                file_warnings.append(f"doc {i+1}: metadata.name is empty (KUTTL matching may fail)")

            # Warn for unexpected top-level keys beyond expected
            # Allow common K8s resource top-level fields found in asserts
            allowed = {
                'apiVersion', 'kind', 'metadata', 'spec', 'status',
                # RBAC
                'rules', 'subjects', 'roleRef',
                # Configs/Secrets
                'data', 'stringData', 'type'
            }
            extra_keys = [k for k in d.keys() if k not in allowed]
            if extra_keys:
                file_warnings.append(
                    f"doc {i+1}: unexpected top-level keys present: {', '.join(sorted(extra_keys))}"
                )

        if file_errors or file_warnings:
            print(f"== {af}")
            for msg in file_errors:
                print(f"ERROR: {msg}")
            for msg in file_warnings:
                print(f"WARN: {msg}")

        error_count += len(file_errors)
        warn_count += len(file_warnings)

    if error_count:
        print(f"\nPreflight failed: {error_count} error(s), {warn_count} warning(s)")
        return 1
    else:
        print(f"Preflight passed: {warn_count} warning(s)")
        return 0


if __name__ == '__main__':
    sys.exit(main())
