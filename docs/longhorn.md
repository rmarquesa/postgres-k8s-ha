# Longhorn no laboratório k3s

## Âmbito

O Longhorn é instalado pelo chart oficial `longhorn/longhorn`, fixado em `1.12.0`. Esta instalação usa até aproximadamente 10 GiB de cada disco de sistema dos três workers. Não foram adicionados discos às VMs.

```text
worker root disk ~50 GiB
├── sistema operativo e k3s
└── /var/lib/longhorn
    ├── 80% do filesystem reservado
    └── ~10 GiB máximo anunciado ao Longhorn
```

Esta disposição é aceitável para laboratório, não para produção. Em produção, use discos dedicados, failure domains reais, monitorização de latência e capacidade, e dimensionamento medido.

## Pré-requisitos

Cada worker Ubuntu necessita de:

- `open-iscsi`;
- serviço `iscsid` ativo e enabled;
- `nfs-common` para RWX e operações que dependem de NFS;
- `dmsetup` e `cryptsetup` para funcionalidades de volumes;
- mount propagation suportada pelo kubelet;
- espaço livre suficiente em `/var/lib/longhorn`.

O control-plane não recebe disco Longhorn. O instalador etiqueta apenas nós sem o label `node-role.kubernetes.io/control-plane`.

## Instalação

```bash
export KUBECONFIG=/path/to/kubeconfig
export KUBECTL_BIN=kubectl
./scripts/install-longhorn.sh
```

O script:

1. valida acesso ao cluster;
2. etiqueta os workers com `node.longhorn.io/create-default-disk=true`;
3. renderiza o chart oficial `longhorn/longhorn` `1.12.0` através de Kustomize;
4. remove hooks Helm que seriam inseguros como recursos normais;
5. aplica chart e StorageClasses com server-side apply;
6. aguarda managers/CSI e valida os Longhorn Nodes.

## Values explicados

| Campo | Valor | Motivo |
| --- | --- | --- |
| `persistence.defaultClass` | `false` | não altera implicitamente a StorageClass default do cluster |
| `persistence.reclaimPolicy` | `Retain` | reduz risco de eliminação acidental para volumes não efémeros |
| `createDefaultDiskLabeledNodes` | `true` | impede o master ou nós futuros de receberem storage automaticamente |
| `defaultDataPath` | `/var/lib/longhorn` | path convencional do data engine V1 |
| `defaultReplicaCount` | `1` | evita replicação dupla com CloudNativePG |
| `storageOverProvisioningPercentage` | `100` | sem thin overcommit no laboratório pequeno |
| `storageMinimalAvailablePercentage` | `10` | torna o disco unschedulable antes de esgotar o filesystem |
| `storageReservedPercentageForDefaultDisk` | `80` | limita Longhorn a cerca de 10 GiB do disco de 50 GiB |
| `upgradeChecker` | `false` | evita chamadas externas não necessárias |

## StorageClasses

### `longhorn-postgres`

- uma réplica;
- `strict-local` para colocar a réplica junto da instância PostgreSQL;
- `Retain` para proteção contra eliminação acidental;
- expansão online permitida;
- `WaitForFirstConsumer` para a decisão de topology ocorrer com o Pod conhecido.

### `longhorn-lab`

- uma réplica;
- `best-effort` locality;
- `Delete`, porque serve componentes descartáveis como o MinIO de testes;
- não é default.

## Capacidade

Com uma reserva percentual, o limite acompanha o tamanho real do filesystem. Num filesystem de 50,88 GB, 80% reservados deixam aproximadamente 10,18 GB decimais, ou 9,48 GiB.

Não se deve preencher essa capacidade: PostgreSQL usa 5 GiB por instância e MinIO usa 2 GiB, ficando margem para snapshots e variação de scheduling. Longhorn snapshots não substituem backups Barman no MinIO/S3.

## Quando não usar esta configuração

- dados de produção;
- disco raiz com pressão ou pouca previsibilidade;
- requisito de sobrevivência do mesmo PVC à perda do worker;
- necessidade de mais de uma réplica de storage;
- workloads cujo total reservado exceda cerca de 10 GiB por nó.
