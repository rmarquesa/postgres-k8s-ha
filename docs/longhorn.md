# Longhorn in the k3s lab

## Scope

Longhorn is installed from the official `longhorn/longhorn` chart pinned to `1.12.0`. This installation uses up to approximately 10 GiB from each system disk on the three workers. No disks were added to the VMs.

```text
worker root disk ~50 GiB
├── operating system and k3s
└── /var/lib/longhorn
    ├── 80% of the filesystem reserved
    └── ~10 GiB maximum advertised to Longhorn
```

This layout is acceptable for a lab, not production. Production requires suitable dedicated storage, real failure domains, latency/capacity monitoring and measured sizing.

## Prerequisites

Each Ubuntu worker requires:

- `open-iscsi`;
- active and enabled `iscsid` service;
- `nfs-common` for RWX and NFS-dependent operations;
- `dmsetup` and `cryptsetup` for volume features;
- mount propagation supported by kubelet;
- sufficient free space in `/var/lib/longhorn`.

The control-plane does not receive a Longhorn disk. The installer labels only nodes without `node-role.kubernetes.io/control-plane`.

## Installation

```bash
export KUBECONFIG=/path/to/kubeconfig
export KUBECTL_BIN=kubectl
./scripts/install-longhorn.sh
```

The script:

1. validates cluster access;
2. labels workers with `node.longhorn.io/create-default-disk=true`;
3. renders official `longhorn/longhorn` chart `1.12.0` through Kustomize;
4. removes Helm hooks that would be unsafe as normal resources;
5. applies the chart and StorageClasses with server-side apply;
6. waits for managers/CSI and validates Longhorn Nodes.

## Values explained

| Field | Value | Reason |
| --- | --- | --- |
| `persistence.defaultClass` | `false` | does not implicitly change the cluster's default StorageClass |
| `persistence.reclaimPolicy` | `Retain` | reduces accidental deletion risk for non-ephemeral volumes |
| `createDefaultDiskLabeledNodes` | `true` | prevents the control-plane or future nodes from receiving storage automatically |
| `defaultDataPath` | `/var/lib/longhorn` | conventional V1 data-engine path |
| `defaultReplicaCount` | `1` | avoids duplicate replication with CloudNativePG |
| `storageOverProvisioningPercentage` | `100` | no thin overcommit in the small lab |
| `storageMinimalAvailablePercentage` | `10` | makes the disk unschedulable before the filesystem is exhausted |
| `storageReservedPercentageForDefaultDisk` | `80` | limits Longhorn to approximately 10 GiB of the 50 GiB disk |
| `upgradeChecker` | `false` | avoids unnecessary external calls |

## StorageClasses

### `longhorn-postgres`

- one replica;
- `strict-local` to place the replica with the PostgreSQL instance;
- `Retain` to protect against accidental deletion;
- online expansion enabled;
- `WaitForFirstConsumer` so topology is selected with the Pod known.

### `longhorn-lab`

- one replica;
- `best-effort` locality;
- `Delete`, because it serves disposable components such as lab MinIO;
- not the default StorageClass.

## Capacity

With percentage-based reservation, the limit follows actual filesystem size. On a 50.88 GB filesystem, an 80% reservation leaves approximately 10.18 decimal GB, or 9.48 GiB.

This capacity must not be filled. PostgreSQL uses 5 GiB per instance and MinIO uses 2 GiB, leaving headroom for snapshots and scheduling variation. Longhorn snapshots do not replace Barman backups in MinIO/S3.

## When not to use this configuration

- production data;
- a root disk under pressure or with unpredictable capacity;
- a requirement for the same PVC to survive worker loss;
- a requirement for more than one storage replica;
- workloads whose reserved total exceeds approximately 10 GiB per node.
