# CI/CD (GitHub Actions)

!!! info "Responsável: Leonardo"

Escolhemos **GitHub Actions** em vez de Jenkins: não precisa de servidor próprio rodando, os segredos
ficam na organização do GitHub e os resultados aparecem direto nos PRs e na aba Security.

## Desenho

Um único pipeline **reutilizável** fica no repositório `platform`
([`.github/workflows/service.yaml`](https://github.com/pna26/platform/blob/main/.github/workflows/service.yaml){target="_blank"})
e cada microsserviço só tem um arquivo pequeno que o chama. Uma correção no pipeline vale para todos os
serviços de uma vez.

``` mermaid
flowchart LR
    subgraph svc ["repo do serviço (push/PR)"]
        ci["ci.yaml<br/>(10 linhas)"]
    end
    subgraph platform ["pna26/platform"]
        reuse["service.yaml<br/>(workflow_call)"]
    end
    ci -->|uses| reuse
    reuse --> b["1. build + testes"]
    b --> s1["2. Trivy: código"]
    s1 --> s2["3. Trivy: imagem"]
    s2 --> gate{"portão de<br/>segurança"}
    gate -->|"push na main"| p["4. push multi-arch<br/>GHCR + ECR"]
    p --> d["5. deploy EKS<br/>kubectl apply + rollout"]
```

| Etapa | Quando | O que faz |
|---|---|---|
| 1. Build e testes | sempre | `mvn verify` (Java, depois do `mvn install` das interfaces `account`/`auth` da org) ou `pytest` (Python) |
| 2. Trivy no código | sempre | dependências, segredos, `Dockerfile` e `k8s/` ([detalhes](../bottlenecks/vulnerability-scanning.md)) |
| 3. Trivy na imagem | serviços | `docker build` local e varredura da imagem antes de publicar |
| Portão | sempre | falha com CVE CRITICAL corrigível ou segredo exposto |
| 4. Push | push na `main` | imagem `linux/amd64` + `linux/arm64` em `ghcr.io/pna26/<serviço>:sha-<commit>` e `:latest`; também no ECR quando houver credenciais da AWS (cria o repositório com *scan on push* se faltar) |
| 5. Deploy | push na `main` com `EKS_CLUSTER` definido | `aws eks update-kubeconfig`, troca a imagem `:latest` do `k8s/` pela do commit, `kubectl apply` e espera o `rollout status` |

Em **pull requests** só rodam as etapas 1–3: o PR mostra se compila, se os testes passam e se a
varredura acha algo, sem publicar nada.

## Como cada serviço usa

=== "gateway-service"

    ``` { .yaml .copy title=".github/workflows/ci.yaml" }
    --8<-- "api/gateway-service/.github/workflows/ci.yaml"
    ```

=== "account / auth (bibliotecas)"

    ``` { .yaml .copy title=".github/workflows/ci.yaml" }
    name: ci
    on:
      push:
        branches: [ main ]
      pull_request:
      workflow_dispatch:
    permissions:
      contents: read
      packages: write
      security-events: write
    jobs:
      pipeline:
        uses: pna26/platform/.github/workflows/service.yaml@main
        with:
          service: account          # sem "image": só build, testes e scan
        secrets: inherit
    ```

=== "account-service / auth-service"

    ``` { .yaml .copy title=".github/workflows/ci.yaml" }
    name: ci
    on:
      push:
        branches: [ main ]
      pull_request:
      workflow_dispatch:
    permissions:
      contents: read
      packages: write
      security-events: write
    jobs:
      pipeline:
        uses: pna26/platform/.github/workflows/service.yaml@main
        with:
          service: account
          image: account-service
          maven-deps: account       # auth-service: "account auth"
          aws-region: ${{ vars.AWS_REGION }}
          eks-cluster: ${{ vars.EKS_CLUSTER }}
          k8s-namespace: ${{ vars.K8S_NAMESPACE || 'store' }}
        secrets: inherit
    ```

=== "exchange-service (Python)"

    ``` { .yaml .copy title=".github/workflows/ci.yaml" }
    name: ci
    on:
      push:
        branches: [ main ]
      pull_request:
      workflow_dispatch:
    permissions:
      contents: read
      packages: write
      security-events: write
    jobs:
      pipeline:
        uses: pna26/platform/.github/workflows/service.yaml@main
        with:
          service: exchange
          image: exchange-service
          language: python
          aws-region: ${{ vars.AWS_REGION }}
          eks-cluster: ${{ vars.EKS_CLUSTER }}
          k8s-namespace: ${{ vars.K8S_NAMESPACE || 'store' }}
        secrets: inherit
    ```

## Configuração da AWS (alinhar com o Nicolas)

O deploy só liga quando estas configurações existem na **organização** `pna26` (Settings → Secrets and
variables → Actions), assim nenhum repositório precisa mudar:

| Tipo | Nome | Exemplo |
|---|---|---|
| Variable | `AWS_REGION` | `us-east-2` |
| Variable | `EKS_CLUSTER` | `eks-store` |
| Variable | `K8S_NAMESPACE` | `store` (padrão) |
| Secret | `AWS_ACCESS_KEY_ID` | chave de um usuário IAM só para o CI |
| Secret | `AWS_SECRET_ACCESS_KEY` | |
| Secret | `AWS_SESSION_TOKEN` | só se a conta usar credenciais temporárias (Learner Lab) |

O usuário IAM do CI precisa de: `AmazonEC2ContainerRegistryPowerUser` (push no ECR),
`eks:DescribeCluster` e uma **access entry** no cluster EKS com a política
`AmazonEKSEditPolicy` no namespace `store` (para o `kubectl apply`).

!!! tip "Sem credenciais da AWS"

    Sem os secrets, o pipeline continua fazendo build, testes, varredura e publica as imagens no
    **GHCR**. O EKS consegue puxar do GHCR desde que os pacotes estejam públicos.

## Outros workflows do `platform`

| Workflow | Gatilho | O que faz |
|---|---|---|
| `integration` | push, PR, toda segunda | Sobe a plataforma inteira com o compose (submódulos), roda o `smoke-test.sh` e o OWASP ZAP |
| `infra` | mudança em `k8s/` | Aplica no EKS o Nginx (`lb`) e o Redis |
| `docs` | push na `main` | Publica esta documentação no GitHub Pages |

## Pipeline completo

??? example "`.github/workflows/service.yaml`"

    ``` { .yaml .copy linenums="1" }
    --8<-- ".github/workflows/service.yaml"
    ```
