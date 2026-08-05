# Baseline do cluster de validação

Última atualização: 5 de agosto de 2026.

## Cluster

- kubeconfig: externo ao repositório, fornecido por `KUBECONFIG`;
- contexto: `default`;
- k3s: `v1.36.2+k3s1`;
- cliente usado nas instalações: `kubectl v1.36.2` verificado por SHA-256;
- um control-plane e três workers Ready.

| Nó | Papel | CPU | Memória | Endereço |
| --- | --- | ---: | ---: | --- |
| `k8s-master-1` | control-plane | 2 | ~3.8 GiB | rede privada |
| `k8s-worker-1` | worker | 8 | ~15.6 GiB | rede privada |
| `k8s-worker-2` | worker | 8 | ~15.6 GiB | rede privada |
| `k8s-worker-3` | worker | 8 | ~15.6 GiB | rede privada |

O control-plane é único, portanto a API Kubernetes não é HA. Isto não invalida testes de HA do PostgreSQL, mas é uma limitação da plataforma completa.

## Storage físico e virtual

O Proxmox possui:

- `nvme0n1`, XPG GAMMIX S11 Pro, usado pelo thin pool `local-lvm`;
- `sdb`, SSD SATA de aproximadamente 477 GiB, configurado como datastore `ssd` e atualmente vazio.

Cada worker vê apenas um disco virtual de sistema de 50 GiB no `local-lvm`. Por decisão do laboratório, não foram adicionados discos. Longhorn usa `/var/lib/longhorn` nesse filesystem com 80% reservado, limitando a capacidade Longhorn a aproximadamente 10 GiB por worker.

## Pré-requisitos Longhorn aplicados

Nos três workers:

- `open-iscsi` instalado;
- `iscsid` enabled e active;
- `nfs-common` instalado;
- `cryptsetup` e `dmsetup` presentes;
- módulo `iscsi_tcp` carregável;
- sudo não interativo disponível para o bootstrap.

## Componentes instalados

Todos os componentes do projeto são renderizados por Kustomize; os charts abaixo são fontes infladas, não releases Helm operacionais.

### Operators

- cert-manager `v1.21.1`;
- CloudNativePG chart `0.29.0`, operator `1.30.0`;
- Barman Cloud Plugin `v0.14.0`;
- CRDs e webhooks Ready.

### Longhorn

- chart oficial `longhorn/longhorn` `1.12.0`;
- namespace `longhorn-system`;
- três Longhorn Nodes Ready e Schedulable;
- CSI driver `driver.longhorn.io` registado;
- `longhorn-postgres`: `Retain`, uma réplica, `strict-local`;
- `longhorn-lab`: `Delete`, uma réplica, `best-effort`;
- `local-path` continua default.

### MinIO lab

- chart `minio/minio` `5.4.0`;
- namespace `minio-lab`;
- modo standalone, update strategy `Recreate`;
- PVC `2Gi` em `longhorn-lab`;
- services ClusterIP 9000/9001;
- bucket privado `postgres-backups` com versioning;
- utilizador Barman dedicado; utilizador default inseguro removido;
- credenciais em Secrets gerados no cluster.

### PostgreSQL

- PostgreSQL `18.3-standard-trixie`;
- namespace `postgres-lab`;
- três instâncias 2/2 Ready em três workers;
- três PVCs `5Gi` em `longhorn-postgres`;
- primary atual gerida pelo operator;
- synchronous replication `ANY 1`, `dataDurability: required`;
- `ObjectStore` Barman e `ScheduledBackup` diário.

## Evidências executadas

- Longhorn write e fsync;
- expansão online de PVC `1Gi → 2Gi`;
- detach/reattach após recriação do Pod;
- persistência do marcador;
- limpeza do PVC/volume temporário;
- MinIO PUT, stat, GET, comparação e DELETE;
- backup completo e `backup.info` no object store;
- PITR para um timestamp entre dois writes;
- failover de Pod primary em 27 segundos com write preservado.

## Nexus

O registry interno da plataforma permaneceu fora do âmbito e não é necessário para esta instalação. Endereços, credenciais e configuração Nexus não são versionados neste repositório público.

## Ainda ausente

- Prometheus/Grafana;
- Loki/Grafana Alloy;
- External Secrets Operator, opcional para produção;
- object storage externo;
- control-plane HA;
- Argo CD, deliberadamente fora do baseline atual.
