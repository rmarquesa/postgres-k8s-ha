# PostgreSQL K8s HA

Project vault for the highly available PostgreSQL reference implementation, its k3s-Proxmox lab validation and public GitHub delivery.

## Navigation

- [[Architecture]]
- [[Decisions]]
- [[Current State]]

## Canonical repository documentation

- [Project website](https://rmarquesa.github.io/postgres-k8s-ha/)
- [README](../README.md)
- [Detailed architecture](../docs/architecture.md)
- [Architecture decisions](../docs/decisions.md)
- [Cluster baseline](../docs/cluster-baseline.md)
- [Implementation contract](../docs/implementation-contract.md)
- [Kustomize delivery](../docs/kustomize.md)
- [Production profile](../docs/production.md)
- [Observability](../docs/observability.md)
- [Runbooks](../docs/runbooks/alerts.md)
- [Validation results](../docs/validation-results.md)

## Operating principle

The project is not complete when manifests exist. It is complete when failover, backup, restore and PITR have been exercised and the relevant RPO/RTO measurements have been recorded.
