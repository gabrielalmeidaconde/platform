# EKS

!!! warning "A preencher — responsável: Nicolas"

    Página criada na estrutura da documentação; o conteúdo é do item **EKS (10%)** do
    [quadro do projeto](https://github.com/orgs/pna26/projects/1){target="_blank"}.

Quando o cluster estiver no ar, o deploy é automático pelo pipeline ([CI/CD](ci-cd.md)): definir `EKS_CLUSTER`/`AWS_REGION` e os secrets na organização. Infra compartilhada já pronta no `platform/k8s/` (Nginx `lb` com Service LoadBalancer e Redis) e o manifesto do gateway em `gateway-service/k8s/`. Faltam os manifestos de `account`, `auth`, `exchange` e do banco (ou RDS).
