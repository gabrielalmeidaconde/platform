# Exchange

!!! info "Responsável: Gabriel — repositório [pna26/exchange-service](https://github.com/pna26/exchange-service){target="_blank"}"

Microsserviço de **câmbio** em **Python (FastAPI)**. Recebe um par de moedas, busca a cotação numa API
de terceiros e devolve o preço de compra e de venda para o usuário logado.

``` mermaid
flowchart LR
    u([Usuário]) -->|"GET /exchange/USD/BRL<br/>cookie JWT"| lb[lb · Nginx] --> gw[gateway]
    gw -->|"+ header id-account"| ex[exchange]
    ex <-->|"hit (30 s)"| cache[(cache em memória)]
    ex -->|"miss"| api([AwesomeAPI])
```

## Contrato

| Método | Rota | Entrada | Saída |
|---|---|---|---|
| GET | `/exchange/{from}/{to}` | header `id-account` (posto pelo gateway) | `{ sell, buy, date, id-account }` |

O gateway também aceita `/exchanges/{from}/{to}` e reescreve para `/exchange/...`.

``` bash
curl -H "Cookie: __store_jwt_token=$TOKEN" localhost:8080/exchange/USD/BRL
```

``` json
{ "sell": 5.3942, "buy": 5.3912, "date": "2026-11-05 10:00:00", "id-account": "8f1c..." }
```

| Status | Quando |
|---|---|
| 200 | cotação (do cache ou da API externa) |
| 400 | moeda que não tem 3 letras (`/exchange/US/BRL`) |
| 401 | sem token (barrado no gateway) ou sem `id-account` (não passou pelo gateway) |
| 404 | par que a API externa não conhece |
| 503 | API externa fora do ar **e** sem cotação recente em cache |

## Decisões

| Decisão | Motivo |
|---|---|
| FastAPI + `httpx` assíncrono | Enquanto espera a API externa, o processo atende outras requisições (o serviço é quase só I/O). |
| AwesomeAPI (`economia.awesomeapi.com.br`) | Gratuita, sem cadastro, cobre BRL. `ask` → `sell` e `bid` → `buy` (por isso `sell ≥ buy`). Token opcional em `EXCHANGE_API_TOKEN` aumenta o limite. |
| Cache da cotação por 30 s | É o bottleneck deste serviço: ver [Cache da cotação](../bottlenecks/exchange-cache.md). |
| Mesma moeda (`BRL/BRL`) responde `1.0` sem chamar a API | Evita uma chamada externa inútil (a API devolveria 404). |
| `401` sem `id-account` | O serviço só deve ser alcançado pelo gateway; sem o header, a requisição veio de outro lugar. |
| 1 processo `uvicorn` por container | As métricas do `prometheus_client` ficam na memória do processo; com vários workers cada scrape veria um diferente. Escala com réplicas (`EXCHANGE_REPLICAS` / `replicas` no k8s). |
| Porta 8080 e nome `exchange` | O gateway encaminha para `http://exchange:8080` no compose e no k8s. |
| `/metrics` fora de `/exchange/**` | O gateway só encaminha `/exchange/**`, então as métricas ficam só na rede interna (o Prometheus raspa direto). |
| Imagem `python:3.12-slim`, usuário 1001, FS somente leitura no k8s | Menos pacotes para o Trivy e mesmo padrão de segurança dos outros serviços. |

## Configuração

| Variável | Padrão | |
|---|---|---|
| `EXCHANGE_API_URL` | `https://economia.awesomeapi.com.br/json/last` | API externa |
| `EXCHANGE_API_TOKEN` | — | token da AwesomeAPI (opcional) |
| `CACHE_TTL` | `30` | segundos que uma cotação vale (`0` desliga o cache) |
| `CACHE_STALE_TTL` | `600` | quanto tempo uma cotação velha ainda serve se a API cair |
| `UPSTREAM_TIMEOUT` | `3` | timeout da chamada externa, em segundos |

No compose, `EXCHANGE_CACHE_TTL` e `EXCHANGE_REPLICAS` (no `.env`) viram `CACHE_TTL` e o número de réplicas.

## Código

=== "app/main.py"

    ``` { .python .copy linenums="1" }
    --8<-- "api/exchange-service/app/main.py"
    ```

=== "app/provider.py"

    ``` { .python .copy linenums="1" }
    --8<-- "api/exchange-service/app/provider.py"
    ```

=== "app/cache.py"

    ``` { .python .copy linenums="1" }
    --8<-- "api/exchange-service/app/cache.py"
    ```

=== "Dockerfile"

    ``` { .dockerfile .copy }
    --8<-- "api/exchange-service/Dockerfile"
    ```

=== "k8s/k8s.yaml"

    ``` { .yaml .copy }
    --8<-- "api/exchange-service/k8s/k8s.yaml"
    ```

## Testes

`pytest` com a API externa simulada (`httpx.MockTransport`), rodando no pipeline de CI
([CI/CD](../devops/ci-cd.md)): contrato da resposta, `sell ≥ buy`, 400/401/404/503, `429` da API externa
virando `503`, mesma moeda sem chamada externa, 50 requisições → 1 chamada externa, e o cache (TTL,
*stale-if-error*, 100 requisições simultâneas → 1 chamada). O [smoke test](../como-rodar.md#smoke-test)
confere a rota de ponta a ponta pelo gateway, inclusive que o `id-account` que chega é o do usuário logado.

``` bash
cd api/exchange-service
pip install -r requirements.txt pytest && pytest -q
```
