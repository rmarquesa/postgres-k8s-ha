# Observability

The repository integrates with an existing Prometheus Operator and Grafana deployment. It does not install another monitoring stack.

## Included

`monitoring/cloudnative-pg` renders:

- a PodMonitor for the CloudNativePG operator in `cnpg-system`;
- eleven production alerts for primary count, instance availability, replication, backup/WAL, connections, transactions, deadlocks and PVC usage;
- the official CloudNativePG Grafana dashboard chart `0.0.5` (Grafana.com dashboard `20417`).

The production `Cluster` enables CNPG's native PodMonitor for PostgreSQL instances. CNPG inherits the `release=kube-prometheus-stack` label from the Cluster so the reference Prometheus selector discovers it.

## Prerequisites

- Prometheus Operator CRDs `PodMonitor` and `PrometheusRule`;
- a Prometheus instance configured to discover monitors/rules carrying `release=kube-prometheus-stack`;
- Grafana sidecar discovery for ConfigMaps labelled `grafana_dashboard=1`;
- kubelet volume metrics for the PVC alert;
- a `monitoring` namespace or a per-cluster patch selecting the platform namespace.

Patch the `release` label when the target monitoring stack uses a different release/selector. Label the namespace running Prometheus so the production NetworkPolicy permits metric scrapes:

```bash
kubectl label namespace monitoring postgres-k8s-ha.io/monitoring=true --overwrite
```

## Install integration resources

```bash
export KUBECONFIG=/path/to/production.kubeconfig
export EXPECTED_CONTEXT=production-context
export ALLOW_PRODUCTION_APPLY=true
./scripts/install-monitoring-resources.sh
```

The script verifies context and CRDs, renders, server dry-runs, diffs and applies without `--force-conflicts`.

## Validate

```bash
kubectl kustomize monitoring/cloudnative-pg --enable-helm > /tmp/cnpg-monitoring.yaml
python3 scripts/extract_prometheus_rules.py \
  monitoring/cloudnative-pg/alerts.yaml /tmp/cnpg-rules.yaml
docker run --rm --entrypoint=promtool \
  -v /tmp/cnpg-rules.yaml:/rules.yaml:ro \
  prom/prometheus:v3.5.0 check rules /rules.yaml
```

CI executes the same PromQL validation. Every alert links to [the alert runbook](runbooks/alerts.md).

## Acceptance

Before production data:

1. confirm operator and all three instance targets are `UP`;
2. confirm the dashboard shows primary, replicas, connections, WAL and backup age;
3. trigger a safe synthetic rule test or use `promtool test rules` in the platform repository;
4. route warning/critical alerts to owned receivers;
5. verify runbook URLs are reachable from the incident system;
6. retain metrics long enough to cover capacity, backup and incident analysis windows.

Logs should remain in the target platform's existing logging stack. Collect CNPG operator, instance-manager/PostgreSQL and Barman plugin logs with bounded retention and secret/PII controls; this repository does not mandate Loki.
