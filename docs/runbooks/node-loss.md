# Worker loss runbook

This test is destructive and must run only in an isolated acceptance environment equivalent to production. The current shared lab is not approved for abrupt worker shutdown.

## Preconditions

- control plane is HA and healthy;
- three PostgreSQL instances occupy distinct workers/failure domains;
- spare capacity can schedule/rebuild a replacement;
- backup and WAL archive gates are green;
- application retry/reconnect behaviour is enabled;
- a continuous write/probe workload is recording acknowledged commits, errors, latency and throughput;
- thresholds are frozen before execution;
- hypervisor/cloud fencing and recovery access are available;
- incident owner and rollback authority are assigned.

## Procedure

1. Capture cluster, node, Pod, PVC, PDB, replication and synchronous-standby state.
2. Identify the worker hosting the current primary.
3. Start the acceptance workload from a different failure domain and confirm its baseline.
4. Abruptly power off or isolate the primary worker at the infrastructure layer. Do not drain it; this test covers ungraceful loss.
5. Measure:
   - node failure detection;
   - new-primary election;
   - first successful reconnect/write through the RW Service;
   - error/retry interval;
   - acknowledged commit continuity;
   - p95/p99 latency and throughput before/during/after.
6. Confirm exactly one primary and a healthy synchronous replica.
7. Keep the old worker fenced until the authoritative primary is confirmed.
8. Restore the worker, then uncordon/reconnect it under operator control.
9. Wait for CNPG to rebuild/rejoin the replica and return to three healthy instances.
10. Re-run consistency checks and the post-failure workload window.

## Pass criteria

- exactly one primary throughout the authoritative cluster view;
- no acknowledged commit is lost with `dataDurability: required` and one failure;
- client-visible recovery is within approved RTO;
- error rate, p95/p99 and throughput satisfy frozen thresholds;
- WAL archive remains inside RPO;
- restored node does not become a second writable primary;
- cluster returns to three healthy instances inside the rebuild threshold.

Any missing evidence is a failed gate, not an assumed pass.

## Emergency response

If two writable primaries are suspected, stop application writes and fence the isolated node/network path first. Preserve logs/timelines. Do not delete Pods/PVCs or reattach storage until the incident owner selects the authoritative timeline.
