# Decisions

## Current decisions

- Publish the project as `postgres-k8s-ha`.
- Use the real k3s-Proxmox cluster for lab validation.
- Do not add disks to the lab: Longhorn may use approximately 10 GiB of each worker's 50 GiB system disk.
- Use `5Gi` per PostgreSQL instance in the lab.
- Use CloudNativePG with three instances, one database and synchronous quorum `ANY 1`.
- Use `dataDurability: required` to preserve local RPO zero while quorum is available.
- Use one `strict-local` Longhorn replica per PostgreSQL volume.
- Use standalone in-cluster MinIO only for S3/PITR tests.
- Use Barman Cloud CNPG-I through an S3-compatible API.
- Create lab Secrets locally and never store them in Git.
- Use cluster-specific, `strict` Sealed Secrets in the production profile for operator-supplied credentials; never reuse ciphertext between clusters.
- Store and test recovery of sealing keys outside Git in an encrypted, audited backup.
- Keep CloudNativePG-managed Secrets and certificates under the operator lifecycle.
- Use Kustomize as the single composition and installation layer; official charts are rendered through `helmCharts`.
- Do not install Argo CD at this stage; GitOps remains an optional future evolution.
- Use Grafana Alloy instead of Promtail when the target platform requires a repository-owned log collector.
- Publish a dependency-free, English-language project landing page through the repository's GitHub Pages workflow.

## Boundaries

- In-cluster MinIO is not disaster recovery.
- A single control-plane node does not make the whole platform highly available.
- Observed RTO is not a universal SLA.
- Clients need retry and reconnect behaviour during failover and switchover.
- Production acceptance requires external object storage, calibrated load and a real abrupt loss of the worker hosting the primary.
