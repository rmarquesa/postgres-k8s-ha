# MinIO de laboratório

## Finalidade

O MinIO fornece um endpoint S3-compatible dentro do mesmo cluster apenas para desenvolver e testar:

- Barman Cloud CNPG-I;
- base backups;
- WAL archive;
- restore;
- PITR.

```text
PostgreSQL/CNPG ─▶ Barman plugin ─▶ Service MinIO ─▶ PVC 2 GiB Longhorn
```

Não é um boundary de disaster recovery: uma falha do cluster pode eliminar simultaneamente PostgreSQL e MinIO. Produção deve usar object storage externo e independente.

## Implementação

- chart: `minio/minio` oficial/comunitário de `https://charts.min.io/`;
- chart version: `5.4.0`;
- MinIO: `RELEASE.2024-12-18T13-15-44Z`;
- modo: standalone;
- storage: PVC `2Gi`, StorageClass `longhorn-lab`;
- acesso: apenas `ClusterIP` HTTP;
- bucket privado: `postgres-backups`, com versioning;
- credenciais root: Secret gerado localmente pelo instalador, nunca no Git;
- credenciais Barman: utilizador dedicado com policy restrita ao bucket;
- update strategy: `Recreate`, necessária para Deployment standalone com PVC RWO;
- utilizador upstream default `console/console123`: explicitamente desativado e removido.

O chart comunitário está desatualizado em relação a ofertas MinIO comerciais mais recentes. É aceite aqui porque o componente é efémero, interno e destinado a testes. Deve ser removido ou atualizado se deixar de receber correções compatíveis.

## Instalação

```bash
export KUBECONFIG=/path/to/kubeconfig
export KUBECTL_BIN=kubectl
./scripts/install-minio.sh
```

O script:

1. renderiza o chart oficial através de Kustomize;
2. gera `minio-root-credentials` apenas se o Secret ainda não existir;
3. aplica strategy `Recreate` para evitar deadlock RWO em upgrades;
4. cria bucket/versioning e utilizador Barman dedicado por Job Kustomize;
5. materializa o Secret Barman no namespace PostgreSQL sem imprimir valores;
6. executa o smoke S3.

As credenciais existentes são preservadas em reaplicações e nunca são escritas em ficheiros.

## Endpoint para aplicações no cluster

```text
http://minio.minio-lab.svc.cluster.local:9000
```

O uso de HTTP é deliberado e limitado à rede interna do laboratório. Produção deve usar TLS e object storage externo.

## Teste S3

```bash
./scripts/test-minio.sh
```

O Job usa as credenciais através de `secretKeyRef` e valida:

1. configuração do endpoint;
2. upload de objeto;
3. `stat`;
4. download e comparação;
5. remoção do objeto.

O teste não imprime as credenciais.
