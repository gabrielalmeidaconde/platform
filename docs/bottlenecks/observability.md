# Observabilidade

!!! warning "A preencher — responsável: Gabriel"

    Página criada na estrutura da documentação; o conteúdo é do item **Bottleneck: Observability (Prometheus + Grafana)** do
    [quadro do projeto](https://github.com/orgs/pna26/projects/1){target="_blank"}.

O gateway já expõe métricas no formato Prometheus em `http://gateway:8080/gateway/actuator/prometheus` (só pela rede interna; o `lb` bloqueia esse caminho para fora), com a tag `application="gateway"`. Métrica própria do cache: `gateway_token_cache_total{result="hit|miss|error"}`.

Como o gateway tem várias réplicas, use `dns_sd_configs` (compose) ou as anotações `prometheus.io/*` do pod (k8s) para o Prometheus raspar todas, e não `static_configs` com `gateway:8080` (cairia numa réplica aleatória).
