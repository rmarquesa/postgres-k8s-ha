# PostgreSQL HA on Kubernetes

A reproducible reference implementation of highly available PostgreSQL on Kubernetes using CloudNativePG, Longhorn, S3-compatible backups, and tested point-in-time recovery.

**[Visit the project website](https://rmarquesa.github.io/postgres-k8s-ha/)** · [Getting started](docs/getting-started.md) · [Production profile](docs/production.md)

> **Status:** validated lab profile plus a fail-closed production profile for prepared HA Kubernetes environments. PostgreSQL HA, Pod failover, storage, S3 operations, backups, PITR, and the Sealed Secrets round-trip have been exercised against the live lab cluster. Real worker loss, calibrated load, and the external-S3 production restore gate remain pending.

## Start here

For a clean-cluster installation, follow **[How to Get Started](docs/getting-started.md)**. It covers host preparation, `KUBECONFIG`, operators, Longhorn, MinIO, PostgreSQL, validation tests, troubleshooting, and production considerations.

For a prepared production environment, follow the **[Production profile](docs/production.md)**. It separates external storage/S3, strict Sealed Secrets, roles, NetworkPolicies, supervised updates, and production acceptance gates from the lab.

```bash
export KUBECONFIG=/path/to/kubeconfig
export KUBECTL_BIN=kubectl

./scripts/install-platform.sh
```

Do not run the quick start until the worker prerequisites described in the guide are installed.

## What is included

- CloudNativePG `1.30.0` with one primary and two replicas;
- PostgreSQL `18.3-standard-trixie`;
- synchronous replication with quorum `ANY 1` and `dataDurability: required`;
- required Pod anti-affinity: one PostgreSQL instance per worker;
- Longhorn `1.12.0`, limited to approximately 10 GiB on each worker;
- one `5Gi` PVC per PostgreSQL instance;
- one Longhorn replica per PostgreSQL PVC with strict data locality;
- Barman Cloud Plugin `v0.14.0` with continuous WAL archiving;
- daily base backups with seven-day retention;
- restore and point-in-time recovery tests;
- standalone MinIO with a `2Gi` PVC for lab use only;
- Kustomize-based composition and installation, without a GitOps controller.
- a separate fail-closed production overlay with external S3 and Sealed Secrets contracts.

## Validated results

| Test | Result |
| --- | --- |
| Longhorn | Three worker disks Ready and Schedulable; managers and CSI components Ready |
| PVC lifecycle | Write, `1Gi → 2Gi` expansion, detach/reattach, and persistence passed |
| PostgreSQL | 3/3 instances Ready and distributed across three workers |
| Replication | `ANY 1`; two replicas reported as synchronous quorum candidates |
| Failover | Current primary Pod deleted; a new primary was promoted in 27 seconds; committed data was preserved |
| Backup | Base backup completed from a replica; Barman objects were confirmed in object storage |
| PITR | A new cluster recovered data before the target and excluded data written after it; Ready in 134 seconds |
| MinIO | Versioned bucket and S3 PUT/stat/GET/DELETE operations passed |

See [validation results](docs/validation-results.md) for the recorded evidence and limitations.

## Architecture

```text
Applications
    │
    ▼
CloudNativePG-managed RW/RO Services
    │
    ├── PostgreSQL instance 1 ── 5Gi PVC ── worker 1
    ├── PostgreSQL instance 2 ── 5Gi PVC ── worker 2
    └── PostgreSQL instance 3 ── 5Gi PVC ── worker 3
                 │
                 └── Barman Cloud Plugin
                           │
                           ▼
                  MinIO 2Gi (lab only)
```

CloudNativePG provides database-level replication and failover. Each PostgreSQL PVC intentionally uses one Longhorn replica because PostgreSQL is already replicated across three workers. Using three Longhorn replicas for every database PVC would create nine physical copies and exceed the lab storage budget.

The in-cluster MinIO deployment shares the Kubernetes and storage failure domain with PostgreSQL. It is useful for functional testing, but **it is not disaster recovery**.

## Repository layout

```text
postgres-k8s-ha/
├── databases/postgres-ha/              # validated lab profile
├── databases/postgres-ha-production/   # production overlay and policies
├── docs/                    # installation, architecture, decisions, and operations
├── monitoring/              # PodMonitors, alerts, and official CNPG dashboard
├── platform/
│   ├── barman-cloud/        # pinned official Barman plugin manifest
│   ├── cert-manager/        # Kustomize and official chart
│   ├── cloudnative-pg/      # Kustomize and official chart
│   ├── longhorn/            # Kustomize, official chart, and StorageClasses
│   ├── minio/               # Kustomize, official chart, and Barman user setup
│   └── sealed-secrets/      # pinned production secrets controller
├── scripts/                 # idempotent installation, validation, and test scripts
├── site/                    # dependency-free GitHub Pages landing page
├── tests/                   # storage, S3, backup, and PITR test resources
└── vault/                   # project notes for Obsidian
```

## Installation and tests

Follow the complete installation guide rather than treating the commands below as standalone instructions:

- **[How to Get Started](docs/getting-started.md)**

After installation, the validation suite is:

```bash
./scripts/test-longhorn.sh
./scripts/test-minio.sh
./scripts/test-backup.sh
./scripts/test-pitr.sh

# Deletes the current primary Pod. Run only on an approved test cluster.
ALLOW_DESTRUCTIVE_TESTS=true ./scripts/test-failover.sh
```

Repository and server-side manifest validation:

```bash
./scripts/validate.sh
```

## Storage sizing

| Purpose | StorageClass | PVC size | Longhorn replicas | Reclaim policy |
| --- | --- | ---: | ---: | --- |
| PostgreSQL instance | `longhorn-postgres` | `5Gi` each | 1 | `Retain` |
| MinIO lab instance | `longhorn-lab` | `2Gi` | 1 | `Delete` |
| Storage smoke test | `longhorn-lab` | `1Gi`, expanded to `2Gi` | 1 | `Delete` |

The reference workers have approximately 50 GiB system disks. Longhorn reserves 80% and can therefore use approximately 10 GiB per worker. This is a configurable lab constraint, not a production recommendation.

## Current limitations

- one Kubernetes control-plane node;
- PostgreSQL and MinIO share the same cluster and storage system;
- Longhorn uses worker system disks rather than dedicated data disks;
- no Prometheus, Grafana, Loki, or Alloy deployment yet;
- full worker shutdown/drain has not been tested because the cluster hosts unrelated workloads;
- clients must retry and reconnect while CloudNativePG promotes a new primary;
- `dataDurability: required` can block writes when no synchronous replica is eligible.

## Production path

Before using this design for production:

1. use an HA Kubernetes control plane;
2. move Longhorn to dedicated, monitored disks or use a production storage platform;
3. send backups to object storage outside the Kubernetes failure domain;
4. use per-cluster strict Sealed Secrets and protect the controller keys externally;
5. add PostgreSQL, operator, storage, backup, and infrastructure monitoring;
6. define and test application retry behavior;
7. test worker loss, zone loss, restore, PITR, upgrades, and capacity exhaustion;
8. derive RPO and RTO commitments from repeated measurements rather than lab targets.

## Documentation

- [How to Get Started](docs/getting-started.md)
- [Production profile](docs/production.md)
- [Observability](docs/observability.md)
- [Operational runbooks](docs/runbooks/alerts.md)
- [Architecture](docs/architecture.md)
- [Decisions](docs/decisions.md)
- [Implementation contract](docs/implementation-contract.md)
- [Cluster baseline](docs/cluster-baseline.md)
- [Kustomize delivery](docs/kustomize.md)
- [Longhorn](docs/longhorn.md)
- [MinIO](docs/minio.md)
- [Validation results](docs/validation-results.md)

## Security

Never commit kubeconfigs, passwords, S3 credentials, tokens, private TLS keys, or Kubernetes Secrets containing real values. The lab creates credentials directly in Kubernetes and configures a dedicated MinIO user restricted to the backup bucket.

## License

[MIT](LICENSE)
