# Testes de carga

!!! warning "A preencher — responsável: Gabriel"

    Página criada na estrutura da documentação; o conteúdo é do item **Load Testing (15%)** do
    [quadro do projeto](https://github.com/orgs/pna26/projects/1){target="_blank"}.

A plataforma local sobe com `./scripts/build.sh && docker compose up -d --build` em `http://localhost:8080` (ver [Como rodar](../como-rodar.md)). Para comparar o bottleneck de cache, rode o mesmo cenário com `TOKEN_CACHE_ENABLED=true` e `false`; para o balanceamento, varie `GATEWAY_REPLICAS` (ou `--scale gateway=N`).
