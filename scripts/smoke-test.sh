#!/usr/bin/env bash
# Teste ponta a ponta da plataforma rodando (compose local ou EKS):
#   ./scripts/smoke-test.sh                       # http://localhost:8080
#   BASE_URL=http://<elb-da-aws> ./scripts/smoke-test.sh
# Confere o contrato da API, o 401 sem token, o header id-account forjado,
# o balanceamento entre réplicas e o cache do token no Redis.
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
EMAIL="smoke+$(date +%s)$RANDOM@store.test"
PASS="senha-forte-123"
fail() { echo "FALHOU: $*" >&2; exit 1; }
ok() { echo "ok  - $*"; }
status() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

echo ">> esperando o gateway em $BASE_URL"
for i in $(seq 1 60); do
  [ "$(status "$BASE_URL/health-check")" = "200" ] && break
  sleep 2
  [ "$i" = 60 ] && fail "gateway não respondeu"
done
ok "gateway no ar"

# o auth/account podem demorar um pouco mais que o gateway para subir
for i in $(seq 1 60); do
  code=$(status -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' \
    -d "{\"name\":\"Smoke Test\",\"email\":\"$EMAIL\",\"password\":\"$PASS\"}")
  case "$code" in 200|201) break ;; esac
  sleep 3
  [ "$i" = 60 ] && fail "POST /auth/register respondeu $code"
done
ok "POST /auth/register ($code)"

headers=$(curl -s -D - -o /dev/null -X POST "$BASE_URL/auth/login" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}")
echo "$headers" | head -1 | grep -q ' 200' || fail "POST /auth/login: $(echo "$headers" | head -1)"
TOKEN=$(echo "$headers" | tr -d '\r' | sed -n 's/^[Ss]et-[Cc]ookie: __store_jwt_token=\([^;]*\).*/\1/p' | head -1)
[ -n "$TOKEN" ] || fail "login não devolveu o cookie __store_jwt_token"
echo "$headers" | grep -qi 'set-cookie:.*HttpOnly' || fail "cookie sem HttpOnly"
ok "POST /auth/login devolveu o cookie __store_jwt_token (HttpOnly)"

COOKIE="Cookie: __store_jwt_token=$TOKEN"

[ "$(status "$BASE_URL/accounts")" = "401" ] || fail "GET /accounts sem token deveria ser 401"
ok "GET /accounts sem token -> 401"

[ "$(status -H 'id-account: forjado' "$BASE_URL/accounts")" = "401" ] || fail "id-account forjado abriu a rota"
ok "header id-account forjado sem token -> 401"

[ "$(status -H "Cookie: __store_jwt_token=token.invalido.x" "$BASE_URL/accounts")" = "401" ] || fail "token inválido deveria ser 401"
ok "token inválido -> 401"

me=$(curl -s -H "$COOKIE" "$BASE_URL/auth/me")
echo "$me" | grep -q "$EMAIL" || fail "GET /auth/me: $me"
ok "GET /auth/me devolve a conta logada"

ID=$(echo "$me" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
[ "$(status -H "$COOKIE" "$BASE_URL/accounts")" = "200" ] || fail "GET /accounts com token"
ok "GET /accounts com token -> 200"
[ "$(status -H "$COOKIE" "$BASE_URL/accounts/$ID")" = "200" ] || fail "GET /accounts/{id}"
ok "GET /accounts/{id} -> 200"

hosts=$(for i in $(seq 1 12); do curl -s "$BASE_URL/health-check"; echo; done | sort -u | wc -l | tr -d ' ')
if [ "$hosts" -ge 2 ]; then ok "balanceamento: $hosts réplicas diferentes do gateway responderam"
else echo "aviso - só 1 réplica do gateway respondeu (GATEWAY_REPLICAS=1?)"; fi

if command -v docker >/dev/null && docker compose ps redis >/dev/null 2>&1; then
  keys=$(docker compose exec -T redis redis-cli --scan --pattern 'gateway:token:*' | wc -l | tr -d ' ')
  [ "$keys" -ge 1 ] || fail "nenhum token em cache no redis"
  ok "cache: $keys token(s) em cache no Redis (chave = SHA-256 do JWT)"
fi

[ "$(status "$BASE_URL/gateway/actuator/prometheus")" = "404" ] || fail "métricas não deveriam ser públicas"
ok "/gateway/actuator/prometheus bloqueado no lb"

logout=$(curl -s -D - -o /dev/null "$BASE_URL/auth/logout")
echo "$logout" | grep -qi 'set-cookie: __store_jwt_token=;' || fail "logout não limpou o cookie"
ok "GET /auth/logout limpa o cookie"

echo ">> smoke test passou"
