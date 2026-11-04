# Uso de IA

O enunciado permite o uso **parcial** de IA na implementação, desde que documentado: o que foi feito
com ajuda de IA, o que foi feito pelo grupo, e todos precisam saber explicar e defender qualquer parte
(inclusive a gerada por IA). Esta página é esse registro — cada integrante preenche a sua parte.

!!! danger "Regra do grupo"

    Nada gerado por IA entra sem que o responsável tenha lido, rodado e entendido. Antes da
    apresentação fazemos um walkthrough interno em que cada um explica as partes dos outros.

## Leonardo

**Ferramenta:** Claude Code (modelo Claude Opus 5.5, Anthropic), rodando no terminal com acesso ao
GitHub da organização.

**Como foi usado:** a partir do quadro do projeto e do material do curso (hands-on 2, 3, 4, 7 e 8 e da
página de bottlenecks), pedi para a IA implementar as minhas tarefas. A IA gerou o código, rodou os
testes e a plataforma localmente, e abriu os repositórios/PRs. O que eu revisei e alterei está registrado
abaixo.

| Parte | Feito com IA? | Observações |
|---|---|---|
| Gateway (`pna26/gateway-service`) | Sim — código gerado pela IA a partir do hands-on 3 | Mudanças em relação ao hands-on (ordem do filtro, 401/503, `AuthClient` com timeout) estão justificadas em [Gateway](servicos/gateway.md). 20 testes automatizados. |
| Cache do token no Redis | Sim | A escolha de cachear o `/auth/solve` no gateway e as regras de TTL/chave estão em [Cache](bottlenecks/cache.md). Testado com o Redis ligado e desligado. |
| Nginx (balanceamento) | Sim — a partir do hands-on 7 | Acrescentado `resolve` (escala sem reload) e bloqueio do actuator. |
| Pipeline de CI/CD reutilizável | Sim | Passos de Trivy simulados localmente antes de publicar. |
| Varredura de vulnerabilidades | Sim | As correções do Dockerfile e do manifesto k8s vieram dos próprios achados do Trivy. |
| `compose.yaml`, scripts e manifestos k8s do `platform` | Sim | Manifestos validados com Trivy e `nginx -t`; **ainda não testados num cluster** (o EKS não estava pronto). |
| Esta documentação (estrutura e textos das minhas partes) | Sim | Baseada no template do professor. |
| Medições (balanceamento, cache) | Executadas pela IA na minha máquina | Os números são os que saíram dos comandos mostrados nas páginas. |

**O que eu (Leonardo) fiz sem IA:** _preencher_ — por exemplo: revisão do código, decisões de contrato com
o grupo, configuração da AWS/secrets junto com o Nicolas, gravação do vídeo.

**Onde a IA errou e foi corrigido:**

- O primeiro benchmark com/sem cache saiu inválido: a variável `TOKEN_CACHE_ENABLED` não estava sendo
  repassada pelo compose para o gateway, então as duas rodadas foram com cache. Foi corrigido e medido de
  novo; a conclusão honesta é que localmente a latência fica igual e o ganho é tirar carga do Auth.
- O Trivy aborta quando o `--ignorefile` aponta para um arquivo que não existe: o pipeline passou a só
  usar o `.trivyignore` quando ele existe (os repositórios do Account/Auth não têm).
- O `WebClient.Builder` não vem mais automático no Spring Boot 4 sem o `spring-boot-starter-webclient`
  (o teste de integração pegou isso).

## Nicolas

_A preencher pelo Nicolas: Auth, Account, AWS, EKS e mensageria — o que foi feito com IA (ferramenta,
partes, revisão) e o que foi feito sem._

| Parte | Feito com IA? | Observações |
|---|---|---|
| | | |

## Gabriel

_A preencher pelo Gabriel: Exchange, testes de carga, observabilidade e custos/SLA._

| Parte | Feito com IA? | Observações |
|---|---|---|
| | | |
