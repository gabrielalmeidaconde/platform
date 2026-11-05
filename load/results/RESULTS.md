# Resultados do teste de carga

- Data: 2026-11-05 12:11
- Máquina: Docker Desktop, 12 CPUs, 7852576768 bytes de RAM para o Docker
- k6, Nginx, gateway e serviços na **mesma máquina** (o k6 disputa CPU com a plataforma)

Latências em ms, só respostas esperadas (2xx/3xx). Erros = % de respostas 4xx/5xx/timeout.

| Execução | Cenário | Perfil | VUs máx. | Requisições | req/s | p50 | p95 | p99 | Erros |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| token-cache-off | auth | load | 50 | 7416 | 80.8 | 5 | 12 | 20 | 0.00 % |
| token-cache-on | auth | load | 50 | 7448 | 79.7 | 4 | 7 | 15 | 0.00 % |
| replicas-1 | auth | stress | 400 | 41110 | 290.9 | 2 | 3 | 4 | 0.00 % |
| replicas-2 | auth | stress | 400 | 40810 | 287.1 | 2 | 17 | 114 | 0.00 % |
| replicas-4 | auth | stress | 400 | 40918 | 285.8 | 3 | 7 | 23 | 0.00 % |
| exchange-cache-off | exchange | load | 10 | 445 | 7.3 | 23 | 49 | 69 | 0.00 % |
| exchange-cache-on | exchange | load | 10 | 454 | 7.5 | 3 | 4 | 17 | 0.00 % |
| mixed-load | mixed | load | 50 | 6605 | 72.1 | 4 | 62 | 197 | 0.00 % |
| saturation-1 | auth | stress | 200 | 578564 | 4120.0 | 13 | 43 | 69 | 0.57 % |
| saturation-4 | auth | stress | 200 | 387296 | 2697.1 | 14 | 88 | 166 | 0.00 % |
