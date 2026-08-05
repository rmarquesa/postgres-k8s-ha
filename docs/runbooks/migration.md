# Production migration runbook

Migrate into a parallel CNPG cluster; never import directly into an untested final endpoint.

## Discovery

Record without sensitive data:

- source/target PostgreSQL versions and encodings;
- database sizes and growth rate;
- roles/memberships and ownership model;
- required extensions and versions;
- large objects, sequences, publications/subscriptions and scheduled jobs;
- connection count, peak TPS, p95/p99 latency and maintenance windows;
- unsupported superuser/file-system dependencies.

## Rehearsal

1. Provision the production profile with external S3 and approved sizing.
2. Validate runtime and migrator roles, TLS and NetworkPolicies.
3. Export globals and data through encrypted storage/streams; dumps can contain password hashes and sensitive data and must never enter Git.
4. Restore globals selectively, excluding provider/operator-managed roles.
5. Restore schema/data with `pg_restore` jobs calibrated to target I/O.
6. Reconcile ownership and grant only required privileges to `app_runtime`.
7. Validate extensions, row counts, checksums for critical tables, sequences, constraints and application queries.
8. Run `ANALYZE`, workload tests, backup and PITR.
9. Measure total migration/cutover time and rehearse rollback.

## Cutover

1. Lower DNS TTL in advance when DNS is part of the path.
2. Stop or fence source writes; record the final consistency point.
3. Apply the tested delta method (final dump, logical replication catch-up or application-specific sync).
4. Verify zero pending replication/delta and critical data checks.
5. Switch clients to the CNPG RW Service/pool endpoint with TLS verification and retries.
6. Monitor errors, connections, latency, throughput and business checks.
7. Keep the source read-only/fenced until acceptance completes.

## Rollback

Rollback is allowed only before writes diverge, or with a rehearsed reverse-sync strategy. DNS reversal alone is unsafe after the target accepts unique writes.

## Acceptance evidence

Store tool versions, sanitized commands, timings, object counts/checksums, extension/role results, application smoke results, performance comparison, backup/PITR proof and cutover/rollback decisions.
