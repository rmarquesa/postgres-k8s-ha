# Contrato de implementação

Este contrato define quando a plataforma pode ser considerada pronta. A existência de YAML não satisfaz o objetivo.

## Perfis

### Lab

- três instâncias PostgreSQL;
- `5Gi` por instância, configurável;
- recursos mínimos definidos após medição;
- synchronous replication `ANY 1`;
- `dataDurability: required`;
- uma réplica Longhorn por PVC;
- MinIO standalone interno com PVC `2Gi` para testes S3;
- credenciais criadas localmente e não versionadas.

### Production reference

- parâmetros de capacidade obrigatórios;
- `dataDurability: required`;
- anti-affinity por hostname e topology spread por failure domain;
- Sealed Secrets `strict` por cluster, com sealing keys protegidas externamente;
- TLS, NetworkPolicies, Pod Security e RBAC;
- alertas, dashboards, runbooks e restore periódico;
- sem valores de CPU, RAM, IOPS ou RTO apresentados como universais.

## SLOs iniciais

| Indicador | Objetivo inicial | Como provar |
| --- | --- | --- |
| RPO em failover simples | 0 para commits confirmados em modo `required` | sequência monotónica antes/depois do failover |
| RTO de failover | < 60 s | medir último write confirmado até primeiro write após promoção |
| RPO via object storage | < 5 min | comparar último WAL recuperável com timestamp de origem |
| PITR do lab | < 30 min | teste completo num novo cluster |
| Backup | base backup diário | estado CNPG + objetos S3 + restore |
| Retenção | 7 dias | policy Barman e inspeção de backups recuperáveis |

São objetivos para o ambiente de validação, não garantias para qualquer hardware.

## Gates por fase

### Gate 0 — pré-requisitos

- cliente `kubectl` compatível;
- kubeconfig e contexto confirmados;
- três workers Ready;
- discos/path NVMe identificados;
- requisitos Longhorn verificados;
- endpoint S3 e secret flow escolhidos.

### Gate 1 — storage

- Longhorn saudável nos três workers;
- StorageClasses renderizadas e explicadas;
- expansão validada;
- perda controlada de réplica/volume testada;
- benchmark de latência, throughput e fsync guardado como artefacto.

### Gate 2 — operators e Kustomize

- charts oficiais fixados e inflados por Kustomize;
- CloudNativePG e Barman plugin disponíveis;
- CRDs estabelecidas antes dos custom resources;
- values, kustomizations e manifests guardados no projeto;
- hooks Helm perigosos removidos dos renders;
- nenhum secret em texto simples no Git.

### Gate 3 — PostgreSQL

- três instâncias em três workers;
- serviços RW/RO funcionais;
- synchronous replication observada no PostgreSQL;
- slots e WAL verificados;
- failover de primary e reconstrução de réplica medidos.

### Gate 4 — backup/PITR

- base backup concluído;
- WAL arquivado continuamente;
- DELETE controlado executado;
- novo cluster recuperado para timestamp anterior;
- dados antes/depois comparados;
- recovery não sobrescreve o cluster de origem.

### Gate 5 — operação

- alertas exercitados;
- dashboards carregados;
- logs consultáveis em Loki;
- runbooks executáveis;
- upgrades e expansão documentados;
- teste de drain e perda de worker concluído.

## Testes destrutivos

Qualquer teste que elimine pods, volumes ou nós deve exigir simultaneamente:

- contexto permitido;
- namespace de teste;
- identificação explícita do alvo;
- `ALLOW_DESTRUCTIVE_TESTS=true`;
- pré-check de backup e saúde;
- recolha de evidências antes e depois.

O cluster de origem nunca será destruído para testar PITR; recovery cria um cluster novo.

## Definition of Done

A plataforma só está concluída quando:

1. todos os manifests renderizam e validam;
2. os scripts Kustomize são idempotentes e o estado observado coincide com os ficheiros do projeto;
3. failover, backup, restore e PITR foram executados realmente;
4. RPO/RTO medidos estão registados;
5. secrets não aparecem no histórico Git;
6. alertas têm owner, severidade e runbook;
7. limitações e dependências ambientais estão documentadas;
8. um segundo operador consegue seguir os runbooks sem conhecimento implícito.
