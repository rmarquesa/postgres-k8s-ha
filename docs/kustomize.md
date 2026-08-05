# Instalação com Kustomize

## Decisão

Kustomize é a camada única de composição e instalação. Isto não introduz GitOps: não existe Argo CD nem reconciliação contínua nesta fase.

Os charts oficiais continuam a ser usados através de `helmCharts`:

| Camada | Fonte | Versão |
| --- | --- | --- |
| cert-manager | `https://charts.jetstack.io` | `v1.21.1` |
| CloudNativePG | `https://cloudnative-pg.github.io/charts` | chart `0.29.0`, app `1.30.0` |
| Longhorn | `https://charts.longhorn.io` | `1.12.0` |
| MinIO | `https://charts.min.io/` | chart `5.4.0` |
| Barman Cloud Plugin | release manifest upstream | `v0.14.0` |

## Ordem

`install-platform.sh` aplica sequencialmente:

1. cert-manager;
2. CloudNativePG;
3. Barman Cloud Plugin;
4. Longhorn e StorageClasses;
5. MinIO;
6. ObjectStore, Cluster e ScheduledBackup PostgreSQL.

A ordem é necessária porque CRDs e webhooks precisam de estar estabelecidos antes dos custom resources dependentes.

## Comando usado

Cada camada é renderizada e aplicada por `scripts/lib/kustomize.sh`:

```bash
kubectl kustomize <diretório> --enable-helm
kubectl apply --server-side --force-conflicts \
  --field-manager=postgres-k8s-ha -f <render>
```

`--force-conflicts` permite que o projeto seja o field manager declarado e também suporta migração de recursos que tenham sido inicialmente criados por Helm. Não deve ser reutilizado para assumir recursos fora do âmbito deste projeto.

## Namespace MinIO

Nesta combinação Kustomize/chart, `helmCharts.namespace` alimenta `.Release.Namespace`, mas os objetos MinIO gerados não recebem automaticamente `metadata.namespace`. O overlay aplica patches JSON explícitos a ServiceAccount, ConfigMap, Services, PVC e Deployment. `check_render.py` falha se qualquer um voltar a renderizar fora de `minio-lab`.

## Hooks Helm

Kustomize renderiza hooks como recursos normais. Por isso:

- os Jobs `longhorn-pre-upgrade`, `longhorn-post-upgrade` e `longhorn-uninstall` são removidos explicitamente no overlay;
- o hook `minio-post-job` é evitado com `buckets/users/policies: []`;
- bucket, versioning, policy e utilizador Barman são configurados por um Job Kustomize controlado pelo projeto.

Isto evita executar acidentalmente um uninstall hook e evita Jobs imutáveis em reaplicações.

## Secrets

Secrets reais não são renderizados pelo Kustomize nem guardados em ficheiros:

- `install-minio.sh` gera as credenciais root se não existirem;
- `configure-minio-barman.sh` gera um utilizador dedicado e policy mínima;
- o Secret S3 é materializado no namespace PostgreSQL sem imprimir os valores.

Para produção, substituir este fluxo por External Secrets ou outro secret manager compatível.

## Render local

```bash
kubectl kustomize platform/longhorn --enable-helm
kubectl kustomize platform/minio --enable-helm
kubectl kustomize platform/cert-manager --enable-helm
kubectl kustomize platform/cloudnative-pg --enable-helm
kubectl kustomize platform/barman-cloud
kubectl kustomize databases/postgres-ha
```

Os diretórios `charts/` descarregados pelo inflator são cache local e estão ignorados pelo Git.
