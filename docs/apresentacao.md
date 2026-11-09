# Apresentação

!!! warning "Rascunho — revisar em grupo"

    Estrutura e roteiro propostos pelo Leonardo a partir das páginas da documentação. Cada integrante
    revisa e ajusta a sua parte; o vídeo entra no fim da página depois do dia do EKS.

Tópicos pedidos pelo curso: introdução, arquitetura, demonstração, desafios (bottlenecks), conclusão e
próximos passos. Vídeo de **1 a 2 minutos** com o projeto e os bottlenecks.

## Roteiro do vídeo (≈ 2 min)

| Tempo | Quem | Fala / tela |
|---|---|---|
| 0:00–0:15 | Leonardo | **Introdução.** Loja em microsserviços: cadastro, login e câmbio, tudo entrando por um gateway. Grupo pna26 (Leonardo, Nicolas, Gabriel). |
| 0:15–0:35 | Leonardo | **Arquitetura** (diagrama da [Home](index.md)): Nginx → réplicas do gateway → Auth, Account, Exchange; Redis, PostgreSQL/RDS, Kafka; tudo no EKS, com deploy pelo GitHub Actions. |
| 0:35–1:05 | Nicolas | **Demonstração no EKS:** `kubectl get pods -n store`, cadastro e login pelo ELB, `GET /accounts` com e sem token (401), câmbio. E-mail de boas-vindas chegando pelo Kafka. |
| 1:05–1:45 | todos | **Bottlenecks**, cada um os seus (tabela abaixo), com o número que mostra o efeito. Teste de carga com o HPA escalando o gateway. |
| 1:45–2:00 | Gabriel | **Custos e conclusão:** ≈ US$ 0,27/h com tudo ligado, cluster apagado fora dos testes; próximos passos. |

## Bottlenecks (o que mostrar)

| Bottleneck | Quem | Número para mostrar | Página |
|---|---|---|---|
| Balanceamento de carga | Leonardo | Nginx distribuindo entre N réplicas do gateway; réplicas novas entram sem `reload` | [Balanceamento](bottlenecks/load-balancing.md) |
| Cache do token (Redis) | Leonardo | 3.001 requisições autenticadas → **1** chamada ao Auth (3.000 hits) | [Cache](bottlenecks/cache.md) |
| Varredura de vulnerabilidades | Leonardo | Trivy bloqueia CVE CRITICAL corrigível; imagem final com 0 HIGH/CRITICAL; OWASP ZAP no gateway | [Varredura](bottlenecks/vulnerability-scanning.md) |
| Cache da cotação | Gabriel | p95 da cotação de **49 ms → 4 ms** (−92 %) | [Cache da cotação](bottlenecks/exchange-cache.md) |
| Observabilidade | Gabriel | Grafana explicou o teste de carga: CPU em 83–85 % e os 0,57 % de erro (`BindException` no Auth) | [Observabilidade](bottlenecks/observability.md) |
| Mensageria (Kafka) | Nicolas | Cadastro em ~15 ms com o consumidor **ou** o Kafka fora; 0 eventos perdidos, 0 e-mails duplicados | [Mensageria](bottlenecks/messaging.md) |

## Slides

1. **Introdução** — o problema (loja que precisa escalar e ser segura) e o grupo.
2. **Arquitetura** — diagrama, camada confiável (só o `lb` é exposto), contrato da API
   ([Arquitetura](arquitetura.md)).
3. **Demonstração** — vídeo ou ao vivo no EKS ([EKS](devops/eks.md)).
4. **CI/CD** — pipeline reutilizável: testes, Trivy, imagem multi-arch, deploy no EKS via OIDC
   ([CI/CD](devops/ci-cd.md)).
5. **Bottlenecks** — a tabela acima, um slide por integrante.
6. **Teste de carga e SLA** — cenários, HPA, SLO e custos ([Testes de carga](devops/load-testing.md),
   [Custos e SLA](devops/custos-sla.md)).
7. **Conclusão e próximos passos** — HTTPS com domínio próprio, Kafka com disco persistente (ou MSK), lag do
   consumidor no Prometheus, pool de conexões no Feign do Auth.

## Vídeo

<!-- vídeo: <iframe width="100%" height="470" src="https://www.youtube.com/embed/<id>" allowfullscreen></iframe> -->
