# Architecture decision record

This document records the current architecture decisions. A decision may be promoted to an individual ADR when it requires dedicated manifests or operating procedures.

## D-001 — CloudNativePG

**Decision:** use CloudNativePG to manage PostgreSQL.

**Why:** it provides declarative lifecycle management, failover, switchover, services, certificates, replication, plugin-based backups and Prometheus integration without maintaining custom election scripts.

**Alternatives:** manually operated Patroni, Zalando Postgres Operator, Crunchy PGO or PostgreSQL outside Kubernetes.

**Not recommended when:** the team cannot operate Kubernetes and storage with the required maturity, or when a managed service provides better RTO/RPO and operating cost.

## D-002 — Three instances and synchronous quorum

**Decision:** one primary and two replicas; synchronous commits wait for `ANY 1` eligible replica.

**Benefit:** one replica can fail without losing the ability to confirm writes.

**Cost:** every commit depends on network, CPU and fsync from at least one replica. Worker latency and jitter become application latency.

**Limit:** three instances tolerate one instance failure during normal HA operation; they do not automatically tolerate every combination of two failures.

## D-003 — Required durability

**Decision:** use `dataDurability: required` in both the lab and production reference while the target is local RPO zero for confirmed commits.

- `required`: blocks commits when no synchronous replica is available and preserves the durability guarantee;
- `preferred`: a documented operational alternative that temporarily degrades to asynchronous replication and can increase RPO.

Any incident-time change must be explicit, audited and covered by a runbook. It is not automated by an opaque script.

## D-004 — No triple Longhorn replication per instance

**Decision:** one `strict-local` Longhorn replica per PostgreSQL volume in the main lab profile; an optional two-replica `best-effort` profile may be provided.

**Why:** CloudNativePG already maintains three PostgreSQL copies. Three Longhorn replicas for each instance would create up to nine local copies and amplify writes and network traffic.

**Benefit:** lower latency and disk use.

**Drawback:** if an instance disk fails, that instance is rebuilt from another instance or backup instead of its volume surviving independently.

**When to use two or three Longhorn replicas:** workloads without native replication, a requirement to recover the same PVC, or benchmarks showing sufficient capacity and a concrete operational benefit.

## D-005 — Barman Cloud CNPG-I backups

**Decision:** use the current plugin, `ObjectStore`, daily base backups and continuous WAL archiving.

**Why:** this separates backup lifecycle from the operator core and supports complete restore/PITR through an S3-compatible backend.

**Do not:** treat Longhorn snapshots as a replacement for external backups or consider a backup valid without a tested restore.

## D-006 — S3-compatible without provider coupling

**Decision:** parameterize endpoint, bucket, region, path and TLS options; do not include credentials or provider-specific extensions in the base manifests.

Compatibility is declared only for tested backends. “S3-compatible” does not guarantee identical multipart upload, object lock, lifecycle, TLS or consistency behaviour.

## D-007 — Secrets by profile

**Decision:** the lab generates Kubernetes Secrets locally and never persists them in Git. The production profile uses cluster-specific, `strict` Sealed Secrets for operator-supplied credentials, starting with S3 access.

Each cluster seals different values with its own controller public certificate. Controller private keys remain outside Git with encrypted backup, access control and a restore drill. Secrets and certificates managed by CloudNativePG remain under the operator lifecycle.

**Why:** this keeps the lab simple and allows encrypted desired state in production without making ciphertext reusable across clusters.

## D-008 — Kustomize without GitOps

**Decision:** use Kustomize as the single composition and installation layer. Official charts enter through `helmCharts`; project manifests enter through `resources` and patches. Do not install Argo CD at this stage.

**Why:** this centralizes rendering, ordering and ownership without adding a reconciliation controller. Lab and production profiles remain explicit in Kustomize. GitOps can be reconsidered when multiple clusters are continuously operated or teams require continuous reconciliation.

## D-009 — Optional Pooler

**Decision:** support the CloudNativePG `Pooler`, disabled by default.

Enable it when connection churn, serverless workloads or connection budgets justify PgBouncer. The application must prove compatibility with transaction pooling.

## D-010 — Grafana Alloy instead of Promtail

**Decision:** use Grafana Alloy for Loki integration when repository-owned log collection is required. Promtail is not used because its support ended in March 2026.

## D-011 — Minimal, not absolute-zero, upgrade interruption

**Decision:** rolling update/switchover, clients with retry and reconnect, and measured interruption.

Active connections and transactions can be interrupted when the primary changes. “Zero downtime” is not used as an absolute guarantee.

## D-012 — Repository ownership

**Decision:** this repository owns the Longhorn, MinIO, PostgreSQL, Sealed Secrets and monitoring-integration configuration used by the reference. The underlying k3s and Proxmox platforms remain external dependencies.

There is no Argo CD at this stage. Idempotent scripts render Kustomize, including pinned official charts, and apply server-side with a dedicated field manager.

## D-013 — In-cluster MinIO for tests only

**Decision:** install standalone MinIO in the lab with a `2Gi` PVC, HTTP ClusterIP and a private versioned bucket.

**Limit:** MinIO shares PostgreSQL's failure domain and is not a disaster-recovery backup. Production requires external object storage.

## D-014 — Longhorn capacity limited on system disks

**Decision:** do not add disks to the lab VMs. Reserve 80% of each 50 GiB filesystem and allow Longhorn approximately 10 GiB per worker.

**Limit:** this configuration is exclusively for the lab. PostgreSQL uses `5Gi` per instance and must retain headroom for snapshots and MinIO.
