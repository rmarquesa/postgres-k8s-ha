# Architecture

## Lab summary

```text
Apps → RW/RO Service → CloudNativePG (1 primary + 2 replicas)
                         │                 │
                         │                 └→ Longhorn, 5 GiB per instance
                         └→ Barman CNPG-I → in-cluster MinIO, 2 GiB PVC
```

- three instances across three workers;
- synchronous replication with quorum `ANY 1`;
- Longhorn with one replica per PVC and approximately 10 GiB per worker;
- daily base backups and continuous WAL archiving;
- PITR always creates a new cluster;
- Kustomize composes official charts and manifests; there is no GitOps controller at this stage;
- in-cluster MinIO is for testing only and is not disaster recovery;
- the production profile integrates with an existing Prometheus/Grafana stack and leaves logging to the target platform.

The complete explanation and trade-offs are documented in [docs/architecture.md](../docs/architecture.md).
