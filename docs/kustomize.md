# Installation with Kustomize

## Decision

Kustomize is the single composition and installation layer. This does not introduce GitOps: there is no Argo CD or continuous reconciliation at this stage.

Official charts remain in use through `helmCharts`:

| Layer | Source | Version |
| --- | --- | --- |
| cert-manager | `https://charts.jetstack.io` | `v1.21.1` |
| CloudNativePG | `https://cloudnative-pg.github.io/charts` | chart `0.29.0`, app `1.30.0` |
| Longhorn | `https://charts.longhorn.io` | `1.12.0` |
| MinIO | `https://charts.min.io/` | chart `5.4.0` |
| Sealed Secrets | `https://bitnami.github.io/sealed-secrets` | chart `2.19.1` |
| Barman Cloud Plugin | upstream release manifest | `v0.14.0` |

## Order

`install-platform.sh` applies components sequentially:

1. cert-manager;
2. CloudNativePG;
3. Barman Cloud Plugin;
4. Longhorn and StorageClasses;
5. MinIO;
6. PostgreSQL ObjectStore, Cluster and ScheduledBackup.

Sealed Secrets is installed separately with `install-sealed-secrets.sh` because production ciphertext is bound to the target cluster controller key.

The order is required because CRDs and webhooks must be established before dependent custom resources.

## Applied command

Each layer is rendered and applied by `scripts/lib/kustomize.sh`:

```bash
kubectl kustomize <directory> --enable-helm
kubectl apply --server-side --force-conflicts \
  --field-manager=postgres-k8s-ha -f <render>
```

`--force-conflicts` allows the project to act as the declared field manager and supports migration of resources initially created by Helm. It must not be reused to take ownership of resources outside this project's scope. The production profile and monitoring installer deliberately do not use `--force-conflicts`.

## MinIO namespace

With this Kustomize/chart combination, `helmCharts.namespace` populates `.Release.Namespace`, but rendered MinIO objects do not automatically receive `metadata.namespace`. The overlay applies explicit JSON patches to the ServiceAccount, ConfigMap, Services, PVC and Deployment. `check_render.py` fails if any of them render outside `minio-lab`.

## Helm hooks

Kustomize renders hooks as normal resources. Therefore:

- the `longhorn-pre-upgrade`, `longhorn-post-upgrade` and `longhorn-uninstall` Jobs are explicitly removed by the overlay;
- the `minio-post-job` hook is avoided with `buckets/users/policies: []`;
- bucket creation, versioning, policy and the Barman user are configured by a project-controlled Kustomize Job.

This avoids accidentally running an uninstall hook and prevents immutable Jobs from blocking repeated applies.

## Secrets

Real Secrets are neither rendered by Kustomize nor stored in files:

- `install-minio.sh` generates root credentials when they do not exist;
- `configure-minio-barman.sh` generates a dedicated user and minimum policy;
- the S3 Secret is materialized in the PostgreSQL namespace without printing values.

Production uses cluster-specific, `strict` Sealed Secrets. The controller and workflow are documented in the [production profile](production.md). External Secrets or Vault remains an alternative for environments requiring dynamic rotation.

## Local render

```bash
kubectl kustomize platform/longhorn --enable-helm
kubectl kustomize platform/minio --enable-helm
kubectl kustomize platform/cert-manager --enable-helm
kubectl kustomize platform/cloudnative-pg --enable-helm
kubectl kustomize platform/sealed-secrets --enable-helm
kubectl kustomize platform/barman-cloud
kubectl kustomize databases/postgres-ha
kubectl kustomize databases/postgres-ha-production
kubectl kustomize monitoring/cloudnative-pg --enable-helm
```

Downloaded `charts/` directories are local inflator caches and are ignored by Git.
