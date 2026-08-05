# Current State

## Estado

A fundação funcional está instalada e validada no k3s-Proxmox. PostgreSQL, failover de Pod, backup e PITR foram executados realmente.

## Concluído

- instalação estruturada em Kustomize, sem Argo CD;
- cert-manager `v1.21.1`;
- CloudNativePG `1.30.0`;
- Barman Cloud Plugin `v0.14.0`;
- Longhorn `1.12.0`, cerca de 10 GiB por worker;
- StorageClasses `longhorn-postgres` e `longhorn-lab`;
- MinIO standalone, PVC `2Gi`, strategy `Recreate`;
- utilizador Barman dedicado e default inseguro removido;
- PostgreSQL 18.3, três instâncias/PVCs `5Gi` em três workers;
- `ANY 1`, `dataDurability: required`, duas réplicas quorum;
- failover de Pod em 27 s com write preservado;
- backup concluído e objeto validado;
- PITR comprovado por comparação before/after;
- smoke de storage e S3 aprovado.

## Pendente

1. observabilidade Prometheus/Grafana/Loki/Alloy;
2. benchmark de storage/PostgreSQL;
3. teste de perda/drain de worker em janela segura;
4. runbooks de upgrade e capacidade;
5. object storage externo para DR real.

Ver [resultados](../docs/validation-results.md), [Kustomize](../docs/kustomize.md) e [contrato](../docs/implementation-contract.md).
