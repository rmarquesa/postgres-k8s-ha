# Arquitetura

## 1. Visão de alto nível

```text
                         aplicações
                              │
                     TLS + NetworkPolicy
                              │
              ┌───────────────┴───────────────┐
              │                               │
         Service RW                      Service RO
       Pooler opcional                 Pooler opcional
              │                               │
              ▼                               ▼
       ┌────────────┐     WAL sync      ┌────────────┐
       │ Primary    │ ───── ANY 1 ─────▶│ Replica 1  │
       │ Worker A   │ ───── ANY 1 ─────▶│ Replica 2  │
       └─────┬──────┘                   └─────┬──────┘
             │                                │
             └──────── CloudNativePG ─────────┘
                              │
                ┌─────────────┴─────────────┐
                │                           │
           PVC Longhorn              Barman CNPG-I
       disco virtual do worker       ├─ base backup
                │                    └─ WAL contínuo
                ▼                          │
       Proxmox local-lvm/NVMe               ▼
                                  MinIO interno no lab
                                  S3 externo em produção
```

O PostgreSQL fornece replicação física de instância para instância. O Longhorn fornece volumes e lifecycle CSI. No laboratório, MinIO partilha o cluster e não é um boundary de disaster recovery; object storage externo é obrigatório para essa garantia em produção.

## 2. Failure domains

Cada instância deve executar num worker diferente. O control-plane não receberá PostgreSQL por defeito.

```text
Worker 1                 Worker 2                 Worker 3
┌─────────────┐          ┌─────────────┐          ┌─────────────┐
│ PG primary  │          │ PG replica  │          │ PG replica  │
│ Longhorn    │          │ Longhorn    │          │ Longhorn    │
│ NVMe path   │          │ NVMe path   │          │ NVMe path   │
└─────────────┘          └─────────────┘          └─────────────┘
```

Anti-affinity evita colocação voluntária no mesmo hostname. Topology spread mantém distribuição equilibrada. Nenhuma regra de scheduling corrige uma infraestrutura onde os três workers dependem do mesmo disco, alimentação ou host físico; esses failure domains devem ser documentados no Proxmox.

## 3. Escrita e replicação

```text
Cliente        Primary        Replica A       Replica B
   │              │               │               │
   │ COMMIT       │               │               │
   ├─────────────▶│ WAL + fsync    │               │
   │              ├──────────────▶│               │
   │              ├──────────────────────────────▶│
   │              │ aguarda ACK de ANY 1          │
   │              │◀──────────────┤               │
   │ COMMIT OK    │               │               │
   │◀─────────────┤               │               │
```

`ANY 1` evita exigir simultaneamente as duas réplicas. Em `required`, a ausência de uma réplica elegível impede confirmar novos commits. Em `preferred`, o operator pode preservar disponibilidade aceitando degradação temporária.

## 4. Failover

```text
Primary deixa de responder
          │
          ▼
CloudNativePG verifica saúde e estado das réplicas
          │
          ▼
Seleciona candidata com WAL mais avançado e elegível
          │
          ▼
Promove réplica
          │
          ├─ atualiza Service RW
          ├─ reconcilia topologia
          └─ substitui/reintegra instância falhada
          │
          ▼
Cliente reconecta e repete operação idempotente
```

Failover pode interromper ligações e transações. Aplicações precisam de timeout, reconnect e retry limitado. PgBouncer reduz churn, mas não preserva transações interrompidas.

## 5. Storage Longhorn

### Perfil PostgreSQL local

```text
PG instance ── PVC ── Longhorn engine ── 1 replica local ── NVMe
```

O PostgreSQL mantém três cópias dos dados, por isso o perfil base evita nova tripla replicação no storage.

### Perfil replicated

```text
PG instance ── PVC ── Longhorn engine ── replica local
                                      └─ replica remota
```

Oferece sobrevivência do PVC à perda de um disco/nó, ao custo de rede, espaço e latência. Só será recomendado após benchmark.

### Quando não usar Longhorn

- storage CSI externo já oferece durabilidade e desempenho melhores;
- workload exige latência previsível que a replicação em rede não consegue cumprir;
- workers não possuem discos dedicados ou failure domains reais;
- equipa não consegue operar rebuilds, snapshots, engine upgrades e capacity pressure;
- um serviço PostgreSQL gerido reduz significativamente o risco operacional.

## 6. Backup e WAL

```text
                   ┌─ base backup diário ──────────┐
PostgreSQL/Barman ─┤                               ├─▶ bucket/prefix do cluster
                   └─ segmentos WAL contínuos ─────┘
```

Base backup é uma cópia física consistente usada como ponto de partida. WAL contém alterações posteriores. PITR escolhe um base backup anterior e reproduz WAL até ao target.

Retenção de sete dias define a janela desejada, mas deve ser validada no backend. Lifecycle do bucket não pode apagar WAL ainda necessário para backups recuperáveis.

## 7. PITR

```text
segunda 02:00  base backup
      │
      ├──────── WAL ──────── terça 14:32:15 target
      │                              │
      └──────── WAL ──────── terça 15:00 DELETE acidental
                                     X não reproduzir

ObjectStore ─▶ novo Cluster recovery ─▶ validação ─▶ cutover explícito
```

A recuperação cria um cluster novo. O cluster original não é editado ou sobrescrito durante o teste.

## 8. Indisponibilidade do S3

```text
S3 indisponível
      │
      ├─ PostgreSQL continua enquanto storage/WAL permitir
      ├─ archiving acumula/retenta
      ├─ alerta dispara
      └─ janela PITR deixa de avançar
                 │
          disco pode encher
                 │
          risco de indisponibilidade
```

O object storage não participa no caminho síncrono do commit, mas uma falha prolongada transforma-se em risco de capacidade e recuperação.

## 9. Entrega atual e evolução GitOps

```text
repositório local/GitHub
  ├─ kustomizations
  ├─ charts oficiais fixados via helmCharts
  ├─ manifests Kubernetes
  └─ scripts idempotentes
            │
            ▼
       cluster k3s
```

A fase atual usa Kustomize e server-side apply porque existe apenas uma base e um ambiente de teste. Argo CD será considerado quando múltiplas bases/ambientes ou reconciliação contínua justificarem outro controller.

## 10. Secrets

```text
gerador local ──▶ Kubernetes Secret ──▶ CNPG / ObjectStore
                         │
                         └─ nunca versionado
```

O perfil production usa Sealed Secrets `strict` por cluster. External Secrets/Vault permanece alternativa quando rotação dinâmica ou integração direta com um cofre externo for requisito. Nenhum destes fluxos altera os Secrets e certificados geridos pelo CloudNativePG.

## 11. Observabilidade

- CloudNativePG metrics via PodMonitor;
- kube-state-metrics e node exporter;
- Longhorn metrics;
- PostgreSQL: disponibilidade, connections, locks, checkpoints, WAL, replication lag;
- backups: último sucesso, idade, duração e falhas;
- storage: espaço, volume degraded/faulted e rebuild;
- logs: Grafana Alloy para Loki;
- dashboards com links para runbooks e eventos de deploy.

Alertas devem representar sintomas acionáveis. CPU alta isolada será contexto, não necessariamente page.

## 12. Segurança

- TLS em trânsito;
- RBAC mínimo;
- aplicação sem superuser;
- NetworkPolicies default-deny com egress explícito para DNS, S3 e monitoring;
- security contexts geridos/suportados pelo operator;
- Pod Security Standards no namespace;
- secrets externos;
- encriptação do object storage e, quando suportado/testado, dos volumes;
- imagens oficiais fixadas por versão e verificadas;
- backups sem credenciais incorporadas.

## 13. Limites conhecidos

- três workers não oferecem capacidade de sobra ilimitada durante manutenção;
- o cluster possui apenas um control-plane, logo o plano de controlo não é altamente disponível;
- Longhorn ainda não está instalado e o NVMe não foi validado como path dedicado;
- Nexus usa HTTP no endpoint observado;
- S3 backend ainda não foi escolhido;
- os SLOs dependem de benchmarks e testes reais;
- HA do PostgreSQL não substitui backup nem HA do control-plane Kubernetes.
