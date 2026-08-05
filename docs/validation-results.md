# Resultados de validação

Data: 5 de agosto de 2026.

Ambiente: k3s-Proxmox, um control-plane e três workers.

## Storage

- três nós Longhorn Ready/Schedulable;
- reserva de 80% em cada filesystem de 50 GiB;
- aproximadamente 9,48 GiB efetivos por worker;
- PVC smoke `1Gi` expandido online para `2Gi`;
- escrita, detach/reattach, leitura e limpeza aprovados.

## PostgreSQL

- CloudNativePG `1.30.0`;
- PostgreSQL `18.3-standard-trixie`;
- três instâncias Ready em três workers;
- `synchronous_standby_names`: `ANY 1`;
- duas réplicas reportadas como `quorum`;
- três PVCs `5Gi` Bound em `longhorn-postgres`.

## Failover

A primary `postgres-ha-1` em `k8s-worker-1` foi eliminada. `postgres-ha-2` em `k8s-worker-3` foi promovida.

- RTO observado até primary Ready: **27 segundos**;
- linha confirmada antes da falha: preservada;
- instância eliminada: reconstruída e regressou Ready;
- estado final: 3/3 Pods Running.

Este resultado comprova perda de Pod, não perda total de worker nem SLA universal.

## Backup

Backup `postgres-ha-manual`:

- target: `prefer-standby`;
- instância: `postgres-ha-2`;
- fase: `completed`;
- início: `2026-08-05T12:26:56Z`;
- fim: `2026-08-05T12:27:14Z`;
- `backup.info` encontrado no MinIO usando apenas credenciais Barman dedicadas.

## PITR

Restore temporário `postgres-ha-restore`, uma instância e PVC `2Gi`:

- target medido: `2026-08-05 12:38:15.727956+00`;
- tempo até o cluster restaurado ficar Ready: **134 segundos**;
- marcador `before`: `1`;
- marcador `after`: `0`;
- resultado: target temporal respeitado;
- cluster, ConfigMap e PVC temporários removidos após o teste.

## MinIO

- Deployment standalone com strategy `Recreate` para PVC RWO;
- bucket `postgres-backups` privado e versionado;
- utilizador default `console/console123` removido;
- utilizador Barman dedicado com policy restrita ao bucket;
- smoke PUT/stat/GET/comparação/DELETE aprovado.

## Não validado ainda

- perda/drain de worker completo;
- falha do disco físico;
- benchmark `fio`/`pgbench` e fsync;
- alertas, dashboards, Loki e Alloy;
- object storage externo e disaster recovery;
- control-plane HA;
- upgrade PostgreSQL/operator sob carga de aplicação.
