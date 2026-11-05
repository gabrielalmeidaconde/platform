# PaaS, custos e SLA

!!! info "Responsável: Gabriel"

!!! note "Preços conferidos em 05/11/2026"

    Valores **on-demand em `us-east-1`, em USD** (mês = 730 h), usados para comparar ordens de grandeza.
    Conferidos em 05/11/2026 contra as páginas de preço do
    [EKS](https://aws.amazon.com/eks/pricing/){target="_blank"},
    [Fargate](https://aws.amazon.com/fargate/pricing/){target="_blank"} e
    [Classic Load Balancer](https://aws.amazon.com/elasticloadbalancing/classicloadbalancer/pricing){target="_blank"}
    e com calculadoras de terceiros para o EC2 (`t3.medium` US$ 0,0416/h) e o IPv4 público
    (US$ 0,005/h). Preços mudam: para um orçamento real, usar a
    [AWS Pricing Calculator](https://calculator.aws/){target="_blank"}. Impostos e câmbio para BRL não
    estão incluídos.

## O que precisa rodar

O que a plataforma pede de recursos, somando os `requests` dos manifestos do EKS:

| Componente | Réplicas | CPU (request) | Memória (request) |
|---|---:|---:|---:|
| `lb` (Nginx) | 2 | 2 × 50m | 2 × 32 Mi |
| `gateway` | 2 | 2 × 250m | 2 × 384 Mi |
| `auth`, `account` (Spring Boot) | 1 + 1 | 2 × 250m | 2 × 384 Mi |
| `exchange` | 2 | 2 × 100m | 2 × 96 Mi |
| `redis` | 1 | 100m | 128 Mi |
| `prometheus` + `grafana` | 1 + 1 | 200m | 384 Mi |
| **Total** | | **≈ 1,6 vCPU** | **≈ 2,3 GiB** |

Valores de `auth`/`account` estimados iguais aos do gateway até os manifestos do Nicolas existirem.
Cabe em **2 nós `t3.medium`** (2 vCPU, 4 GiB cada) com folga para o sistema e para o pico — e 2 nós
em zonas diferentes é o mínimo para não ter um ponto único de falha.

## Custo no EKS (o que entregamos)

| Item | Cálculo | USD/mês |
|---|---|---:|
| Control plane do EKS | US$ 0,10/h | 73,00 |
| 2 nós EC2 `t3.medium` | 2 × US$ 0,0416/h | 60,74 |
| Disco dos nós (EBS gp3, 20 GB cada) | 2 × 20 GB × US$ 0,08 | 3,20 |
| Balanceador (Service `LoadBalancer` → Classic LB) | US$ 0,025/h + US$ 0,008/GB | ≈ 18,50 |
| IPv4 públicos (2 nós + balanceador) | ≈ 4 × US$ 0,005/h | ≈ 14,60 |
| ECR (5 imagens multi-arch, ≈ 2 GB) | US$ 0,10/GB | 0,20 |
| PostgreSQL no RDS `db.t4g.micro` single-AZ + 20 GB | US$ 0,016/h + 20 × US$ 0,115 | ≈ 14,00 |
| Saída de dados | primeiros 100 GB/mês gratuitos | 0,00 |
| **Total** | | **≈ 184** |

!!! danger "Versão do Kubernetes: armadilha de 6×"

    Os US$ 0,10/h do control plane valem só enquanto a versão do Kubernetes do cluster está no
    **suporte padrão** (≈ 14 meses após o lançamento da versão no EKS). Depois disso o cluster entra
    sozinho no **suporte estendido**: **US$ 0,60/h ≈ US$ 438/mês**, só de control plane. Criar o cluster
    na versão mais recente disponível e não deixar um cluster esquecido ligado.

Se os nós ficarem em sub-redes privadas, soma um **NAT Gateway** (US$ 0,045/h + US$ 0,045/GB ≈
US$ 33+/mês) — é o item "escondido" mais caro em projetos pequenos. Para o projeto, nós em sub-rede
pública com *security group* fechado (só o balanceador aceita tráfego de fora) evitam esse custo.

### Para o projeto (AWS Academy / créditos)

O que custa é o **tempo ligado**: ≈ US$ 0,25 por hora com tudo no ar. Um dia de testes e gravação
(8 h) sai por ≈ US$ 2. Regras do grupo:

- subir o cluster só para testar/apresentar e **apagar no fim** (`eksctl delete cluster` ou destruir pelo
  console): o control plane cobra mesmo sem nenhum pod;
- alerta de *billing* na conta (página [AWS](aws.md));
- RDS e balanceador também cobram parados: apagar junto.

### Como baixar o custo em produção

| Medida | Economia | Observação |
|---|---|---|
| Nós **Graviton** (`t4g.medium`, ARM) | ≈ 20 % nos nós | Nossas imagens já são multi-arch (amd64 + arm64) pelo [pipeline](ci-cd.md). |
| Nós **Spot** | até ≈ 70 % nos nós | Os serviços são *stateless* com 2 réplicas; aguentam perder um nó. Não usar para o banco. |
| *Savings Plan* de 1 ano | ≈ 30–40 % em EC2/Fargate | Só quando a carga for estável. |
| Escalar por métrica (HPA) | paga o pico só no pico | Usa as métricas do [Prometheus](../bottlenecks/observability.md). |

## PaaS: e se não usássemos Kubernetes?

Os mesmos containers podem rodar numa **PaaS**, em que o provedor cuida de servidores, balanceamento e
escala. Comparação para a mesma plataforma (6 containers pequenos + PostgreSQL + Redis):

| Opção | Tipo | Estimativa USD/mês | Prós | Contras |
|---|---|---:|---|---|
| **EKS** (atual) | Kubernetes gerenciado | ≈ 184 | Controle total (rede, Nginx, Prometheus, sidecars), portável, é o que o curso pede | US$ 73 só de control plane; mais coisas para operar (nós, upgrades, RBAC) |
| **ECS Fargate** + ALB | CaaS (containers sem servidor) | ≈ 105 | Sem nós nem control plane pago; paga por vCPU/GB do container | Amarrado à AWS; Prometheus precisa de outra solução (AMP ou CloudWatch) |
| **AWS App Runner** | PaaS | ≈ 120 | `git push`/imagem → URL com HTTPS e escala automática | Sem rede interna fácil entre serviços: o "gateway como único ponto de entrada" fica mais difícil |
| **Render** / **Railway** | PaaS | ≈ 60–150 | Mais simples de todos, banco e Redis gerenciados com 1 clique | Planos baratos têm 512 MB (pouco para JVM); menos controle de rede e de região (latência para o Brasil) |
| **Heroku** | PaaS | ≈ 100–180 | Maduro, bom para protótipo | Caro por recurso; dyno básico dorme |

Como chegamos no Fargate: 6 tarefas × (0,25 vCPU + 0,5 GB) = 1,5 vCPU × US$ 0,04048/h + 3 GB ×
US$ 0,004445/h ≈ US$ 54 + ALB ≈ US$ 22 + ElastiCache `cache.t4g.micro` ≈ US$ 12 + RDS ≈ US$ 14.

**Conclusão:** para **esta** plataforma (pequena, 3 desenvolvedores, carga baixa), uma PaaS ou o
Fargate sairia **mais barato e com menos operação** que o EKS — a maior parte do custo do EKS é fixa
(control plane + nós sempre ligados). O EKS passa a compensar quando há **muitos serviços** dividindo
os mesmos nós, quando se precisa de recursos do Kubernetes (HPA por métrica própria, *service mesh*,
operadores, portabilidade entre nuvens) ou quando a equipe já tem a operação do cluster resolvida.
Escolhemos o EKS por ser o objetivo do curso e por manter o mesmo desenho (Nginx → gateway → serviços,
Redis compartilhado, Prometheus) do ambiente local.

## SLA e SLO

**SLA** é o compromisso contratual do provedor (com crédito se não cumprir); **SLO** é a meta interna que
definimos para a nossa plataforma; **SLI** é a medida que mostra se cumprimos.

### SLA dos serviços da AWS que usamos

| Serviço | SLA mensal |
|---|---:|
| EKS (control plane) | 99,95 % |
| EC2 — região (instâncias em ≥ 2 zonas) | 99,99 % |
| EC2 — instância individual | 99,5 % |
| Elastic Load Balancing | 99,99 % |
| RDS single-AZ / Multi-AZ | 99,5 % / 99,95 % |
| API de câmbio (AwesomeAPI) | **nenhum** (serviço gratuito) |

### Disponibilidade composta

Uma requisição autenticada passa **em série** por balanceador → Nginx → gateway → Auth/Account → banco;
a disponibilidade do caminho é o **produto** das disponibilidades. Componentes com **réplicas em zonas
diferentes** ficam em paralelo: `1 − (1 − 0,995)² = 99,9975 %`.

| Cenário | Conta | Disponibilidade | Indisponível/mês |
|---|---|---:|---:|
| Como está (2 réplicas em 2 zonas, RDS single-AZ) | 0,9995 (EKS) × 0,9999 (ELB) × 0,99998 (nós) × 0,995 (RDS) | ≈ **99,44 %** | ≈ 4 h |
| Com RDS Multi-AZ | … × 0,9995 | ≈ **99,89 %** | ≈ 48 min |
| Tudo com 1 réplica, 1 nó | 0,9995 × 0,9999 × 0,995 × 0,995 | ≈ 98,95 % | ≈ 7,7 h |

O **banco single-AZ** é o elo mais fraco: as réplicas do gateway e do Exchange não adiantam se o
PostgreSQL cai. Rotas que não dependem do banco (câmbio com token já em cache no Redis) continuam no ar.
O Exchange depende de uma API **sem SLA**; o cache com *stale-if-error* ([Cache da cotação](../bottlenecks/exchange-cache.md))
segura até 10 min de queda dela.

### Nosso SLO

| SLI | SLO (janela de 30 dias) | Como medir (Prometheus) |
|---|---|---|
| Disponibilidade: % de requisições sem erro 5xx no gateway | **99,5 %** (≈ 3 h 39 min de orçamento de erro/mês) | `1 - sum(rate(http_server_requests_seconds_count{application="gateway",status=~"5.."}[30d])) / sum(rate(http_server_requests_seconds_count{application="gateway"}[30d]))` |
| Latência: p95 das requisições | **< 500 ms** | k6 no [teste de carga](load-testing.md); no servidor, p95 do Exchange pelo histograma |
| Erros sob a carga esperada | **< 1 %** | `http_req_failed` do k6 |

Por que 99,5 % e não 99,9 %: com o banco single-AZ a própria AWS só garante ≈ 99,4 % no caminho
completo; prometer mais que isso seria prometer o que a infraestrutura não sustenta. Para subir para
**99,9 %** o primeiro passo é o RDS Multi-AZ (+ ≈ US$ 14/mês), depois alerta no Grafana quando a taxa
de 5xx consumir o orçamento de erro mais rápido que o normal.

| SLO | Indisponibilidade permitida por mês |
|---:|---:|
| 99 % | 7 h 18 min |
| 99,5 % | 3 h 39 min |
| 99,9 % | 43 min 49 s |
| 99,95 % | 21 min 54 s |
| 99,99 % | 4 min 23 s |
