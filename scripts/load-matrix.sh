#!/usr/bin/env bash
# Roda a bateria de testes de carga da documentação (docs/devops/load-testing.md)
# e junta tudo em load/results/RESULTS.md. Leva ~20 min. Pré-requisito:
#   ./scripts/build.sh && docker compose up -d --build
#
# Cada experimento muda UMA variável e mantém o resto igual:
#   1. cache do token     TOKEN_CACHE_ENABLED=true x false   (cenário auth)
#   2. réplicas           GATEWAY_REPLICAS=1 x 2 x 4         (cenário auth, perfil stress)
#   3. cache da cotação   EXCHANGE_CACHE_TTL=30 x 0          (cenário exchange, poucos VUs:
#                         sem cache cada requisição vai para a API externa e não queremos
#                         martelar um serviço de terceiros)
#   4. uso real           mixed, perfil load, configuração padrão
#
#   ONLY="1 3" ./scripts/load-matrix.sh     # roda só alguns experimentos
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT=load/results/RESULTS.md
ONLY="${ONLY:-1 2 3 4}"
VUS="${VUS:-50}"

want() { [[ " $ONLY " == *" $1 "* ]]; }

# sobe a plataforma com a configuração do experimento e espera ficar saudável
configure() {
  echo ">> configurando: $*"
  env "$@" docker compose up -d --wait --wait-timeout 300 gateway exchange >/dev/null
  # cache do token frio em todo experimento (é só cache, pode apagar)
  docker compose exec -T redis redis-cli FLUSHDB >/dev/null
  # o gateway (Spring) leva alguns segundos para subir depois do "running"
  for _ in $(seq 1 60); do
    curl -sf -o /dev/null "http://localhost:${LB_PORT:-8080}/health-check" && break
    sleep 2
  done
  # o Nginx re-resolve o DNS das réplicas a cada 10 s
  sleep 12
}

run() { # run NAME SCENARIO PROFILE VUS [DURATION]
  NAME="$1" SCENARIO="$2" PROFILE="$3" VUS="$4" DURATION="${5:-1m}" ./scripts/load-test.sh || \
    echo "aviso - $1 estourou algum threshold (ver o resumo acima)"
}

row() { cat "load/results/$1.row.md" 2>/dev/null || echo "| $1 | (falhou) |"; }

DEFAULTS=(TOKEN_CACHE_ENABLED=true GATEWAY_REPLICAS=2 EXCHANGE_CACHE_TTL=30)

if want 1; then
  configure "${DEFAULTS[@]/TOKEN_CACHE_ENABLED=true/TOKEN_CACHE_ENABLED=false}"
  run token-cache-off auth load "$VUS"
  configure "${DEFAULTS[@]}"
  run token-cache-on auth load "$VUS"
fi

if want 2; then
  for n in 1 2 4; do
    configure TOKEN_CACHE_ENABLED=true GATEWAY_REPLICAS=$n EXCHANGE_CACHE_TTL=30
    run "replicas-$n" auth stress "$VUS"
  done
fi

if want 3; then
  configure "${DEFAULTS[@]/EXCHANGE_CACHE_TTL=30/EXCHANGE_CACHE_TTL=0}"
  run exchange-cache-off exchange load 10 30s
  configure "${DEFAULTS[@]}"
  run exchange-cache-on exchange load 10 30s
fi

if want 4; then
  configure "${DEFAULTS[@]}"
  run mixed-load mixed load "$VUS"
fi

# volta para a configuração padrão
configure "${DEFAULTS[@]}"

{
  echo "# Resultados do teste de carga"
  echo
  echo "- Data: $(date '+%Y-%m-%d %H:%M')"
  echo "- Máquina: $(docker info --format '{{.OperatingSystem}}, {{.NCPU}} CPUs, {{.MemTotal}} bytes de RAM para o Docker' 2>/dev/null)"
  echo "- k6, Nginx, gateway e serviços na **mesma máquina** (o k6 disputa CPU com a plataforma)"
  echo
  echo "Latências em ms, só respostas esperadas (2xx/3xx). Erros = % de respostas 4xx/5xx/timeout."
  echo
  echo "| Execução | Cenário | Perfil | VUs máx. | Requisições | req/s | p50 | p95 | p99 | Erros |"
  echo "|---|---|---|---:|---:|---:|---:|---:|---:|---:|"
  for n in token-cache-off token-cache-on replicas-1 replicas-2 replicas-4 exchange-cache-off exchange-cache-on mixed-load; do
    [ -f "load/results/$n.row.md" ] && row "$n"
  done
} > "$OUT"

echo ">> tabela em $OUT"
cat "$OUT"
