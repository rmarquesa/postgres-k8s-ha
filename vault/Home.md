# PostgreSQL K8s HA

Vault do projeto de referência para PostgreSQL altamente disponível no cluster k3s-Proxmox e para posterior publicação no GitHub.

## Navegação

- [[Architecture]]
- [[Decisions]]
- [[Current State]]

## Documentação canónica do repositório

- [README](../README.md)
- [Arquitetura detalhada](../docs/architecture.md)
- [Decisões arquiteturais](../docs/decisions.md)
- [Baseline do cluster](../docs/cluster-baseline.md)
- [Contrato de implementação](../docs/implementation-contract.md)
- [Instalação Kustomize](../docs/kustomize.md)
- [Perfil production](../docs/production.md)
- [Resultados de validação](../docs/validation-results.md)

## Princípio operacional

O projeto não está concluído quando os manifests existem. Está concluído quando failover, backup, restore e PITR foram executados e os RPO/RTO foram medidos.
