# Validation cluster baseline

Last updated: August 5, 2026.

## Cluster

- kubeconfig: external to the repository, supplied through `KUBECONFIG`;
- context: `default`;
- k3s: `v1.36.2+k3s1`;
- installation client: `kubectl v1.36.2`, verified by SHA-256;
- one control-plane and three Ready workers.

| Node | Role | CPU | Memory | Address |
| --- | --- | ---: | ---: | --- |
| `k8s-master-1` | control-plane | 2 | ~3.8 GiB | private network |
| `k8s-worker-1` | worker | 8 | ~15.6 GiB | private network |
| `k8s-worker-2` | worker | 8 | ~15.6 GiB | private network |
| `k8s-worker-3` | worker | 8 | ~15.6 GiB | private network |

The control-plane is a single node, so the Kubernetes API is not highly available. This does not invalidate PostgreSQL HA tests, but it is a limitation of the complete platform.

## Physical and virtual storage

The Proxmox host provides:

- `nvme0n1`, XPG GAMMIX S11 Pro, used by the `local-lvm` thin pool;
- `sdb`, an approximately 477 GiB SATA SSD configured as the currently empty `ssd` datastore.

Each worker sees only one 50 GiB virtual system disk in `local-lvm`. By lab decision, no disks were added. Longhorn uses `/var/lib/longhorn` on that filesystem with 80% reserved, limiting Longhorn capacity to approximately 10 GiB per worker.

## Applied Longhorn prerequisites

On all three workers:

- `open-iscsi` installed;
- `iscsid` enabled and active;
- `nfs-common` installed;
- `cryptsetup` and `dmsetup` available;
- `iscsi_tcp` module loadable;
- non-interactive sudo available for bootstrap.

## Installed components

All project components are rendered by Kustomize. The charts below are inflation sources, not operational Helm releases.

### Operators

- cert-manager `v1.21.1`;
- CloudNativePG chart `0.29.0`, operator `1.30.0`;
- Barman Cloud Plugin `v0.14.0`;
- CRDs and webhooks Ready.

### Longhorn

- official `longhorn/longhorn` chart `1.12.0`;
- namespace `longhorn-system`;
- three Longhorn Nodes Ready and Schedulable;
- CSI driver `driver.longhorn.io` registered;
- `longhorn-postgres`: `Retain`, one replica, `strict-local`;
- `longhorn-lab`: `Delete`, one replica, `best-effort`;
- `local-path` remains the default StorageClass.

### Lab MinIO

- `minio/minio` chart `5.4.0`;
- namespace `minio-lab`;
- standalone mode with `Recreate` update strategy;
- `2Gi` PVC on `longhorn-lab`;
- ClusterIP services on ports 9000/9001;
- private, versioned `postgres-backups` bucket;
- dedicated Barman user; unsafe default user removed;
- credentials stored in cluster-generated Secrets.

### PostgreSQL

- PostgreSQL `18.3-standard-trixie`;
- namespace `postgres-lab`;
- three 2/2 Ready instances across three workers;
- three `5Gi` PVCs on `longhorn-postgres`;
- current primary managed by the operator;
- synchronous replication `ANY 1`, `dataDurability: required`;
- Barman `ObjectStore` and daily `ScheduledBackup`.

### Sealed Secrets

- chart `2.19.1`;
- controller compatible with `kubeseal 0.38.4`;
- strict-scope round-trip validated in the lab without plaintext in Git.

### Monitoring integration

- production CNPG PodMonitor enabled;
- operator PodMonitor, official Grafana dashboard and eleven Prometheus alerts versioned;
- rules validated by `promtool`;
- the target environment remains responsible for Prometheus, Grafana and log storage.

## Executed evidence

- Longhorn write and fsync;
- online PVC expansion from `1Gi` to `2Gi`;
- detach/reattach after Pod recreation;
- marker persistence;
- temporary PVC/volume cleanup;
- MinIO PUT, stat, GET, comparison and DELETE;
- complete backup and `backup.info` in object storage;
- PITR to a timestamp between two writes;
- primary Pod failover in 27 seconds with the confirmed write preserved.

## Still pending

- calibrated storage/PostgreSQL load test;
- abrupt loss of the worker hosting the primary;
- external production object storage and restore/PITR drill;
- highly available control-plane;
- production migration and upgrade/rollback drills;
- target logging-stack integration;
- Argo CD, deliberately outside the current baseline.
