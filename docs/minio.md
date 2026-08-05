# Lab MinIO

## Purpose

MinIO provides an S3-compatible endpoint inside the same cluster only to develop and test:

- Barman Cloud CNPG-I;
- base backups;
- WAL archiving;
- restore;
- PITR.

```text
PostgreSQL/CNPG ─▶ Barman plugin ─▶ MinIO Service ─▶ 2 GiB Longhorn PVC
```

It is not a disaster-recovery boundary: a cluster failure can remove PostgreSQL and MinIO simultaneously. Production must use independent external object storage.

## Implementation

- chart: official/community `minio/minio` from `https://charts.min.io/`;
- chart version: `5.4.0`;
- MinIO: `RELEASE.2024-12-18T13-15-44Z`;
- mode: standalone;
- storage: `2Gi` PVC, `longhorn-lab` StorageClass;
- access: HTTP `ClusterIP` only;
- private bucket: `postgres-backups`, with versioning;
- root credentials: Secret generated locally by the installer, never stored in Git;
- Barman credentials: dedicated user with policy restricted to the bucket;
- update strategy: `Recreate`, required by a standalone Deployment with an RWO PVC;
- upstream default user `console/console123`: explicitly disabled and removed.

The community chart is behind more recent commercial MinIO offerings. It is accepted here because this component is ephemeral, internal and intended for testing. It must be removed or updated if compatible fixes stop being published.

## Installation

```bash
export KUBECONFIG=/path/to/kubeconfig
export KUBECTL_BIN=kubectl
./scripts/install-minio.sh
```

The script:

1. renders the official chart through Kustomize;
2. generates `minio-root-credentials` only when the Secret does not already exist;
3. applies the `Recreate` strategy to avoid RWO deadlock during upgrades;
4. creates the bucket/versioning and dedicated Barman user through a Kustomize Job;
5. materializes the Barman Secret in the PostgreSQL namespace without printing values;
6. runs the S3 smoke test.

Existing credentials are preserved across repeated applies and are never written to files.

## In-cluster endpoint

```text
http://minio.minio-lab.svc.cluster.local:9000
```

HTTP use is deliberate and limited to the internal lab network. Production must use TLS and external object storage.

## S3 test

```bash
./scripts/test-minio.sh
```

The Job consumes credentials through `secretKeyRef` and validates:

1. endpoint configuration;
2. object upload;
3. `stat`;
4. download and comparison;
5. object deletion.

The test does not print credentials.
