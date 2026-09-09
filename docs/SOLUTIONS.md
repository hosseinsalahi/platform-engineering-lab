# Cloud Native Platform Engineering Guide

A knowledge reference for platform engineers, organized by the practical domains used in
this repo. Each chapter explains the **why** behind platform patterns, with exercises to
reinforce understanding. It is not structured to the CNPA exam's own domain weighting —
see the README for that mapping.

### Core Principles (CNCF Platforms Whitepaper)

- **Thinnest Viable Platform**: Build the smallest layer that accelerates delivery
- **Self-Service**: Users provision capabilities autonomously, without tickets
- **Reduced Cognitive Load**: Hide complexity behind simple interfaces
- **Secure by Default**: Compliance and validation built into the platform

Success is measured by DORA metrics: deployment frequency, lead time, MTTR, change failure rate.

---

## Chapter 1: GitOps and Continuous Delivery (25%)

### Why GitOps?

GitOps treats Git as the single source of truth for declarative infrastructure and applications. This pattern provides:

- **Auditability**: Every change is a commit with author, timestamp, and context
- **Rollback**: `git revert` undoes any change
- **Consistency**: Drift detection ensures clusters match desired state
- **Security**: No direct cluster access needed; changes flow through Git

### Pattern: Application Delivery with ArgoCD

ArgoCD continuously reconciles cluster state with Git repositories. When applications fail to sync, common causes include:

- Repository URL or credentials misconfigured
- Target revision (branch/tag) doesn't exist
- Path to manifests incorrect
- Destination namespace doesn't exist

**Exercise:** [gitops-fix](../challenges/1-gitops/broken-sync/answer.md)

### Pattern: Multi-Environment Promotion with ApplicationSets

ApplicationSets solve the "many similar apps" problem. Instead of maintaining separate Application manifests for dev/staging/prod, you define a template and generator:

```yaml
generators:
  - list:
      elements:
        - env: dev
        - env: staging
        - env: prod
template:
  metadata:
    name: 'myapp-{{env}}'
```

This creates three Applications from one definition. When you update the template, all environments update. Generators can also pull from Git directories, cluster labels, or external APIs.

**Exercise:** [gitops-appset](../challenges/1-gitops/env-promotion/answer.md)

### Pattern: Progressive Delivery

Deploying all traffic to a new version instantly is risky. Progressive delivery strategies reduce blast radius:

**Canary**: Route a percentage of traffic to new version, gradually increasing:
```
5% → 25% → 50% → 100%
```
Automated analysis can pause/rollback if error rates spike.

**Blue/Green**: Run both versions simultaneously, switch traffic atomically:
- Blue (current) receives all traffic
- Green (new) is deployed and tested
- Traffic switches from Blue → Green instantly
- Blue kept for quick rollback

Argo Rollouts implements both patterns with Kubernetes-native CRDs.

**Exercises:**
- [gitops-canary](../challenges/1-gitops/canary-rollout/answer.md)
- [gitops-bluegreen](../challenges/1-gitops/bluegreen/answer.md)
- [gitops-istio](../challenges/1-gitops/istio-canary/answer.md)

### Pattern: Event-Driven CI/CD with Tekton

Tekton provides Kubernetes-native CI/CD primitives:

- **Task**: A series of steps (containers) that run sequentially
- **Pipeline**: DAG of Tasks with inputs/outputs
- **TriggerTemplate**: Defines what PipelineRun to create when triggered
- **TriggerBinding**: Extracts parameters from webhook payloads using JSONPath
- **EventListener**: HTTP endpoint that receives webhook events (requires additional infrastructure)

The key to Tekton Triggers is the parameter flow: TriggerBinding extracts data from events (like GitHub webhooks) and passes it to TriggerTemplate, which creates a PipelineRun with those parameters.

**Exercise:** [gitops-tekton](../challenges/1-gitops/tekton-pipeline/answer.md) - Focuses on TriggerTemplate/TriggerBinding configuration

---

## Chapter 2: Platform APIs and Self-Service (25%)

### Why Platform APIs?

Platform teams can't scale by handling tickets. Self-service APIs let developers provision infrastructure safely while platform teams focus on the thinnest viable abstraction layer:

- **Guardrails**: API schemas enforce valid inputs
- **Abstraction**: Hide cloud complexity behind simple interfaces
- **Consistency**: Every database provisioned the same way
- **Auditability**: CR creation is logged in etcd

### Pattern: Custom Resource Definitions

CRDs extend the Kubernetes API with your own resource types. A well-designed CRD:

1. **Validates input** with OpenAPI schemas and CEL rules
2. **Shows status** via the status subresource (updated separately from spec)
3. **Prints nicely** with additionalPrinterColumns for `kubectl get`

The status subresource is critical—it allows controllers to update status without triggering spec validation, and prevents users from manually editing status.

**Exercises:**
- [platform-crd](../challenges/2-apis/platform-crd/answer.md)
- [platform-crd-status](../challenges/2-apis/crd-status/answer.md)

### Pattern: Operators for Automation

Operators encode operational knowledge in software. They watch for CRs and take action:

```
User creates DatabaseClaim CR
    ↓
Operator sees new CR (watch)
    ↓
Operator provisions database (reconcile)
    ↓
Operator updates CR status
```

Common operator failures:
- **RBAC**: Missing permissions to watch/update resources
- **Leader election**: Multiple replicas fighting for control
- **Finalizers**: Stuck deletion because cleanup failed

**Exercise:** [platform-operator](../challenges/2-apis/operator-rbac/answer.md)

### Pattern: Crossplane for Self-Service

Crossplane extends the operator pattern to provision any infrastructure. Key concepts:

- **XRD (CompositeResourceDefinition)**: Defines your platform API (e.g., DatabaseRequest)
- **Composition**: Maps your API to actual infrastructure resources via pipeline mode
- **Claim**: Namespaced resource developers create
- **Functions**: Composition functions transform and generate resources dynamically

**Crossplane v2 Pipeline Mode:**

In Crossplane v2, Compositions use pipeline mode with functions instead of the deprecated resources field:

```yaml
spec:
  mode: Pipeline  # New in v2
  pipeline:
    - step: patch-and-transform
      functionRef:
        name: function-patch-and-transform
      input:
        apiVersion: pt.fn.crossplane.io/v1beta1
        kind: Resources
        resources:
          - name: my-resource
            base: {...}
```

Benefits of pipeline mode:
- Functions can be chained for complex transformations
- Better separation of composition logic from resource templates
- More flexible and composable than v1 resources approach

The power is abstraction—developers request a "small postgres database" without knowing if it's RDS, Cloud SQL, or a StatefulSet.

**Exercise:** [platform-selfservice](../challenges/2-apis/crossplane-workflow/answer.md) - Uses Crossplane v2 pipeline mode

---

## Chapter 3: Observability and Operations (20%)

### The Three Pillars

- **Metrics**: Aggregated numerical data (Prometheus)
- **Logs**: Discrete events with context (Loki, ELK)
- **Traces**: Request flow across services (Jaeger)

Each answers different questions:
- Metrics: "What is the error rate?"
- Logs: "What error message did we get?"
- Traces: "Where did this request spend time?"

### Pattern: Prometheus Monitoring

Prometheus scrapes metrics endpoints and stores time-series data. Key concepts:

- **PromQL**: Query language for metrics (`rate(http_requests_total[5m])`)
- **Recording rules**: Pre-compute expensive queries
- **Alerting rules**: Fire alerts when conditions met

Common issues:
- Scrape target down (check ServiceMonitor labels)
- PromQL syntax errors
- Missing labels in aggregations

**Exercises:**
- [obs-monitor](../challenges/3-observability/broken-servicemonitor/answer.md)
- [obs-grafana](../challenges/3-observability/grafana-dashboard/answer.md)
- [obs-alerting](../challenges/3-observability/prometheus-alert/answer.md)

### Pattern: Distributed Tracing

In microservices, a single request touches many services. Tracing shows the full journey:

```
Frontend → API Gateway → Order Service → Payment Service → Database
   50ms       10ms           100ms           200ms           50ms
```

OpenTelemetry standardizes trace propagation. Key environment variables:
- `OTEL_SERVICE_NAME`: Identifies this service in traces
- `OTEL_EXPORTER_OTLP_ENDPOINT`: Where to send traces
- `OTEL_PROPAGATORS`: How context flows between services

**Exercise:** [obs-tracing](../challenges/3-observability/jaeger-trace/answer.md)

### Pattern: Cost Management

Observability extends beyond system health to business metrics. The DORA framework measures platform effectiveness: deployment frequency, lead time for changes, time to restore (MTTR), and change failure rate.

OpenCost tracks Kubernetes spending by:

- **Namespace**: Team/project allocation
- **Label**: Environment, app, cost-center
- **Resource**: CPU, memory, storage

Effective cost allocation requires consistent labeling conventions enforced by policy.

**Exercise:** [obs-cost](../challenges/3-observability/cost-allocation/answer.md)

### Pattern: Incident Diagnosis

Systematic troubleshooting approach:

1. **Events**: `kubectl describe pod` shows scheduling, image pull, probe failures
2. **Logs**: `kubectl logs` shows application errors
3. **Status**: Pod phase, conditions, container states
4. **Resources**: OOMKilled, CPU throttling

Common failure patterns:
- `ImagePullBackOff`: Image doesn't exist or registry auth failed
- `CrashLoopBackOff`: Container starts then exits (check logs)
- `Pending`: No node can schedule (resources, taints, affinity)

**Exercise:** [obs-incident](../challenges/3-observability/incident-fix/answer.md)

---

## Chapter 4: Platform Architecture (15%)

### Pattern: Network Isolation

Kubernetes networks are flat by default—any pod can reach any pod. NetworkPolicies add segmentation:

- **Default deny**: Start by blocking all traffic
- **Allow specific**: Whitelist required communication
- **Egress control**: Prevent data exfiltration

Multi-tenant isolation requires policies that:
1. Allow intra-namespace communication
2. Block inter-namespace communication
3. Allow DNS (kube-system port 53)
4. Allow ingress controller access

**Exercise:** [arch-networkpolicy](../challenges/4-architecture/network-policy/answer.md)

### Pattern: Storage Configuration

StorageClasses abstract storage provisioning:

- **Provisioner**: What creates the volume (cloud provider, CSI driver)
- **ReclaimPolicy**: What happens when PVC deleted
  - `Delete`: Volume deleted (dev/test)
  - `Retain`: Volume preserved (production data)
- **VolumeBindingMode**:
  - `Immediate`: Provision when PVC created
  - `WaitForFirstConsumer`: Provision when pod scheduled (topology-aware)

`WaitForFirstConsumer` is critical for multi-zone clusters—it ensures the volume is created in the same zone as the pod.

**Exercise:** [arch-storage](../challenges/4-architecture/storage-class/answer.md)

### Pattern: Resource Management

Without limits, one team can consume entire cluster. ResourceQuota and LimitRange provide guardrails:

**ResourceQuota**: Namespace-level caps
- Total CPU/memory requests and limits
- Number of pods, services, PVCs

**LimitRange**: Per-pod/container defaults and constraints
- Default requests/limits if not specified
- Min/max allowed values

Together they ensure fair sharing and prevent runaway workloads.

**Exercise:** [arch-quota](../challenges/4-architecture/resource-quota/answer.md)

### Pattern: Service Mesh Traffic Management

Service meshes like Istio provide advanced traffic control:

**VirtualService**: Route rules
- Traffic splitting (canary)
- Header-based routing (A/B testing)
- Retries and timeouts

**DestinationRule**: Backend configuration
- Subsets (version labels)
- Connection pool settings
- Load balancing algorithm

Traffic splitting enables risk-free deployments:
```yaml
route:
  - destination: {subset: stable}
    weight: 90
  - destination: {subset: canary}
    weight: 10
```

**Exercise:** [arch-mesh](../challenges/4-architecture/service-mesh/answer.md)
**Exercise:** [arch-fault](../challenges/4-architecture/istio-fault-injection/answer.md)
**Exercise:** [arch-pdb](../challenges/4-architecture/pod-disruption-budget/answer.md)

---

## Chapter 5: Security and Policy Enforcement (15%)

### Defense in Depth

Security isn't one control—it's layers:

1. **Admission**: Block bad configs before they're created
2. **Runtime**: Detect and prevent malicious behavior
3. **Network**: Limit communication paths
4. **Identity**: Authenticate and authorize all requests

### Pattern: Policy Engines

Kyverno and OPA/Gatekeeper enforce policies at admission time:

- **Validate**: Reject non-compliant resources
- **Mutate**: Add defaults (labels, security contexts)
- **Generate**: Create related resources automatically

Example policies:
- Require resource limits on all containers
- Block privileged containers
- Enforce image registry whitelist
- Add default network policies

**Exercises:**
- [security-policy](../challenges/5-security/kyverno-policy/answer.md)
- [security-gatekeeper](../challenges/5-security/gatekeeper-constraint/answer.md)
- [security-secrets](../challenges/5-security/external-secrets/answer.md)

### Pattern: RBAC

Kubernetes RBAC controls who can do what:

- **Role**: Defines permissions (verbs on resources)
- **RoleBinding**: Grants Role to subjects (users, groups, service accounts)
- **ClusterRole/ClusterRoleBinding**: Cluster-wide equivalents

Common issues:
- Missing verbs (`list` but not `watch`)
- Wrong apiGroup (custom resources need their group)
- Namespace mismatch (Role vs ClusterRole)

Debug with: `kubectl auth can-i <verb> <resource> --as=<user>`

**Exercise:** [security-rbac](../challenges/5-security/rbac-fix/answer.md)
**Exercise:** [security-rbac-min](../challenges/5-security/rbac-minimal/answer.md)

### Pattern: Pod Security Standards

PSS replaces PodSecurityPolicies with namespace-level controls:

**Levels:**
- `privileged`: No restrictions (system workloads)
- `baseline`: Prevents known privilege escalations
- `restricted`: Hardened, best practices

**Modes:**
- `enforce`: Reject violating pods
- `warn`: Allow but warn
- `audit`: Log violations

Restricted requires:
- `runAsNonRoot: true`
- `allowPrivilegeEscalation: false`
- `capabilities: {drop: [ALL]}`
- `seccompProfile: {type: RuntimeDefault}`

**Exercise:** [security-pss](../challenges/5-security/pod-security/answer.md)

### Pattern: mTLS with Service Mesh

Service-to-service communication should be encrypted and authenticated. Istio provides automatic mTLS:

**PeerAuthentication**: Require mTLS for incoming traffic
```yaml
spec:
  mtls:
    mode: STRICT  # Only accept mTLS connections
```

**DestinationRule**: Use mTLS for outgoing traffic
```yaml
spec:
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL  # Use Istio-managed certificates
```

With both configured, all service communication is encrypted with automatic certificate rotation.

**Exercise:** [security-mtls](../challenges/5-security/istio-mtls/answer.md)

---

## Chapter 6: Scalability

### Why Scalability?

Platform teams must ensure applications can handle traffic spikes without manual intervention. Kubernetes provides Horizontal Pod Autoscaling (HPA) to scale pods based on metrics.

### Pattern: Horizontal Pod Autoscaling

The HPA controller monitors metrics (usually CPU/Memory from Metrics Server) and adjusts the replica count:

```yaml
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 50
```

Key considerations:
- **Resource Requests**: HPA requires CPU requests to be set on containers.
- **Cool-down**: Prevents "flapping" by waiting before scaling down.

**Exercise:** [scal-hpa](../challenges/6-scalability/hpa-cpu/answer.md)

---

## Chapter 7: Packaging

### Why Packaging?

Directly managing raw YAML manifests is error-prone and doesn't scale. Packaging tools like Helm and Kustomize allow for template reuse and environment-specific configuration.

### Pattern: Helm Templating

Helm is a package manager that uses Go templates to generate manifests. It provides:
- **Abstraction**: Hide complex YAML behind simple `values.yaml` files.
- **Version Control**: Manage application versions as discrete charts.
- **Dependency Management**: Define and install sub-charts.

**Exercise:** [pkg-helm](../challenges/7-packaging/helm-templating/answer.md)

### Pattern: Kustomize Overlays

Kustomize uses a "base and overlay" approach to manage variations across environments (dev, prod) without templates:
- **Base**: Common resource definitions.
- **Overlay**: Environment-specific patches (e.g., higher replica count for prod).

**Exercise:** [pkg-kustomize](../challenges/7-packaging/kustomize-overlays/answer.md)

---

## Quick Reference

### Troubleshooting Commands

```bash
# Events and status
kubectl describe pod <name>
kubectl get events --sort-by=.lastTimestamp

# Logs
kubectl logs <pod> -c <container> --previous
kubectl logs -l app=myapp --all-containers

# RBAC testing
kubectl auth can-i <verb> <resource> --as=system:serviceaccount:<ns>:<sa>

# Network debugging
kubectl run tmp --rm -it --image=nicolaka/netshoot -- /bin/bash
```

### Key Resources by Domain

| Domain | Must Know |
|--------|-----------|
| GitOps | Application, ApplicationSet, Rollout |
| Platform | CRD, XRD, Composition, Operator patterns |
| Observability | PrometheusRule, ServiceMonitor, OTEL env vars |
| Architecture | NetworkPolicy, StorageClass, ResourceQuota |
| Security | ClusterPolicy, Role/RoleBinding, PeerAuthentication |

### Exam Tips

1. **Read carefully**: Note namespace, resource names, exact requirements
2. **Check existing state**: `kubectl get -o yaml` before making changes
3. **Use edit**: `kubectl edit` is faster than complex patches
4. **Verify changes**: Confirm fix worked before moving on
5. **Know the docs**: Each task lists allowed documentation—use it
