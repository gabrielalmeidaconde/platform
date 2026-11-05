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
THINK=0 SCENARIO=auth PROFILE=stress VUS=25 ./scripts/load-test.sh   # sem pausa: limite de vazão
BASE_URL=http://<endereço-do-elb> ./scripts/load-test.sh   # contra o EKS

./scripts/load-matrix.sh        # todos os experimentos abaixo (~25 min) -> load/results/RESULTS.md
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
| 5 | Saturação | `GATEWAY_REPLICAS` = 1 × 4, **`THINK=0`** (sem pausa) | `auth` / `stress` até 200 VUs | Com pausa, o experimento 2 não chega ao limite; sem pausa, cada VU dispara o mais rápido possível e mostra o que quebra primeiro. |

## Resultados

Medidos em **05/11/2026** com `./scripts/load-matrix.sh` (os experimentos 3 e 5 foram rodados de novo
com `ONLY="3 5"`). Máquina: Windows 11 + Docker Desktop (WSL2), 12 CPUs lógicas, 7,3 GiB de RAM para
o Docker. **k6, Nginx, gateway, serviços, banco, Prometheus e Grafana na mesma máquina.** Latências
só das respostas esperadas e só da fase de teste (o cadastro/login do `setup()` fica de fora).

| Execução | Cenário | Perfil | VUs máx. | Requisições | req/s | p50 (ms) | p95 (ms) | p99 (ms) | Erros |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| token-cache-off | auth | load | 50 | 7.416 | 80,8 | 5 | 12 | 20 | 0,00 % |
| token-cache-on | auth | load | 50 | 7.448 | 79,7 | 4 | **7** | 15 | 0,00 % |
| replicas-1 | auth | stress | 400 | 41.110 | 290,9 | 2 | 3 | 4 | 0,00 % |
| replicas-2 | auth | stress | 400 | 40.810 | 287,1 | 2 | 17 | 114 | 0,00 % |
| replicas-4 | auth | stress | 400 | 40.918 | 285,8 | 3 | 7 | 23 | 0,00 % |
| exchange-cache-off | exchange | load | 10 | 445 | 7,3 | 23 | 49 | 69 | 0,00 % |
| exchange-cache-on | exchange | load | 10 | 454 | 7,5 | 3 | **4** | 17 | 0,00 % |
| mixed-load | mixed | load | 50 | 6.605 | 72,1 | 4 | 62 | 197 | 0,00 % |
| saturation-1 | auth | stress, `THINK=0` | 200 | 578.564 | **4.120** | 13 | 43 | 69 | **0,57 %** |
| saturation-4 | auth | stress, `THINK=0` | 200 | 387.296 | 2.697 | 14 | 88 | 166 | **0,00 %** |

**Todos os cenários com pausa (1–4) ficaram dentro do SLO** (erros < 1 %, p95 < 500 ms, p99 < 1,5 s).

### O que os números mostram

**1. Cache do token (Redis) — o Auth sai do caminho.** Com o cache ligado, o Prometheus registrou
**7.571 hits e 21 misses** em `gateway_token_cache_total` durante a rodada: 99,7 % das validações não
chamaram o Auth (os 21 misses são ≈ 1 por usuário do teste). Sem cache, todas as ≈ 7.400 requisições
passaram pelo `POST /auth/solve`. A latência caiu de p95 12 → **7 ms** (−42 %). A vazão é a mesma nas
duas rodadas porque quem dita o ritmo é a pausa dos usuários, não o servidor.

**2. Cache da cotação — a API externa sai do caminho.** Sem cache, toda cotação ia até a AwesomeAPI:
p50 de 23 ms e p95 de 49 ms, a latência de um serviço de terceiros. Com o cache de 30 s, p50 de **3 ms** e
p95 de **4 ms** (−92 %). Em 10 usuários a API externa aguentou sem `429`, mas o volume de chamadas a ela
cai de ≈ 7 por segundo para 1 a cada 30 s por réplica — é isso que protege do limite de requisições.

**3. Réplicas com carga "realista" — um gateway sobra.** Com a pausa entre ações, 400 usuários geram
≈ 290 req/s, e uma réplica só responde com p95 de 3 ms. As diferenças entre 1, 2 e 4 réplicas
(3 / 17 / 7 ms) são ruído de JVMs recém-criadas (ainda sem o JIT aquecido), não ganho nem perda.
Conclusão honesta: **nessa carga o gateway não é o gargalo**; o motivo para ter 2+ réplicas é
disponibilidade (uma pode cair), não capacidade.

**4. Saturação — achamos o gargalo real, e não era o gateway.** Sem pausa, a plataforma passou de
**4.100 req/s** com uma réplica do gateway, mas **0,57 % das requisições falharam (3.279)**, todas em
`GET /auth/me`, nenhuma em `GET /accounts/{id}`. O gateway devolveu `500` e o log do Auth mostrou
exatamente **3.279 × `java.net.BindException: Cannot assign requested address`**:

``` mermaid
flowchart LR
    gw[gateway] -->|"GET /auth/me"| auth[Auth]
    auth -->|"Feign: 1 conexão TCP nova<br/>por chamada (sem pool)"| acc[Account]
    auth -.-x|"portas efêmeras<br/>esgotadas → 500"| acc
```

O `GET /auth/me` do Auth chama o Account pelo **OpenFeign com o cliente HTTP padrão, sem pool de
conexões**: cada requisição abre uma conexão TCP nova, e a 4.000 req/s as portas locais do container do
Auth acabam (as fechadas ficam em `TIME_WAIT`). Com 4 réplicas do gateway a máquina ficou mais
ocupada (CPU em ≈ 83 % nas duas rodadas, 4 JVMs disputando os mesmos núcleos), a vazão caiu para
2.697 req/s e o Auth não chegou no limite — por isso 0 erros, mas p95 o dobro.

!!! tip "Correção sugerida (Auth — Nicolas)"

    Trocar o cliente do Feign por um com **pool de conexões** e keep-alive — adicionar
    `io.github.openfeign:feign-hc5` ao `auth-service` e `spring.cloud.openfeign.httpclient.hc5.enabled=true`.
    Com conexões reaproveitadas, o Auth deixa de abrir uma porta por requisição. Depois, repetir
    `ONLY=5 ./scripts/load-matrix.sh` para confirmar que os `500` somem.

**5. Uso real (`mixed`).** Dentro do SLO, mas com a cauda mais longa da bateria (p95 62 ms, p99 197 ms):
5 % das ações são `POST /auth/login`, que faz o hash da senha (custoso de propósito) e emite o JWT.

### Limitações

- **Tudo na mesma máquina:** o k6 disputa CPU com a plataforma. Os números mostram **tendências e
  gargalos**, não a capacidade do EKS. Em nós separados, mais réplicas devem *aumentar* a vazão —
  aqui ficaram presas à mesma CPU.
- **Rodadas curtas (1–3 min) e uma execução por configuração:** diferenças de poucos ms são ruído.
- **20 contas reutilizadas:** favorece o cache do token (é o padrão de uso logado, mas um teste com
  milhares de usuários novos teria mais misses).

Para medir a capacidade real: `BASE_URL=http://<elb> ./scripts/load-test.sh` a partir de outra máquina.

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
