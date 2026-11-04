# Bottlenecks

Gargalos identificados na plataforma e o que foi feito em cada um (o enunciado pede ao menos 2 por
integrante).

| Gargalo | Problema | Mitigação | Responsável | Status |
|---|---|---|---|---|
| [Balanceamento de carga](load-balancing.md) | Um gateway só é ponto único de falha e de capacidade | Nginx na frente de N réplicas do gateway (compose e EKS) | Leonardo | pronto |
| [Cache](cache.md) | Toda requisição autenticada chamava o Auth (`/auth/solve`) | Redis compartilhado entre as réplicas: token → id da conta | Leonardo | pronto |
| [Varredura de vulnerabilidades](vulnerability-scanning.md) | Dependências, imagens e manifestos com falhas conhecidas | Trivy (SCA, imagem, segredos, IaC) no pipeline + OWASP ZAP (DAST) | Leonardo | pronto |
| [Observabilidade](observability.md) | Sem visibilidade do comportamento sob carga | Prometheus + Grafana | Gabriel | a fazer |
| [Mensageria](messaging.md) | Acoplamento síncrono entre serviços | Kafka/RabbitMQ (ex.: evento de conta criada) | Nicolas | a fazer |
