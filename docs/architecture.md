# Architecture

## 1. High-level view

```text
                         applications
                              │
                     TLS + NetworkPolicy
                              │
              ┌───────────────┴───────────────┐
              │                               │
         RW Service                      RO Service
       optional Pooler                 optional Pooler
              │                               │
              ▼                               ▼
       ┌────────────┐     WAL sync      ┌────────────┐
       │ Primary    │ ───── ANY 1 ─────▶│ Replica 1  │
       │ Worker A   │ ───── ANY 1 ─────▶│ Replica 2  │
       └─────┬──────┘                   └─────┬──────┘
             │                                │
             └──────── CloudNativePG ─────────┘
                              │
                ┌─────────────┴─────────────┐
                │                           │
           Longhorn PVC              Barman CNPG-I
       worker virtual disk           ├─ base backup
                │                    └─ continuous WAL
                ▼                          │
       Proxmox local-lvm/NVMe               ▼
                                   in-cluster MinIO in lab
                                   external S3 in production
```

PostgreSQL provides physical replication between instances. Longhorn provides volumes and the CSI lifecycle. In the lab, MinIO shares the cluster and is not a disaster-recovery boundary; external object storage is mandatory for that guarantee in production.

## 2. Failure domains

Each instance must run on a different worker. The control-plane does not receive PostgreSQL workloads by default.

```text
Worker 1                 Worker 2                 Worker 3
┌─────────────┐          ┌─────────────┐          ┌─────────────┐
│ PG primary  │          │ PG replica  │          │ PG replica  │
│ Longhorn    │          │ Longhorn    │          │ Longhorn    │
│ disk path   │          │ disk path   │          │ disk path   │
└─────────────┘          └─────────────┘          └─────────────┘
```

Anti-affinity prevents voluntary placement on the same hostname. Topology spread maintains balanced distribution. No scheduling rule can fix infrastructure where all three workers depend on the same disk, power supply or physical host; those failure domains must be documented by the target platform.

## 3. Writes and replication

```text
Client         Primary        Replica A       Replica B
   │              │               │               │
   │ COMMIT       │               │               │
   ├─────────────▶│ WAL + fsync    │               │
   │              ├──────────────▶│               │
   │              ├──────────────────────────────▶│
   │              │ waits for ACK from ANY 1      │
   │              │◀──────────────┤               │
   │ COMMIT OK    │               │               │
   │◀─────────────┤               │               │
```

`ANY 1` avoids requiring both replicas simultaneously. With `required`, the absence of an eligible synchronous replica prevents new commits from being confirmed. With `preferred`, the operator can preserve availability by accepting temporary durability degradation.

## 4. Failover

```text
Primary stops responding
          │
          ▼
CloudNativePG checks health and replica state
          │
          ▼
Selects the eligible candidate with the most advanced WAL
          │
          ▼
Promotes the replica
          │
          ├─ updates the RW Service
          ├─ reconciles topology
          └─ replaces or rejoins the failed instance
          │
          ▼
Client reconnects and retries the idempotent operation
```

Failover can interrupt connections and transactions. Applications need timeouts, reconnects and bounded retries. PgBouncer reduces connection churn but does not preserve interrupted transactions.

## 5. Longhorn storage

### Local PostgreSQL profile

```text
PG instance ── PVC ── Longhorn engine ── 1 local replica ── worker disk
```

PostgreSQL already maintains three copies of the data, so the base profile avoids another layer of triple replication in storage.

### Replicated profile

```text
PG instance ── PVC ── Longhorn engine ── local replica
                                      └─ remote replica
```

This allows a PVC to survive disk or node loss at the cost of network traffic, capacity and latency. It should only be recommended after benchmarking.

### When not to use Longhorn

- an external CSI storage platform already provides better durability and performance;
- the workload requires predictable latency that network replication cannot meet;
- workers lack dedicated disks or real failure domains;
- the team cannot operate rebuilds, snapshots, engine upgrades and capacity pressure;
- a managed PostgreSQL service significantly reduces operational risk.

## 6. Backup and WAL

```text
                   ┌─ daily base backup ───────────┐
PostgreSQL/Barman ─┤                               ├─▶ cluster bucket/prefix
                   └─ continuous WAL segments ─────┘
```

A base backup is a consistent physical copy used as the recovery starting point. WAL contains subsequent changes. PITR selects an earlier base backup and replays WAL up to the target.

Seven-day retention defines the lab window but must be validated in the backend. Bucket lifecycle rules must not delete WAL still required by recoverable backups.

## 7. PITR

```text
Monday 02:00  base backup
      │
      ├──────── WAL ──────── Tuesday 14:32:15 target
      │                              │
      └──────── WAL ──────── Tuesday 15:00 accidental DELETE
                                     X do not replay

ObjectStore ─▶ new recovery Cluster ─▶ validation ─▶ explicit cutover
```

Recovery creates a new cluster. The original cluster is not edited or overwritten during the test.

## 8. S3 outage

```text
S3 unavailable
      │
      ├─ PostgreSQL continues while storage/WAL capacity permits
      ├─ archiving queues and retries
      ├─ alert fires
      └─ PITR window stops advancing
                 │
          disk may fill
                 │
          availability risk
```

Object storage is not part of the synchronous commit path, but a prolonged outage becomes a capacity and recoverability risk.

## 9. Current delivery and GitOps evolution

```text
local repository/GitHub
  ├─ kustomizations
  ├─ pinned official charts through helmCharts
  ├─ Kubernetes manifests
  └─ idempotent scripts
            │
            ▼
       k3s cluster
```

The current phase uses Kustomize and server-side apply because there is one database and one lab environment. Argo CD should be considered when multiple databases/environments or continuous reconciliation justify another controller.

## 10. Secrets

```text
local generator ──▶ Kubernetes Secret ──▶ CNPG / ObjectStore
                           │
                           └─ never committed
```

The production profile uses cluster-specific, `strict` Sealed Secrets. External Secrets or Vault remains an alternative when dynamic rotation or direct integration with an external secret manager is required. None of these flows replaces Secrets and certificates managed by CloudNativePG.

## 11. Observability

- CloudNativePG metrics through PodMonitor;
- kube-state-metrics and node exporter;
- Longhorn metrics;
- PostgreSQL availability, connections, locks, checkpoints, WAL and replication lag;
- backup last success, age, duration and failures;
- storage capacity, degraded/faulted volumes and rebuilds;
- target-platform logging, optionally Grafana Alloy to Loki;
- dashboards linked to runbooks and deployment events.

Alerts should represent actionable symptoms. High CPU by itself is context, not necessarily a page.

## 12. Security

- TLS in transit;
- least-privilege RBAC;
- application roles without superuser privileges;
- default-deny NetworkPolicies with explicit DNS, S3 and monitoring paths;
- operator-supported security contexts;
- Pod Security Standards on the namespace;
- externally supplied Secrets;
- object-storage encryption and, when supported and tested, volume encryption;
- official images pinned to versions and verified;
- backups without embedded credentials.

## 13. Known limitations

- three workers do not provide unlimited spare capacity during maintenance;
- the lab has a single control-plane, so the Kubernetes control plane is not highly available;
- lab Longhorn uses constrained worker system disks rather than dedicated production storage;
- in-cluster MinIO is not a disaster-recovery destination;
- external production S3, sizing and valid production TLS remain environment-specific;
- load, abrupt worker-loss, upgrade and migration acceptance gates remain pending;
- SLOs depend on benchmarks and real target-environment tests;
- PostgreSQL HA does not replace backups or Kubernetes control-plane HA.
