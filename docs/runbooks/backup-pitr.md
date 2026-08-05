# Backup and PITR runbook

## Policy

Production requires continuous WAL archive, at least daily base backups, external object storage, retention set by compliance and a restore drill on a schedule. Object-store lifecycle/immutability is configured outside this repository and must not delete objects inside the active PITR window.

## Daily checks

- latest successful base backup age is within the alert threshold;
- WAL archive is current and has no newer failure than success;
- object-store capacity, versioning/lifecycle and access logs are healthy;
- `serverName` still identifies the same PostgreSQL timeline/archive;
- no credentials or endpoint changes are pending.

## On-demand backup

1. Confirm context, namespace, cluster health and WAL archive health.
2. Create a `Backup` referencing the existing `ObjectStore`; do not embed credentials.
3. Wait for `Completed` and record timestamps/duration.
4. Verify backup and WAL objects with metadata only.
5. A completed backup is not accepted until the corresponding restore gate passes.

The lab implementation is executable with `scripts/test-backup.sh`.

## PITR drill

1. Select a target timestamp inside the verified archive window.
2. Create a new cluster name and independent PVCs; never restore over the source cluster.
3. Use the same `ObjectStore` and immutable `serverName` archive identity.
4. Wait for recovery, then verify:
   - target timeline and timestamp;
   - pre-target marker/data exists;
   - post-target marker/data is absent;
   - application roles, extensions and schema exist;
   - read/write smoke test passes through the new RW Service.
5. Record RTO from resource creation to application-ready verification.
6. Delete the drill cluster only after evidence is stored and approved.

The lab implementation is executable with `scripts/test-pitr.sh`.

## Disaster recovery

When the source cluster is unavailable:

1. fence the old write path before exposing the recovered cluster;
2. restore into prepared compute/storage using external object storage;
3. verify archive continuity and choose target time/timeline;
4. validate roles, certificates, extensions, data and application queries;
5. switch clients with controlled DNS/service configuration;
6. monitor retries, errors and lag;
7. keep the old environment fenced until the recovered cluster is authoritative.

## Evidence

Record resource YAML with Secret data removed, backup identifiers, target timestamp, object metadata, start/end times, RTO, verification queries/results and SHA-256 checksums for the evidence bundle.
