# Implementation contract

This contract defines when the platform may be considered ready. The existence of YAML does not satisfy the objective.

## Profiles

### Lab

- three PostgreSQL instances;
- configurable `5Gi` storage per instance;
- minimum resources defined after measurement;
- synchronous replication `ANY 1`;
- `dataDurability: required`;
- one Longhorn replica per PVC;
- standalone in-cluster MinIO with a `2Gi` PVC for S3 tests;
- locally created, unversioned credentials.

### Production reference

- mandatory capacity parameters;
- `dataDurability: required`;
- hostname anti-affinity and topology spread by failure domain;
- cluster-specific, `strict` Sealed Secrets with externally protected sealing keys;
- TLS, NetworkPolicies, Pod Security and RBAC;
- alerts, dashboards, runbooks and periodic restore drills;
- no CPU, RAM, IOPS or RTO values presented as universal.

## Initial SLO targets

| Indicator | Initial target | Evidence |
| --- | --- | --- |
| RPO during a single failover | 0 for confirmed commits in `required` mode | monotonic sequence before/after failover |
| Failover RTO | < 60 s | measure last confirmed write to first write after promotion |
| Object-storage RPO | < 5 min | compare latest recoverable WAL with source timestamp |
| Lab PITR | < 30 min | complete test in a new cluster |
| Backup | daily base backup | CNPG status + S3 objects + restore |
| Retention | 7 days | Barman policy and inspection of recoverable backups |

These are validation-environment targets, not guarantees for arbitrary hardware.

## Acceptance gates

### Gate 0 — Prerequisites

- compatible `kubectl` client;
- kubeconfig and context confirmed;
- three Ready workers;
- storage paths identified;
- Longhorn requirements verified for the lab;
- S3 endpoint and Secret flow selected.

### Gate 1 — Storage

- Longhorn healthy on all three lab workers;
- StorageClasses rendered and documented;
- expansion validated;
- controlled replica/volume loss tested;
- latency, throughput and fsync benchmark retained as an artifact.

### Gate 2 — Operators and Kustomize

- official charts pinned and inflated by Kustomize;
- CloudNativePG and Barman plugin available;
- CRDs established before dependent custom resources;
- values, kustomizations and manifests stored in the project;
- unsafe Helm hooks removed from rendered output;
- no plaintext Secret in Git.

### Gate 3 — PostgreSQL

- three instances across three workers;
- functional RW/RO services;
- synchronous replication observed in PostgreSQL;
- slots and WAL verified;
- primary failover and replica reconstruction measured.

### Gate 4 — Backup/PITR

- base backup completed;
- WAL archived continuously;
- controlled DELETE executed;
- new cluster recovered to an earlier timestamp;
- before/after data compared;
- recovery does not overwrite the source cluster.

### Gate 5 — Operations

- alerts exercised;
- dashboards loaded;
- logs available in the target logging platform;
- executable runbooks;
- upgrades and expansion documented;
- worker drain and abrupt worker-loss tests completed.

## Destructive tests

Any test that deletes Pods, volumes or nodes must simultaneously require:

- an allowed context;
- a test namespace;
- explicit target identification;
- `ALLOW_DESTRUCTIVE_TESTS=true`;
- backup and health pre-checks;
- evidence collected before and after.

The source cluster is never destroyed to test PITR; recovery creates a new cluster.

## Definition of Done

The platform is complete only when:

1. all manifests render and validate;
2. Kustomize scripts are idempotent and observed state matches project files;
3. failover, backup, restore and PITR have actually been executed;
4. measured RPO/RTO values are recorded;
5. Secrets do not appear in Git history;
6. alerts have an owner, severity and runbook;
7. limitations and environmental dependencies are documented;
8. a second operator can follow the runbooks without implicit knowledge.
