#!/usr/bin/env bash
# Roda um teste de carga (k6, via Docker) contra a plataforma.
#
#   ./scripts/load-test.sh                               # cenário mixed, perfil load, 50 VUs
#   SCENARIO=auth PROFILE=stress VUS=50 ./scripts/load-test.sh
#   BASE_URL=http://<elb-da-aws> ./scripts/load-test.sh  # contra o EKS
#
# Sem BASE_URL, o k6 entra na rede do compose e chama o lb por dentro (http://lb),
# e manda as métricas para o Prometheus do compose (aparecem no Grafana, linha
# "Teste de carga (k6)"). Resultados em load/results/<NAME>.json e .row.md.
# Variáveis aceitas: ver o cabeçalho de load/store.js.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

K6_IMAGE="grafana/k6:1.3.0"
SCENARIO="${SCENARIO:-mixed}"
PROFILE="${PROFILE:-load}"
NAME="${NAME:-$SCENARIO-$PROFILE}"
mkdir -p load/results
# o container do k6 roda como usuário sem privilégio: precisa poder gravar o resultado
chmod a+w load/results 2>/dev/null || true

ARGS=(run --rm -i
  -v "$ROOT/load:/scripts:ro"
  -v "$ROOT/load/results:/results"
  -e SCENARIO="$SCENARIO" -e PROFILE="$PROFILE" -e NAME="$NAME"
  -e VUS="${VUS:-50}" -e DURATION="${DURATION:-1m}" -e USERS="${USERS:-20}")
[ -n "${THINK:-}" ] && ARGS+=(-e THINK="$THINK")
K6_ARGS=(run)

if [ -z "${BASE_URL:-}" ]; then
  NETWORK="$(docker compose ps -q lb | xargs -r docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null || true)"
  [ -n "$NETWORK" ] || { echo "a plataforma não está no ar: docker compose up -d --build" >&2; exit 1; }
  ARGS+=(--network "$NETWORK" -e BASE_URL=http://lb)
  if [ -n "$(docker compose ps -q prometheus 2>/dev/null)" ]; then
    ARGS+=(-e K6_PROMETHEUS_RW_SERVER_URL=http://prometheus:9090/api/v1/write
           -e "K6_PROMETHEUS_RW_TREND_STATS=p(95),p(99),avg,max"
           -e K6_PROMETHEUS_RW_PUSH_INTERVAL=5s)
    K6_ARGS+=(-o experimental-prometheus-rw)
  fi
  TARGET="http://lb (rede $NETWORK)"
else
  ARGS+=(-e BASE_URL="$BASE_URL")
  TARGET="$BASE_URL"
fi

echo ">> k6: cenário=$SCENARIO perfil=$PROFILE VUs=${VUS:-50} alvo=$TARGET"
# MSYS_NO_PATHCONV: no Git Bash (Windows) evita converter /scripts em C:/Program Files/Git/scripts
MSYS_NO_PATHCONV=1 docker "${ARGS[@]}" "$K6_IMAGE" "${K6_ARGS[@]}" /scripts/store.js
