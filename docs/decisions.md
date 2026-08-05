# Registo de decisões arquiteturais

Este documento regista as decisões ainda antes da implementação. Cada decisão poderá ser separada num ADR individual quando gerar manifests ou procedimentos próprios.

## D-001 — CloudNativePG

**Decisão:** usar CloudNativePG para gerir PostgreSQL.

**Porquê:** fornece lifecycle declarativo, failover, switchover, services, certificados, replicação, backup por plugin e integração Prometheus sem manter scripts próprios de eleição.

**Alternativas:** Patroni manual, Zalando Postgres Operator, Crunchy PGO ou PostgreSQL fora de Kubernetes.

**Não recomendado quando:** a equipa não consegue operar Kubernetes/storage com a maturidade exigida, ou quando um serviço gerido oferece RTO/RPO e custo operacional melhores.

## D-002 — Três instâncias e quorum síncrono

**Decisão:** um primary e duas réplicas; commits síncronos aguardam `ANY 1` réplica elegível.

**Vantagem:** uma réplica pode falhar sem perder a capacidade de confirmar writes.

**Custo:** cada commit depende de rede, CPU e fsync de pelo menos uma réplica. Latência e jitter dos workers tornam-se latência da aplicação.

**Limite:** três instâncias toleram uma falha de instância para HA normal; não significam tolerância automática a qualquer combinação de duas falhas.

## D-003 — Durabilidade required

**Decisão:** usar `dataDurability: required` no laboratório e na referência de produção enquanto o objetivo for RPO local zero para commits confirmados.

- `required`: bloqueia commits quando não existe réplica síncrona; protege a garantia de durabilidade.
- `preferred`: alternativa operacional documentada que degrada temporariamente para assíncrono e pode aumentar o RPO.

A alteração em incidente deve ser explícita, auditada e coberta por runbook. Não será automatizada por um script opaco.

## D-004 — Longhorn sem tripla replicação para cada instância

**Decisão:** uma réplica Longhorn `strict-local` por volume PostgreSQL no perfil principal de laboratório; disponibilizar perfil opcional com duas réplicas `best-effort`.

**Porquê:** CloudNativePG já mantém três cópias PostgreSQL. Três réplicas Longhorn para cada uma criariam até nove cópias locais e amplificação de escrita/rede.

**Vantagem:** menor latência e uso de disco.

**Desvantagem:** se o disco de uma instância falhar, essa instância será reconstruída a partir de outra instância ou backup em vez de o volume sobreviver sozinho.

**Quando usar duas/três réplicas Longhorn:** workload sem replicação própria, requisito de recuperação do mesmo PVC, ou benchmarks que demonstrem capacidade suficiente e um benefício operacional concreto.

## D-005 — Backup pelo Barman Cloud CNPG-I

**Decisão:** usar o plugin atual, `ObjectStore`, base backup diário e WAL archive contínuo.

**Porquê:** separa o lifecycle do backup do core do operator e suporta restore completo/PITR em S3-compatible.

**Não fazer:** tratar snapshots Longhorn como substituto de backup externo ou considerar um backup válido sem restore testado.

## D-006 — S3-compatible sem acoplamento a fornecedor

**Decisão:** parametrizar endpoint, bucket, region, path e opções TLS; não incluir credenciais nem extensões específicas de um fornecedor no chart base.

A compatibilidade só será declarada para backends realmente testados. “S3-compatible” não garante comportamento idêntico em multipart upload, object lock, lifecycle, TLS ou consistency.

## D-007 — Secrets por fase

**Decisão:** o laboratório gera Kubernetes Secrets localmente e nunca os persiste no Git. O perfil de produção usa Sealed Secrets com scope `strict` para credenciais fornecidas pelo operador, começando pelo acesso S3.

Cada cluster sela valores diferentes com o certificado público do seu próprio controller. As chaves privadas do controller ficam fora do Git, com backup cifrado, controlo de acesso e restore drill. Secrets e certificados geridos pelo CloudNativePG permanecem sob o lifecycle do operator.

**Porquê:** mantém o laboratório simples e permite desired state cifrado em produção sem tornar ciphertext reutilizável entre clusters.

## D-008 — Kustomize sem GitOps

**Decisão:** usar Kustomize como camada única de composição e instalação. Charts oficiais entram por `helmCharts`; manifests próprios entram por `resources` e patches. Não instalar Argo CD nesta fase.

**Porquê:** centraliza render, ordem e ownership sem adicionar um controller de reconciliação. Os perfis lab e production continuam explícitos em Kustomize. GitOps será reavaliado quando houver múltiplos clusters operados continuamente ou equipas responsáveis pela reconciliação.

## D-009 — Pooler opcional

**Decisão:** criar suporte a CloudNativePG `Pooler`, desativado por defeito.

Ativar quando connection churn, serverless ou orçamento de conexões justificarem PgBouncer. A aplicação deve provar compatibilidade com transaction pooling.

## D-010 — Grafana Alloy em vez de Promtail

**Decisão:** Loki + Grafana Alloy. Promtail não será usado porque terminou suporte em março de 2026.

## D-011 — Upgrade com indisponibilidade mínima, não zero absoluto

**Decisão:** rolling update/switchover, clientes com retry e reconnect, e medição da interrupção.

Ligações e transações em curso podem ser interrompidas durante mudança de primary. “Sem downtime” não será usado como garantia absoluta.

## D-012 — Ownership local do projeto

**Decisão:** este repositório é o owner das configurações Longhorn, MinIO e PostgreSQL usadas no laboratório. Nexus e o cluster k3s continuam pertencentes à plataforma Proxmox.

Não existe Argo CD nesta fase. Instalações são executadas por scripts idempotentes que renderizam Kustomize, incluindo charts oficiais com versões fixadas, e aplicam server-side com field manager próprio.

## D-013 — MinIO interno apenas para testes

**Decisão:** instalar MinIO standalone no cluster, com PVC `2Gi`, HTTP ClusterIP e bucket privado versionado.

**Limite:** MinIO partilha o failure domain do PostgreSQL e não é backup de desastre. Produção exige object storage externo.

## D-014 — Capacidade Longhorn limitada no disco do sistema

**Decisão:** não adicionar discos às VMs. Reservar 80% do filesystem de 50 GiB e permitir cerca de 10 GiB ao Longhorn em cada worker.

**Limite:** configuração exclusivamente de laboratório; PostgreSQL usa `5Gi` por instância e deve manter margem para snapshots e MinIO.
