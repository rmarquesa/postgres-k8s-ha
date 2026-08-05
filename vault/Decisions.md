# Decisions

## Decisões atuais

- Publicar como `postgres-k8s-ha`.
- Usar o cluster k3s-Proxmox real para validação.
- Não adicionar discos: Longhorn usa até cerca de 10 GiB dos 50 GiB de cada worker.
- Usar `5Gi` por instância PostgreSQL no laboratório.
- Usar CloudNativePG com três instâncias, uma base e quorum `ANY 1`.
- Usar `dataDurability: required` para manter RPO local zero quando existe quorum.
- Usar uma réplica Longhorn `strict-local` por volume PostgreSQL.
- Usar MinIO standalone dentro do cluster apenas para testes S3/PITR.
- Usar Barman Cloud CNPG-I e interface S3-compatible.
- Criar secrets localmente no laboratório, nunca no Git.
- Usar Kustomize como camada única de composição/instalação; charts oficiais entram por `helmCharts`.
- Não instalar Argo CD nesta fase; GitOps é evolução futura.
- Manter Nexus interno em HTTP.
- Usar Grafana Alloy em vez de Promtail.

## Limites

- MinIO interno não é DR.
- Um control-plane não torna toda a plataforma HA.
- RTO observado não é SLA universal.
- Clientes precisam de retry/reconnect durante failover/switchover.
