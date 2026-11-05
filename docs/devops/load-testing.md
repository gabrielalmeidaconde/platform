# Testes de carga

!!! info "Responsável: Gabriel"

Ferramenta: **[k6](https://k6.io){target="_blank"}** (Grafana Labs), rodando em container — ninguém do
grupo precisa instalar nada além do Docker. Escolhemos o k6 em vez do JMeter/Locust porque o teste é
um arquivo JavaScript versionado no repositório, os limites de aceitação (*thresholds*) ficam no
próprio script e ele envia as métricas direto para o Prometheus, então a carga aparece no mesmo
[dashboard do Grafana](../bottlenecks/observability.md) que as métricas do servidor.

## O que é testado

``` mermaid
flowchart LR
    k6([k6<br/>N usuários virtuais]) ==> lb[lb · Nginx] ==> gw["gateway<br/>(1, 2 ou 4 réplicas)"]
    gw <-->|token| redis[(Redis)]
    gw --> auth & account & exchange
    exchange -->|miss| api([AwesomeAPI])
    k6 -.->|remote write| prom[(Prometheus)] --> graf[Grafana]
```

O `setup()` do script cria 20 contas e faz login uma vez; depois os usuários virtuais (VUs) reaproveitam
os tokens, como usuários reais navegando logados. Cada VU espera 0,5–1,5 s entre as ações.

| Cenário | Requisições | O que exercita |
|---|---|---|
| `auth` | `GET /auth/me` + `GET /accounts/{id}` | validação do token (Redis ou Auth), balanceamento, Account + PostgreSQL |
| `exchange` | `GET /exchange/USD/BRL` (80 %) e `EUR/BRL` | gateway → Exchange → cache da cotação / API externa |
| `login` | `POST /auth/login` | caminho caro: hash da senha + emissão do JWT |
| `mixed` | 80 % leitura autenticada, 15 % câmbio, 5 % login | uso "real" da loja |

| Perfil | Forma da carga | Pergunta que responde |
|---|---|---|
| `smoke` | 1 VU, 20 s | O script e a plataforma funcionam? |
| `load` | sobe em 20 s até `VUS`, mantém por `DURATION`, desce | Aguenta a carga esperada dentro do SLO? |
| `stress` | `VUS` → ×2 → ×4 → ×8, 30 s cada | Onde quebra? Qual componente satura primeiro? |
| `spike` | `VUS/10` → pico de `VUS×4` em 5 s → volta | Aguenta um pico repentino e se recupera? |

**Critérios de aceitação** (os mesmos do [SLO](custos-sla.md#sla-e-slo)), checados pelo k6 — ele sai
com código `99` se algum estourar:

| Métrica | Limite |
|---|---|
| Erros (`http_req_failed`) | < 1 % |
| Latência p95 / p99 (respostas esperadas) | < 500 ms / < 1500 ms |
| `checks` (status e conteúdo das respostas) | > 99 % |

## Como rodar

``` bash
./scripts/build.sh && docker compose up -d --build     # plataforma + Prometheus + Grafana

./scripts/load-test.sh                                  # mixed, perfil load, 50 VUs, 1 min
SCENARIO=auth PROFILE=stress VUS=50 ./scripts/load-test.sh
SCENARIO=exchange PROFILE=spike VUS=20 ./scripts/load-test.sh
BASE_URL=http://<endereço-do-elb> ./scripts/load-test.sh   # contra o EKS

./scripts/load-matrix.sh        # todos os experimentos abaixo (~20 min) -> load/results/RESULTS.md
```

Enquanto roda, abra o Grafana em [http://localhost:3000](http://localhost:3000){target="_blank"}: a
linha **Teste de carga (k6)** mostra VUs, req/s e p95/p99 do cliente, e as linhas de cima mostram o
que acontece em cada réplica, no Redis e no Exchange no mesmo instante.

## Experimentos

O `scripts/load-matrix.sh` muda **uma** variável por vez e mantém o resto igual (cache do Redis
esvaziado antes de cada rodada):

| # | Experimento | Variável | Cenário / perfil | Hipótese |
|---|---|---|---|---|
| 1 | Cache do token | `TOKEN_CACHE_ENABLED` = `false` × `true` | `auth` / `load` | Sem cache, cada requisição chama o Auth: mais carga no Auth e latência maior quando ele satura. Com cache, `gateway_token_cache_total{result="miss"}` fica perto de 20 (um por usuário). |
| 2 | Réplicas do gateway | `GATEWAY_REPLICAS` = 1 × 2 × 4 | `auth` / `stress` | Mais réplicas atrasam o ponto em que o p95 estoura — **até** o gargalo passar para outro componente (Account/PostgreSQL ou a própria CPU da máquina). |
| 3 | Cache da cotação | `EXCHANGE_CACHE_TTL` = `0` × `30` | `exchange` / `load`, 10 VUs, 30 s | Sem cache, a latência do Exchange é a da API externa e aparecem `429`; com cache, ~1 chamada externa a cada 30 s por réplica. Poucos VUs de propósito: não queremos martelar um serviço de terceiros. |
| 4 | Uso real | configuração padrão | `mixed` / `load` | Dentro do SLO. |

## Resultados

!!! warning "A medir"

    Os scripts estão prontos mas a bateria ainda não foi executada. Rodar `./scripts/load-matrix.sh`
    e colar aqui a tabela de `load/results/RESULTS.md`, com prints do Grafana durante os
    experimentos 1 e 2. **Não preencher com números estimados.**

| Execução | Cenário | Perfil | VUs máx. | Requisições | req/s | p50 (ms) | p95 (ms) | p99 (ms) | Erros |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| token-cache-off | auth | load | | | | | | | |
| token-cache-on | auth | load | | | | | | | |
| replicas-1 | auth | stress | | | | | | | |
| replicas-2 | auth | stress | | | | | | | |
| replicas-4 | auth | stress | | | | | | | |
| exchange-cache-off | exchange | load | | | | | | | |
| exchange-cache-on | exchange | load | | | | | | | |
| mixed-load | mixed | load | | | | | | | |

### Como ler

- **Local, tudo na mesma máquina:** k6, Nginx, réplicas do gateway, serviços e banco disputam a mesma
  CPU. Os números mostram **tendências** (com × sem cache, 1 × 4 réplicas), não a capacidade real.
  Mais réplicas na mesma máquina podem até piorar quando a CPU já está no limite — isso é um resultado,
  não um erro. Para capacidade real, rodar com `BASE_URL` apontando para o EKS a partir de outra máquina.
- **Ponto de quebra (stress):** olhar no Grafana em que número de VUs o p95 do k6 passa de 500 ms e qual
  painel satura junto (CPU das réplicas, heap, erros 5xx).
- **Cache do token:** além da latência, comparar `gateway_token_cache_total` — a diferença de chamadas
  ao Auth é o ganho principal (ver a conclusão da página [Cache](../bottlenecks/cache.md)).

## Código

=== "load/store.js"

    ``` { .js .copy linenums="1" }
    --8<-- "load/store.js"
    ```

=== "scripts/load-test.sh"

    ``` { .bash .copy }
    --8<-- "scripts/load-test.sh"
    ```

=== "scripts/load-matrix.sh"

    ``` { .bash .copy }
    --8<-- "scripts/load-matrix.sh"
    ```
