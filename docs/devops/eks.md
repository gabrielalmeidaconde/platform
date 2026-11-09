# EKS

!!! info "Responsável: Nicolas"

A plataforma roda num cluster **Amazon EKS** (`eks-store`, região `us-east-2`) com o banco do
Account num **Amazon RDS for PostgreSQL**. Tudo fica no namespace `store`. O cluster é criado com o
`eksctl` a partir de um arquivo versionado ([`setup/eks-store.yaml`](https://github.com/pna26/platform/blob/main/setup/eks-store.yaml){target="_blank"})
e **apagado quando não está em uso**, porque é o item mais caro do projeto (ver [Custos](#custos)).

## Arquitetura

``` mermaid
flowchart LR
    user([internet]) --> elb[ELB da AWS<br/>Service lb · LoadBalancer]
    subgraph vpc[VPC 10.20.0.0/16 · us-east-2a e 2b]
        subgraph pub[sub-redes públicas]
            elb
            nat[NAT gateway]
        end
        subgraph priv[sub-redes privadas · 2 nós t3.medium]
            lb[lb · Nginx ×2] --> gw[gateway ×2]
            gw <--> redis[(Redis)]
            gw --> auth & account & exchange[exchange ×2]
            auth --> account
            prom[Prometheus] --> graf[Grafana]
        end
        rds[(RDS PostgreSQL 17<br/>db.t4g.micro)]
    end
    elb --> lb
    account -->|5432| rds
    exchange --> nat --> api([AwesomeAPI])
    priv -.->|pull| ecr[(ECR)]
```

| Peça | Escolha | Por quê |
|---|---|---|
| Versão do Kubernetes | 1.37 | versão padrão do EKS, em suporte padrão até 11/2027 (versões em suporte estendido custam 6× mais por hora) |
| Nós | 2× `t3.medium` (2 vCPU, 4 GiB), managed node group | os requests de memória somam ~2,6 GiB; 2× `t3.small` (~2,9 GiB úteis, 11 pods por nó) não deixavam folga para rolling update nem para o teste de carga |
| Rede | VPC própria do eksctl, 2 zonas, nós **só em sub-redes privadas** (sem IP público) | os nós não ficam expostos; só o ELB, nas sub-redes públicas, recebe tráfego da internet |
| Saída para a internet | 1 NAT gateway | os nós precisam baixar imagens do ECR e o exchange chama a AwesomeAPI; um NAT por zona dobraria o custo |
| Acesso ao cluster | `authenticationMode: API` (access entries) | permissões do Kubernetes dadas a roles da AWS sem editar o ConfigMap `aws-auth` |
| Imagens | ECR (`637423273088.dkr.ecr.us-east-2.amazonaws.com/<serviço>-service`) | os pacotes do GHCR são privados; os nós já têm permissão de leitura no ECR |
| Banco | RDS PostgreSQL 17.11, `db.t4g.micro`, 20 GB gp3 | a página do EKS do curso pede RDS ou DynamoDB; 20 GB é o mínimo do RDS |

### Exposição dos serviços

Só o `lb` é `type: LoadBalancer`. Gateway, auth, account e exchange são `ClusterIP`: ficam acessíveis
só de dentro do cluster, pelos nomes `gateway`, `auth`, `account` e `exchange` na porta 8080. São os
mesmos nomes do compose, por isso os Feign clients (`http://account:8080`, `http://auth:8080`) e o
`nginx.conf` funcionam sem mudança.

## Manifestos

Cada serviço tem o próprio `k8s/k8s.yaml` no seu repositório (ConfigMap, Deployment e Service), e a
infra compartilhada (lb, Redis, Prometheus, Grafana) fica em `platform/k8s/`. Padrões comuns:

- label `app: <serviço>`, usada pelo `selector` do Service e pelo `kubectl rollout` do pipeline;
- `requests`/`limits` de CPU e memória (o Java usa `-XX:MaxRAMPercentage=75` para respeitar o limite);
- container sem root (`runAsNonRoot`, uid 1001), sem escalada de privilégio, sistema de arquivos só
  leitura e um `emptyDir` em `/tmp`;
- `readinessProbe`/`livenessProbe` (account e auth usam probe TCP na 8080, porque não têm Actuator);
- imagem terminando em `/<serviço>-service:latest`: o pipeline troca pela tag do commit (`sha-xxxxxxx`).

### Segredos

Nenhum segredo fica no Git. O pipeline faz `kubectl apply -f k8s/` a cada deploy, então um Secret de
exemplo dentro de `k8s/` sobrescreveria o real. Os Secrets são criados uma vez por cluster:

| Secret | Chaves | Usado por |
|---|---|---|
| `account-secrets` | `DATABASE_USERNAME`, `DATABASE_PASSWORD` | account (`secretRef`) |
| `auth-secrets` | `JWT_SECRET_KEY` | auth (`secretRef`) |
| `grafana-admin` | `password` | Grafana (criado pelo workflow `infra`) |

O host, a porta e o nome do banco não são segredos e ficam no ConfigMap `account-configmap`
(`DATABASE_HOST` = endpoint do RDS).

## RDS PostgreSQL

| Configuração | Valor |
|---|---|
| Instância | `rds-store`, `db.t4g.micro`, single-AZ |
| Armazenamento | 20 GB gp3, criptografado, **storage autoscaling desligado** |
| Rede | subnet group `rds-store` (só as sub-redes privadas), **sem acesso público** |
| Firewall | security group `rds-store`: entrada **só na porta 5432 e só a partir do security group dos nós** do EKS (nenhuma faixa de IP liberada) |
| Backup | 1 dia de retenção, sem proteção contra exclusão (o ambiente é recriado com frequência) |
| Schema | criado pelo Flyway do account no primeiro boot (`accounts`) |

O endpoint é `rds-store.<id-da-conta>.us-east-2.rds.amazonaws.com`: ele depende só do nome da
instância, da conta e da região, então é o mesmo toda vez que o RDS é recriado com o nome `rds-store`.
A senha é aleatória e só existe no RDS e no Secret `account-secrets`.

## Deploy pelo CI/CD

O pipeline reutilizável ([CI/CD](ci-cd.md)) faz o deploy em todo push na `main`, quando a variável
da organização `EKS_CLUSTER` está definida: `aws eks update-kubeconfig` → troca da imagem pela do
commit → `kubectl apply -n store -f k8s/` → `kubectl rollout status`.

O GitHub Actions entra na AWS pela role OIDC `github-actions-pna26` (ver [AWS](aws.md)). Dentro do
cluster, ela tem uma **access entry** com a access policy `AmazonEKSAdminPolicy` **limitada ao
namespace `store`**: pode criar e atualizar Deployments, Services, ConfigMaps, Secrets e também
`Role`/`RoleBinding` ali, e nada fora dele. A `AmazonEKSEditPolicy` não basta: ela segue o papel
`edit` do Kubernetes, que não deixa mexer em roles, e o workflow `infra` aplica o `Role`/`RoleBinding`
do Prometheus. Como o acesso é só ao namespace, o `store` é criado à mão (`kubectl create namespace
store`, no passo 1 abaixo).

``` bash
aws eks create-access-entry --cluster-name eks-store --region us-east-2 \
  --principal-arn arn:aws:iam::637423273088:role/github-actions-pna26
aws eks associate-access-policy --cluster-name eks-store --region us-east-2 \
  --principal-arn arn:aws:iam::637423273088:role/github-actions-pna26 \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy \
  --access-scope type=namespace,namespaces=store
```

!!! warning "Situação"

    O primeiro deploy (08/11/2026) foi feito à mão, com os mesmos passos do pipeline. O `service.yaml`
    já autentica pela role OIDC (`vars.AWS_ROLE_ARN` + `id-token: write`); o deploy automático liga
    quando a variável `EKS_CLUSTER=eks-store` é criada na organização, com o cluster no ar.

## Ciclo de vida do ambiente

Todos os comandos rodam a partir da raiz do `platform`, com o AWS CLI logado (`aws sso login`).

### Criar (~25 min)

``` bash
# 1. cluster, VPC, NAT e nós (~15 min); já configura o kubectl
eksctl create cluster -f setup/eks-store.yaml
kubectl create namespace store
# 2. access entry do CI (comandos da seção anterior)

# 3. rede do RDS: security group (5432 só dos nós) e subnet group (sub-redes privadas)
VPC=$(aws eks describe-cluster --name eks-store --query cluster.resourcesVpcConfig.vpcId --output text)
NODES_SG=$(aws eks describe-cluster --name eks-store --query cluster.resourcesVpcConfig.clusterSecurityGroupId --output text)
SUBNETS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC Name=map-public-ip-on-launch,Values=false \
  --query 'Subnets[].SubnetId' --output text)
RDS_SG=$(aws ec2 create-security-group --vpc-id $VPC --group-name rds-store \
  --description "RDS PostgreSQL: 5432 so dos nos do eks-store" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id $RDS_SG --protocol tcp --port 5432 --source-group $NODES_SG
aws rds create-db-subnet-group --db-subnet-group-name rds-store \
  --db-subnet-group-description "Sub-redes privadas do eks-store" --subnet-ids $SUBNETS

# 4. RDS (~10 min) e o Secret com a mesma senha
DB_PASS=$(openssl rand -hex 24)
aws rds create-db-instance --db-instance-identifier rds-store --engine postgres --engine-version 17.11 \
  --db-instance-class db.t4g.micro --allocated-storage 20 --storage-type gp3 --storage-encrypted \
  --master-username store --master-user-password "$DB_PASS" --db-name store \
  --db-subnet-group-name rds-store --vpc-security-group-ids $RDS_SG \
  --no-publicly-accessible --no-multi-az --backup-retention-period 1 --no-deletion-protection
kubectl create secret generic account-secrets -n store \
  --from-literal=DATABASE_USERNAME=store --from-literal=DATABASE_PASSWORD="$DB_PASS"
kubectl create secret generic auth-secrets -n store --from-literal=JWT_SECRET_KEY="$(openssl rand -base64 32)"

# 5. deploy: rodar o workflow "infra" e o CI de cada serviço (ou kubectl apply à mão)
```

### Testar

``` bash
LB=$(kubectl get svc lb -n store -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
BASE_URL=http://$LB ./scripts/smoke-test.sh
```

Resultado em 08/11/2026: **smoke test passou** — register/login com cookie `HttpOnly`, 401 sem token,
com token inválido e com `id-account` forjado, as duas réplicas do gateway respondendo e o actuator
bloqueado no lb. O único aviso foi o câmbio: a AwesomeAPI responde **429** para o IP do NAT da AWS
(limite da API gratuita para IPs de nuvem), e o exchange devolve 503 como esperado.

### Apagar (~15 min)

A ordem importa: o ELB (criado pelo Service `lb`) e o RDS ficam dentro da VPC do eksctl e impedem
que ela seja apagada.

``` bash
kubectl delete svc lb -n store
aws rds delete-db-instance --db-instance-identifier rds-store --skip-final-snapshot --delete-automated-backups
aws rds wait db-instance-deleted --db-instance-identifier rds-store
aws rds delete-db-subnet-group --db-subnet-group-name rds-store
aws ec2 delete-security-group --group-id $RDS_SG
eksctl delete cluster -f setup/eks-store.yaml --disable-nodegroup-eviction
```

## Custos

Preços on-demand em us-east-2, por hora com o ambiente ligado:

| Item | US$/h |
|---|---:|
| Control plane do EKS (suporte padrão) | 0,100 |
| 2× EC2 `t3.medium` | 0,083 |
| NAT gateway (sem contar dados) | 0,045 |
| Classic Load Balancer | 0,025 |
| RDS `db.t4g.micro` + 20 GB gp3 | 0,019 |
| **Total** | **~0,27** |

Com o budget de US$ 20/mês, isso dá cerca de **70 horas ligado**. Por isso o ambiente é criado para
testes, demonstração e teste de carga e apagado em seguida. As imagens no ECR continuam (centavos
por mês).

## Problemas encontrados

| Problema | Causa | Solução |
|---|---|---|
| `docker login` no ECR falha no Windows ("O fragmento de código recebeu dados incorretos") | o token do ECR obtido com SSO tem ~3 KB e o Gerenciador de Credenciais do Windows aceita no máximo 2560 bytes | usar o `docker-credential-ecr-login` (vem com o Docker Desktop) em `credHelpers`, sem `docker login` |
| `denied` ao baixar imagens do GHCR | token do `gh` sem o escopo `read:packages` | `gh auth refresh -h github.com -s read:packages` |
| pods do `lb` reiniciam 2 vezes no primeiro deploy | o Nginx resolve `gateway` ao iniciar e subiu antes do Service `gateway` existir | nenhuma: na tentativa seguinte o Service já existe |
| exchange devolve 503 no EKS | a AwesomeAPI responde 429 para o IP de saída da AWS | comportamento esperado do exchange (cache + 503); afeta o cenário `exchange` do teste de carga |
