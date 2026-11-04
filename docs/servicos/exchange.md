# Exchange

!!! warning "A preencher — responsável: Gabriel"

    Página criada na estrutura da documentação; o conteúdo é do item **Exchange (5%)** do
    [quadro do projeto](https://github.com/orgs/pna26/projects/1){target="_blank"}.

Contrato: `GET /exchange/{from}/{to}` com o header `id-account` (o gateway também aceita `/exchanges/...`). O gateway encaminha para `http://exchange:8080` — o serviço precisa escutar na porta **8080** e se chamar `exchange` no compose/k8s (ou definir `EXCHANGE_URI` no gateway).

Para entrar no compose do `platform`: criar o repositório `pna26/exchange-service` com um `Dockerfile` e adicioná-lo como submódulo em `api/exchange-service` (`docker compose --profile exchange up`). O pipeline de CI/CD já suporta Python ([CI/CD](../devops/ci-cd.md)).
