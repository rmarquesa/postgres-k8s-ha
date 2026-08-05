# Production profile

The production profile targets a prepared HA Kubernetes environment. It does not install Longhorn or MinIO and it must not be applied unchanged.

## Contract

The target environment must provide:

- an HA Kubernetes control plane across independent failure domains;
- at least three database workers plus spare capacity for maintenance/rebuild;
- the `topology.kubernetes.io/zone` node label;
- a production StorageClass exposed as `postgres-production`, or a per-cluster patch that replaces it;
- external HTTPS S3-compatible object storage outside the database failure domain;
- the Sealed Secrets controller and three strict, cluster-bound SealedSecrets;
- a CNI enforcing Kubernetes NetworkPolicy;
- a Prometheus-compatible monitoring stack;
- capacity and SLO thresholds approved before acceptance testing.

## Reference defaults

`databases/postgres-ha-production` starts with three instances, `100Gi` per instance, requests of `2 CPU/4Gi`, limits of `4 CPU/8Gi`, synchronous `ANY 1`, `dataDurability: required`, supervised primary updates, PDB management and zone spreading.

These values are a reference floor, not universal sizing. Patch them from measured workload and storage results before deployment.

The checked-in S3 endpoint ends in `.invalid` and the bucket contains `replace-with-production-bucket`. This is intentional: `scripts/check_production.py` rejects unresolved placeholders.

## Secrets

Install the pinned controller:

```bash
export KUBECONFIG=/path/to/production.kubeconfig
export EXPECTED_CONTEXT=production-context
./scripts/install-sealed-secrets.sh
```

Create each encrypted manifest with values loaded into the shell by the approved password manager:

```bash
export SECRET_KIND=s3
export ACCESS_KEY_ID='...'
export ACCESS_SECRET_KEY='...'
export OUTPUT=clusters/<cluster-id>/secrets/s3-backup-credentials.sealed.yaml
./scripts/seal-production-secret.sh
unset ACCESS_KEY_ID ACCESS_SECRET_KEY

export SECRET_KIND=app-migrator
export DB_PASSWORD='...'
export OUTPUT=clusters/<cluster-id>/secrets/app-migrator-credentials.sealed.yaml
./scripts/seal-production-secret.sh
unset DB_PASSWORD

export SECRET_KIND=app-runtime
export DB_PASSWORD='...'
export OUTPUT=clusters/<cluster-id>/secrets/app-runtime-credentials.sealed.yaml
./scripts/seal-production-secret.sh
unset DB_PASSWORD
```

Do not reuse ciphertext between clusters. The default strict scope binds it to the Secret name and namespace.

The CloudNativePG-managed replication credentials, internal certificates and ServiceAccount tokens are not sealed by this project.

## Controller disaster recovery

Back up all Secrets labelled `sealedsecrets.bitnami.com/sealed-secrets-key` directly to an encrypted external vault with access control and audit. Never write them inside this repository. Test restoration in an isolated cluster periodically. An etcd backup is additional protection, not a replacement for an independently protected key backup.

## Database roles

The profile defines:

- `app_owner`: `NOLOGIN`, owns the application database;
- `app_migrator`: login role that inherits `app_owner`, used only by the migration pipeline;
- `app_runtime`: restricted login role for the application.

Application migrations must grant only the required schema/table/sequence privileges to `app_runtime`. The runtime role does not inherit the owner role.

## Per-cluster changes

Before applying, patch at least:

- StorageClass and PVC size;
- CPU/memory requests and limits;
- S3 endpoint, bucket/prefix and retention;
- Barman `serverName` (immutable archive identity; never reuse it for unrelated clusters);
- backup schedule and compliance retention;
- client and monitoring namespace labels;
- optional endpoint CA for private PKI;
- PostgreSQL parameters proven by load tests.

Render and validate:

```bash
kubectl kustomize databases/postgres-ha-production > /tmp/postgres-production.yaml
python3 scripts/check_production.py /tmp/postgres-production.yaml
kubectl apply --server-side --dry-run=server \
  --field-manager=postgres-k8s-ha-production \
  -f /tmp/postgres-production.yaml
```

Production apply must not use `--force-conflicts`. Review `kubectl diff` and resolve field ownership deliberately.

## Network access

The namespace defaults to deny ingress. PostgreSQL accepts:

- replication traffic from the same CNPG cluster;
- clients only from namespaces labelled `postgres-k8s-ha.io/client=true`;
- monitoring only from namespaces labelled `postgres-k8s-ha.io/monitoring=true`;
- operator traffic from `cnpg-system`.

Egress is not restricted in the portable profile because standard NetworkPolicy cannot express S3 FQDNs safely. Enforce egress with the target CNI or platform firewall and allow only DNS, Kubernetes API requirements and the external object-store endpoints.
