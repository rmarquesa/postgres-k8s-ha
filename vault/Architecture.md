# Architecture

## Resumo do laboratório

```text
Apps → Service RW/RO → CloudNativePG (1 primary + 2 replicas)
                         │                 │
                         │                 └→ Longhorn, 5 GiB por instância
                         └→ Barman CNPG-I → MinIO interno, PVC 2 GiB
```

- três instâncias em três workers;
- replicação síncrona `ANY 1`;
- Longhorn com uma réplica por PVC e cerca de 10 GiB por worker;
- base backup diário e WAL contínuo;
- PITR cria sempre um cluster novo;
- Kustomize compõe charts oficiais e manifests; não existe controller GitOps nesta fase;
- MinIO interno serve apenas testes e não é DR;
- Prometheus/Grafana e Loki/Alloy serão adicionados depois do fluxo de recovery.

A explicação completa e os trade-offs vivem em [docs/architecture.md](../docs/architecture.md).
