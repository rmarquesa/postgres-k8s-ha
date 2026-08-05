# Alert runbook

All commands require an explicitly selected `KUBECONFIG` and namespace. Start read-only. Do not delete Pods, restart nodes, raise limits, or terminate sessions until the failure and blast radius are understood.

```bash
kubectl config current-context
kubectl -n postgres-prod get cluster,pod,pvc
kubectl -n postgres-prod get events --sort-by=.lastTimestamp
```

Correlate the alert with the CloudNativePG dashboard, application errors, recent changes and object-storage health. Never paste Secret data, connection strings or raw production queries into incident notes.

## PostgresHANotExactlyOnePrimary

1. Confirm the CNPG control plane view: `kubectl -n postgres-prod get cluster postgres-ha -o wide`.
2. Inspect role labels on all instances: `kubectl -n postgres-prod get pod -l cnpg.io/cluster=postgres-ha -L role -o wide`.
3. Check node reachability and events before assuming split-brain.
4. If two writable primaries are independently confirmed, fence the isolated node/network path first and stop application writes. Do not delete either instance until the incident owner selects the authoritative timeline.

## PostgresHAInstanceUnavailable

1. Identify the missing/unhealthy instance and node.
2. Check Pod events, PVC attachment and node conditions.
3. Confirm one primary and at least one synchronous replica remain healthy.
4. Restore node/storage capacity; let CNPG rebuild the replica. Do not copy `PGDATA` manually.

## PostgresHAReplicationLag

1. Determine whether lag is byte, replay or client-visible lag in the dashboard.
2. Check storage latency, CPU saturation, network loss and long-running queries on the replica.
3. Confirm WAL retention and disk headroom before restarting anything.
4. Scale or repair the bottleneck. Do not drop the replica merely to clear the alert.

## PostgresHAReplicaReceiverDown

1. Inspect replica and operator logs with bounded tails.
2. Confirm Service endpoints, NetworkPolicies and certificates are healthy.
3. Check whether a node/storage interruption explains the receiver loss.
4. Allow CNPG reconciliation; replace the replica only after the operator reports an unrecoverable state.

## PostgresHABackupStale

1. Inspect `ScheduledBackup`, recent `Backup` resources and Barman plugin logs.
2. Confirm object-store availability, credentials metadata and bucket capacity without printing Secret values.
3. Verify WAL archiving before triggering a new base backup.
4. Run an on-demand backup and confirm objects exist. The incident remains open until a restore drill proves usability.

## PostgresHAWALArchiveStale

1. Check current WAL generation and archive status on the primary.
2. Inspect Barman sidecar/plugin logs and S3 reachability.
3. Confirm credentials have not expired and the archive prefix/serverName has not changed.
4. Treat an outage longer than the approved RPO as a data-protection incident.

## PostgresHAWALArchiveFailure

Use the same checks as `PostgresHAWALArchiveStale`. A newer successful archive can clear the immediate symptom, but recurring failures require root-cause analysis of S3 throttling, DNS/TLS, credentials or resource pressure.

## PostgresHAConnectionsHigh

1. Compare active, idle and waiting backends with pool size and application replicas.
2. Check leaked/long-lived sessions and retry storms.
3. Fix pool/retry behaviour first. Raising `max_connections` without memory and workload evidence is not remediation.

## PostgresHALongRunningTransaction

1. Identify the owner, state, wait event and transaction age in `pg_stat_activity` using a privileged read-only incident role.
2. Contact the workload owner and assess locks/WAL/vacuum impact.
3. Prefer `pg_cancel_backend`; use `pg_terminate_backend` only with incident-owner approval.

## PostgresHADeadlockDetected

Capture the deadlock log and involved transaction paths. Fix lock ordering or transaction scope in the application. Increasing timeouts does not resolve deadlocks.

## PostgresHAPVCUsageHigh

1. Confirm actual filesystem and PVC usage plus growth rate.
2. Check WAL backlog, retained backups, temp files and table/index growth.
3. Expand through the StorageClass/CNPG workflow only after provider headroom is confirmed.
4. Vacuum is not a generic disk-reclamation command; investigate bloat before acting.
