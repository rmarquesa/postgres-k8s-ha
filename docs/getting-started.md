# How to Get Started

This guide installs the complete PostgreSQL HA lab on a clean Kubernetes cluster. It covers the workstation, worker preparation, operators, Longhorn, MinIO, PostgreSQL, validation, troubleshooting, and the changes required before production use.

## 1. Understand the target environment

The reference environment uses:

- k3s `v1.36.2+k3s1`;
- one control-plane node;
- three Linux worker nodes;
- approximately 8 vCPU and 16 GiB RAM per worker;
- approximately 50 GiB on each worker system disk;
- approximately 10 GiB per worker made available to Longhorn;
- outbound access to the chart and container registries referenced by the manifests.

Three schedulable workers are required because the PostgreSQL manifest requests three instances and uses required anti-affinity on `kubernetes.io/hostname`. The control-plane is excluded from PostgreSQL and Longhorn data placement.

The scripts are idempotent: rerunning them reconciles the declared resources and preserves generated credentials that already exist. They are not a replacement for reviewing changes before upgrades.

## 2. Local prerequisites

Install these tools on the workstation used to operate the cluster:

- Git;
- `kubectl` compatible with the Kubernetes server version;
- Helm 3, used by `kubectl kustomize --enable-helm`;
- OpenSSL, used to generate MinIO credentials;
- Bash;
- Python 3, used by repository validation.

Verify them:

```bash
git --version
kubectl version --client
helm version
openssl version
bash --version
python3 --version
```

Clone the repository and enter it:

```bash
git clone https://github.com/rmarquesa/postgres-k8s-ha.git
cd postgres-k8s-ha
```

If the public repository has not been created yet, use the existing local checkout instead.

## 3. Configure KUBECONFIG

Keep the kubeconfig outside the repository and export it explicitly:

```bash
export KUBECONFIG=/absolute/path/to/kubeconfig
export KUBECTL_BIN=kubectl
```

If a version-specific client is required, set `KUBECTL_BIN` to its absolute path:

```bash
export KUBECTL_BIN="$HOME/.local/bin/kubectl-1.36.2"
```

Confirm that the selected context is the intended cluster. Do not continue if it points to a local Docker, OrbStack, kind, or another production cluster by mistake.

```bash
"$KUBECTL_BIN" config current-context
"$KUBECTL_BIN" cluster-info
"$KUBECTL_BIN" get nodes -o wide
"$KUBECTL_BIN" auth can-i '*' '*' --all-namespaces
```

Expected baseline:

- all nodes are `Ready`;
- exactly three or more schedulable workers are available;
- the operator account can create cluster-scoped resources, CRDs, namespaces, RBAC, and storage resources.

Check worker labels and taints:

```bash
"$KUBECTL_BIN" get nodes \
  -o custom-columns='NAME:.metadata.name,ROLES:.metadata.labels.node-role\.kubernetes\.io/control-plane,TAINTS:.spec.taints'
```

## 4. Prepare every worker for Longhorn

Run the following on **each worker**, not on the workstation. The example is for Debian or Ubuntu workers:

```bash
sudo apt-get update
sudo apt-get install -y open-iscsi nfs-common cryptsetup dmsetup
sudo systemctl enable --now iscsid
sudo modprobe iscsi_tcp
```

Verify each worker:

```bash
systemctl is-active iscsid
command -v iscsiadm
command -v mount.nfs
command -v cryptsetup
command -v dmsetup
lsmod | grep '^iscsi_tcp'
findmnt -o TARGET,PROPAGATION /
df -h /var/lib
```

Requirements:

- `iscsid` reports `active`;
- `iscsiadm`, NFS utilities, `cryptsetup`, and `dmsetup` exist;
- the `iscsi_tcp` module can be loaded;
- mount propagation is supported;
- `/var/lib/longhorn` has enough free capacity.

The lab stores Longhorn data under `/var/lib/longhorn` on the worker system filesystem. `platform/longhorn/values.yaml` reserves 80% of each detected disk, limiting usable Longhorn capacity to approximately 10 GiB on a 50 GiB worker disk. Adjust this before installation if the worker disks have different sizes.

> Do not use this layout on production hosts without a capacity model. A full system disk can affect the operating system, kubelet, container runtime, and database simultaneously.

## 5. Validate the repository before installation

The full validator performs source checks, Kustomize renders, and Kubernetes server-side dry-runs:

```bash
./scripts/validate.sh
```

Expected final line:

```text
OK: project validation complete
```

This step downloads the pinned charts during Kustomize rendering. It does not persist chart caches in Git.

## 6. Install the operators

Install cert-manager, CloudNativePG, and the Barman Cloud Plugin:

```bash
./scripts/install-operators.sh
```

The script waits for deployments and required CRDs. Verify them independently:

```bash
"$KUBECTL_BIN" -n cert-manager get deployments
"$KUBECTL_BIN" -n cnpg-system get deployments,pods
"$KUBECTL_BIN" get crd \
  certificates.cert-manager.io \
  clusters.postgresql.cnpg.io \
  objectstores.barmancloud.cnpg.io
```

Expected result:

- cert-manager, webhook, and cainjector are Available;
- `cnpg-cloudnative-pg` is Available;
- `barman-cloud` is Available;
- all three CRDs exist.

## 7. Install and validate Longhorn

Install Longhorn and the project StorageClasses:

```bash
./scripts/install-longhorn.sh
```

The script labels every non-control-plane node with:

```text
node.longhorn.io/create-default-disk=true
```

It then installs Longhorn `1.12.0`, waits for CSI components, and validates every worker as Ready and Schedulable.

Check the result:

```bash
./scripts/verify-longhorn.sh

"$KUBECTL_BIN" -n longhorn-system get pods
"$KUBECTL_BIN" -n longhorn-system get nodes.longhorn.io
"$KUBECTL_BIN" get storageclass longhorn-postgres longhorn-lab
```

Expected StorageClasses:

- `longhorn-postgres`: one replica, strict locality, `WaitForFirstConsumer`, `Retain`;
- `longhorn-lab`: one replica, best-effort locality, `WaitForFirstConsumer`, `Delete`.

Run the destructive-to-temporary-resources storage test:

```bash
./scripts/test-longhorn.sh
```

It creates an isolated namespace, provisions a PVC, writes data, expands the PVC from `1Gi` to `2Gi`, remounts it, verifies persistence, and removes the test namespace unless `KEEP_TEST_RESOURCES=true` is set.

## 8. Install and configure MinIO

Install the lab-only S3-compatible backend:

```bash
./scripts/install-minio.sh
```

The installer:

1. creates `minio-lab`;
2. generates `minio-root-credentials` directly in Kubernetes if absent;
3. installs standalone MinIO with a `2Gi` Longhorn PVC;
4. creates and versions the `postgres-backups` bucket;
5. creates a dedicated Barman user restricted to that bucket;
6. writes the corresponding S3 credential Secret to `postgres-lab`;
7. runs the S3 smoke test.

No credential value is written to a repository file or printed by the scripts.

Validate the deployment:

```bash
"$KUBECTL_BIN" -n minio-lab get deployment,pod,pvc,service
"$KUBECTL_BIN" -n minio-lab get job minio-configure-barman
./scripts/test-minio.sh
```

Expected result:

- Deployment `minio` is `1/1` Available;
- PVC `minio` is Bound to `longhorn-lab`;
- configuration Job is Complete;
- S3 PUT/stat/GET/DELETE passes.

MinIO deliberately uses `Recreate`, because a standalone Deployment with one RWO PVC cannot perform a cross-node surge rollout.

## 9. Install PostgreSQL HA

Install the three-instance PostgreSQL cluster:

```bash
./scripts/install-database.sh
```

The script ensures Barman credentials exist, applies the database Kustomization, waits up to 15 minutes for the cluster, and prints synchronous replication state.

Validate placement and readiness:

```bash
"$KUBECTL_BIN" -n postgres-lab get cluster.postgresql.cnpg.io postgres-ha
"$KUBECTL_BIN" -n postgres-lab get pods,pvc -o wide
"$KUBECTL_BIN" -n postgres-lab get scheduledbackup.postgresql.cnpg.io
```

Expected result:

- Cluster `postgres-ha` reports three instances and `Ready=3`;
- one Pod runs on each worker;
- three `5Gi` PVCs are Bound using `longhorn-postgres`;
- one Pod has role `primary` and two have role `replica`;
- `postgres-ha-daily` exists.

Inspect synchronous replication:

```bash
primary=$("$KUBECTL_BIN" -n postgres-lab get pod \
  -l cnpg.io/cluster=postgres-ha,role=primary \
  -o jsonpath='{.items[0].metadata.name}')

"$KUBECTL_BIN" -n postgres-lab exec "$primary" -c postgres -- \
  psql -XAt -d app -c 'SHOW synchronous_standby_names'

"$KUBECTL_BIN" -n postgres-lab exec "$primary" -c postgres -- \
  psql -XAt -d app -c \
  "SELECT application_name, state, sync_state FROM pg_stat_replication ORDER BY application_name"
```

The configured policy is quorum synchronous replication `ANY 1` with `dataDurability: required`. Confirmed commits require at least one eligible synchronous replica. If no replica is eligible, writes can block rather than weakening durability silently.

## 10. Run backup and PITR tests

### Manual backup

```bash
./scripts/test-backup.sh
```

The test creates a CloudNativePG `Backup`, waits for completion, and runs a second Job that verifies Barman objects in the S3-compatible bucket. A completed CR without object verification is not treated as sufficient evidence.

Inspect status:

```bash
"$KUBECTL_BIN" -n postgres-lab get backup.postgresql.cnpg.io
"$KUBECTL_BIN" -n postgres-lab describe backup.postgresql.cnpg.io postgres-ha-manual
```

### Point-in-time recovery

```bash
./scripts/test-pitr.sh
```

The PITR test:

1. ensures a successful base backup exists;
2. writes a marker before the recovery target;
3. records the target using the PostgreSQL server clock;
4. writes a second marker after the target;
5. switches and verifies WAL archival;
6. creates an isolated recovery cluster;
7. verifies that the first marker exists and the second does not;
8. reports restore time;
9. removes the temporary cluster and ConfigMap.

Expected output resembles:

```text
PASS: PITR target=... before=1 after=0 restore_seconds=...
```

A backup strategy is not considered validated until restore or PITR succeeds.

## 11. Optional failover test

This test deletes the current primary PostgreSQL Pod. Run it only on an approved lab cluster:

```bash
ALLOW_DESTRUCTIVE_TESTS=true ./scripts/test-failover.sh
```

The script verifies that:

- another instance becomes primary;
- a committed probe remains readable;
- all three instances return to Ready;
- synchronous replication is restored.

Applications must still implement connection retry and reconnect logic. A Kubernetes Service cannot make existing TCP sessions survive primary promotion.

## 12. Install everything in one command

After worker preparation and repository validation, a clean cluster can be installed in the required order with:

```bash
./scripts/install-platform.sh
```

The sequence is:

1. cert-manager, CloudNativePG, and Barman Cloud Plugin;
2. Longhorn and StorageClasses;
3. MinIO, bucket, dedicated Barman user, and S3 smoke test;
4. PostgreSQL HA and synchronous replication validation.

For troubleshooting, use the phase-specific scripts instead of rerunning the entire stack blindly.

## 13. Operational checks

### Cluster and placement

```bash
"$KUBECTL_BIN" get nodes
"$KUBECTL_BIN" -n postgres-lab get cluster,pod,pvc -o wide
"$KUBECTL_BIN" -n longhorn-system get volumes.longhorn.io \
  -o custom-columns='VOLUME:.metadata.name,STATE:.status.state,HEALTH:.status.robustness,NODE:.status.currentNodeID,SIZE:.spec.size'
```

### Operators

```bash
"$KUBECTL_BIN" -n cert-manager get pods
"$KUBECTL_BIN" -n cnpg-system get pods
"$KUBECTL_BIN" -n cnpg-system logs deployment/cnpg-cloudnative-pg --tail=200
"$KUBECTL_BIN" -n cnpg-system logs deployment/barman-cloud --tail=200
```

### PostgreSQL events and logs

```bash
"$KUBECTL_BIN" -n postgres-lab describe cluster.postgresql.cnpg.io postgres-ha
"$KUBECTL_BIN" -n postgres-lab get events --sort-by=.lastTimestamp
"$KUBECTL_BIN" -n postgres-lab logs "$primary" -c postgres --tail=200
```

### Scheduled backups

```bash
"$KUBECTL_BIN" -n postgres-lab get scheduledbackup.postgresql.cnpg.io postgres-ha-daily -o yaml
"$KUBECTL_BIN" -n postgres-lab get backup.postgresql.cnpg.io --sort-by=.metadata.creationTimestamp
```

The schedule uses CloudNativePG's six-field cron syntax and runs daily at 02:00.

## 14. Troubleshooting

### Longhorn nodes are not schedulable

Check host prerequisites and the node label:

```bash
"$KUBECTL_BIN" get nodes --show-labels | grep 'node.longhorn.io/create-default-disk=true'
"$KUBECTL_BIN" -n longhorn-system describe nodes.longhorn.io WORKER_NAME
```

On the affected worker, verify `iscsid`, `iscsi_tcp`, mount propagation, and free space under `/var/lib/longhorn`.

### A PVC remains Pending

```bash
"$KUBECTL_BIN" -n postgres-lab describe pvc PVC_NAME
"$KUBECTL_BIN" -n postgres-lab get events --sort-by=.lastTimestamp
"$KUBECTL_BIN" -n longhorn-system get nodes.longhorn.io
```

Common causes are insufficient Longhorn capacity, a non-schedulable worker, missing CSI components, or required anti-affinity with fewer than three eligible workers.

### MinIO remains Pending or cannot roll out

Confirm that the Deployment strategy is `Recreate` and that only one MinIO PVC exists in `minio-lab`:

```bash
"$KUBECTL_BIN" -n minio-lab get deployment minio \
  -o jsonpath='{.spec.strategy.type}{"\n"}'
"$KUBECTL_BIN" -n minio-lab get pvc,pod -o wide
```

A `RollingUpdate` surge can deadlock when a second Pod on another node tries to mount the same RWO volume.

### PostgreSQL Pods remain Pending

Confirm three eligible workers and required anti-affinity:

```bash
"$KUBECTL_BIN" get nodes
"$KUBECTL_BIN" -n postgres-lab describe pod PENDING_POD
```

The manifest intentionally does not place PostgreSQL on the control-plane and does not co-locate two instances on one worker.

### Writes block after failures

Inspect synchronous replica state. With `dataDurability: required`, write blocking is expected when no synchronous replica is eligible. Restore replica health first. Changing to `preferred` trades strict local RPO for write availability and must be an explicit operational decision.

### Backup or WAL archiving fails

```bash
"$KUBECTL_BIN" -n postgres-lab describe objectstore.barmancloud.cnpg.io postgres-ha-backups
"$KUBECTL_BIN" -n postgres-lab describe backup.postgresql.cnpg.io postgres-ha-manual
"$KUBECTL_BIN" -n cnpg-system logs deployment/barman-cloud --tail=200
"$KUBECTL_BIN" -n minio-lab logs deployment/minio --tail=200
```

Check that `s3-backup-credentials` exists, MinIO is reachable at its internal Service, and the `postgres-backups` bucket configuration Job completed. Do not print or copy Secret values into troubleshooting output.

### Kustomize fails while rendering charts

Use the project command, which enables Helm inflation:

```bash
"$KUBECTL_BIN" kustomize platform/longhorn --enable-helm >/tmp/longhorn.yaml
```

The project intentionally removes Longhorn Helm hook Jobs from the declarative render. Do not apply upstream uninstall hooks as ordinary Jobs.

## 15. Cleanup and reset

Cleanup is destructive. Back up anything that must be retained before proceeding.

Remove the PostgreSQL cluster first:

```bash
"$KUBECTL_BIN" -n postgres-lab delete cluster.postgresql.cnpg.io postgres-ha --wait=true
```

`longhorn-postgres` uses reclaim policy `Retain`; deleting the Cluster or PVC does not guarantee automatic deletion of the underlying database volumes. Inspect retained PVs and Longhorn volumes individually before deleting them:

```bash
"$KUBECTL_BIN" get pv
"$KUBECTL_BIN" -n longhorn-system get volumes.longhorn.io
```

Remove the lab MinIO resources only after deciding whether its backup objects are disposable:

```bash
"$KUBECTL_BIN" delete namespace minio-lab
```

Do not uninstall Longhorn while any required volume remains attached or retained. Operators should be removed only after all CloudNativePG clusters, backups, ObjectStores, and plugin resources have been removed.

## 16. Lab limitations and production path

This repository proves component integration and recovery behavior. It does not make the reference cluster production-ready.

Current limitations:

- one control-plane node;
- worker system disks are shared with Longhorn;
- one Longhorn copy per PVC;
- MinIO and PostgreSQL share the cluster failure domain;
- no external secret manager;
- no complete metrics, logs, alerts, or capacity dashboards;
- no tested worker or zone shutdown;
- measured results come from one lab environment.

Production changes:

1. deploy an HA Kubernetes control plane across independent failure domains;
2. use dedicated and monitored storage devices, or a production storage service;
3. use independent external object storage such as S3, Ceph RGW, or external MinIO;
4. manage credentials with Vault, External Secrets Operator, or the platform's secret manager;
5. add monitoring and alerts for PostgreSQL, CloudNativePG, Longhorn, backup age, WAL archival, capacity, and node health;
6. test application reconnect behavior during switchover and failover;
7. repeat backup, restore, PITR, worker-loss, upgrade, and capacity-exhaustion exercises;
8. define RPO and RTO from repeated evidence;
9. review whether `required` or `preferred` synchronous durability matches the business requirement;
10. use GitOps only when a reconciliation controller and its operational ownership are explicitly required.

The S3 integration is intentionally backend-neutral. Replacing the lab MinIO endpoint and credentials with an external S3-compatible service does not require redesigning the PostgreSQL cluster.
