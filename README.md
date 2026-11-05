# platform — pna26

Repositório principal do projeto de **Plataformas, Microsserviços, DevOps e APIs** (Insper, 2026.2).

📚 **Documentação:** https://pna26.github.io/platform · 📋 **Quadro:** https://github.com/orgs/pna26/projects/1

```
platform/
├── api/                      # microsserviços (submódulos)
│   ├── account/              #   interface Feign + DTOs do Account
│   ├── account-service/      #   Account (Spring Boot + PostgreSQL)
│   ├── auth/                 #   interface Feign + DTOs do Auth
│   ├── auth-service/         #   Auth (JWT)
│   ├── exchange-service/     #   Exchange (Python/FastAPI, câmbio)
│   └── gateway-service/      #   API gateway (Spring Cloud Gateway + Redis)
├── compose.yaml              # plataforma local: db, redis, account, auth, exchange, gateway (N), lb
├── setup/                    # nginx.conf (balanceador), prometheus.yml e grafana/ (dashboards)
├── k8s/                      # infra compartilhada no EKS: lb (Nginx), redis, prometheus e grafana
├── scripts/                  # build.sh e smoke-test.sh
├── .github/workflows/        # service.yaml (CI/CD reutilizável), integration, infra, docs
├── docs/ + mkdocs.yml        # documentação (MkDocs Material)
```

## Rodar

```bash
git clone --recurse-submodules https://github.com/pna26/platform.git && cd platform
./scripts/build.sh               # compila interfaces e serviços, cria o .env
docker compose up -d --build     # http://localhost:8080
./scripts/smoke-test.sh          # teste ponta a ponta
```

## Grupo

Leonardo ([@souzxxx](https://github.com/souzxxx)), Nicolas ([@NicolasVolf](https://github.com/NicolasVolf)) e
Gabriel ([@gabrielalmeidaconde](https://github.com/gabrielalmeidaconde)).
