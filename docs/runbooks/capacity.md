# Capacity and load runbook

No CPU, memory, IOPS, TPS or latency number in this repository is a universal production threshold. Freeze workload-specific thresholds before running the gate.

## Inputs

- peak TPS and expected growth;
- read/write mix and dataset size;
- clients/jobs and pool size;
- transaction/query distribution;
- p95/p99 latency and error-rate SLOs;
- backup/maintenance overlap;
- CPU, memory, storage latency/IOPS, PVC and WAL headroom;
- soak duration and rebuild/failover thresholds.

## Procedure

1. Restore an anonymized production-scale dataset or initialize `pgbench` at a representative scale.
2. Warm caches using the documented workload.
3. Run stepped load, increasing one fixed increment at a time.
4. At each step record TPS, p50/p95/p99, errors, CPU throttling, memory, connections, locks, WAL generation/archive, replication lag and storage latency.
5. Stop at the first SLO, saturation or stability violation.
6. Define sustainable capacity as the last passing step, not the failure point.
7. Require approved headroom between target peak and sustainable capacity.
8. Run a soak at target load through backup and maintenance windows.
9. Repeat target load while executing controlled switchover and abrupt worker-loss gates.

Do not tune PostgreSQL from generic formulas before observing the workload. Change one parameter class at a time and retain before/after evidence.

## Pass criteria

- target TPS sustained for the approved soak duration;
- p95/p99 and error rate stay inside frozen limits;
- no OOM, CPU throttling instability, connection exhaustion or PVC pressure;
- replication and WAL archive stay inside RPO;
- backup completes without violating application SLOs;
- failover and rebuild remain inside approved thresholds.

Store raw `pgbench` progress output and monitoring snapshots in a timestamped evidence directory with SHA-256 checksums. Do not store credentials or connection URIs.
