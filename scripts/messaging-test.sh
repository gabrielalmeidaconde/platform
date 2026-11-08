#!/usr/bin/env bash
# Teste da mensageria no compose local (docs/bottlenecks/messaging.md), com os
# experimentos do Hands-on 7 do curso:
#   1. caminho feliz: cadastro -> outbox -> Kafka -> notification -> e-mail no Mailpit
#   2. notification fora: o cadastro continua respondendo, o lag cresce e depois drena
#   3. Kafka fora: o cadastro continua respondendo, os eventos esperam no outbox
#   4. reprocessamento (reset dos offsets): nenhum e-mail duplicado
#   5. mensagem envenenada: vai para a DLT e a partição continua andando
# Pré-requisito: docker compose up -d --build (stack inteira no ar).
#   ./scripts/messaging-test.sh
set -euo pipefail
# Git Bash (Windows): não converter /opt/... em caminho do Windows no docker exec
export MSYS_NO_PATHCONV=1

BASE_URL="${BASE_URL:-http://localhost:8080}"
MAILPIT="${MAILPIT:-http://127.0.0.1:${MAILPIT_PORT:-8025}}"
N="${N:-20}"
RUN="msg$(date +%s)$RANDOM"
PASS="senha-forte-123"

fail() { echo "FALHOU: $*" >&2; exit 1; }
ok() { echo "ok  - $*"; }

kafka() { docker compose exec -T kafka /opt/kafka/bin/"$@"; }
sql() { docker compose exec -T db psql -U "${DB_USER:-store}" -d "${DB_NAME:-store}" -tAc "$1"; }

# e-mails deste teste no Mailpit (busca pelo marcador $RUN no destinatário)
mails() {
  curl -s "$MAILPIT/api/v1/search?query=to:$1&limit=1000" | sed -n 's/.*"messages_count":\([0-9]*\).*/\1/p'
}

# soma do lag do grupo notification no tópico account-events
lag() {
  kafka kafka-consumer-groups.sh --bootstrap-server kafka:9092 --describe --group notification 2>/dev/null \
    | awk '$2=="account-events" && $6 ~ /^[0-9]+$/ {s+=$6} END {print s+0}'
}

# cadastra N contas com o prefixo dado; devolve a latência média em ms
register() {
  local prefix=$1 total=0 code t
  for i in $(seq 1 "$N"); do
    read -r code t < <(curl -s -o /dev/null -w '%{http_code} %{time_total}\n' -X POST "$BASE_URL/auth/register" \
      -H 'Content-Type: application/json' \
      -d "{\"name\":\"Teste $i\",\"email\":\"$prefix-$i@store.test\",\"password\":\"$PASS\"}")
    case "$code" in 200|201) ;; *) fail "POST /auth/register ($prefix-$i) respondeu $code" ;; esac
    total=$(awk -v a="$total" -v b="$t" 'BEGIN {print a + b}')
  done
  awk -v t="$total" -v n="$N" 'BEGIN {printf "%.0f", t * 1000 / n}'
}

wait_for() { # wait_for <descrição> <segundos> <comando...>
  local what=$1 secs=$2; shift 2
  for _ in $(seq 1 "$secs"); do
    if "$@"; then return 0; fi
    sleep 1
  done
  fail "$what (esperou ${secs}s)"
}

mails_eq() { [ "$(mails "$1")" = "$2" ]; }
lag_zero() { [ "$(lag)" = "0" ]; }

echo ">> 1. caminho feliz ($N cadastros)"
ms=$(register "$RUN-a")
wait_for "e-mails do caminho feliz" 60 mails_eq "$RUN-a" "$N"
ok "$N cadastros (média ${ms} ms) -> $N e-mails de boas-vindas no Mailpit"

echo ">> 2. notification fora"
docker compose stop notification >/dev/null 2>&1
ms=$(register "$RUN-b")
ok "com o notification parado o cadastro continua respondendo (média ${ms} ms)"
wait_for "lag do notification" 30 bash -c "[ \"\$(docker compose exec -T kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server kafka:9092 --describe --group notification 2>/dev/null | awk '\$2==\"account-events\" && \$6 ~ /^[0-9]+\$/ {s+=\$6} END {print s+0}')\" -ge $N ]"
ok "lag do grupo notification: $(lag) mensagem(ns) esperando no Kafka"
[ "$(mails "$RUN-b")" = "0" ] || fail "chegou e-mail com o notification parado"
start=$(date +%s)
docker compose start notification >/dev/null 2>&1
wait_for "drenagem do backlog" 120 mails_eq "$RUN-b" "$N"
ok "notification de volta: backlog drenado em $(( $(date +%s) - start )) s (inclui subir a JVM), $N e-mails"

echo ">> 3. Kafka fora"
docker compose stop kafka >/dev/null 2>&1
ms=$(register "$RUN-c")
pending=$(sql "SELECT count(*) FROM accounts.outbox WHERE published_at IS NULL")
[ "$pending" -ge "$N" ] || fail "esperava >= $N eventos pendentes no outbox, achou $pending"
ok "com o Kafka parado o cadastro continua respondendo (média ${ms} ms); $pending evento(s) esperando no outbox"
docker compose start kafka >/dev/null 2>&1
wait_for "outbox publicado" 180 bash -c "[ \"\$(docker compose exec -T db psql -U ${DB_USER:-store} -d ${DB_NAME:-store} -tAc 'SELECT count(*) FROM accounts.outbox WHERE published_at IS NULL')\" = 0 ]"
wait_for "e-mails depois da volta do Kafka" 180 mails_eq "$RUN-c" "$N"
ok "Kafka de volta: o relay publicou tudo, $N e-mails, nenhum evento perdido"

echo ">> 4. reprocessamento: reset dos offsets para o início"
before=$(sql "SELECT count(*) FROM notification.notifications")
docker compose stop notification >/dev/null 2>&1
kafka kafka-consumer-groups.sh --bootstrap-server kafka:9092 --group notification \
  --topic account-events --reset-offsets --to-earliest --execute >/dev/null
docker compose start notification >/dev/null 2>&1
wait_for "releitura do tópico" 120 lag_zero
after=$(sql "SELECT count(*) FROM notification.notifications")
[ "$before" = "$after" ] || fail "reprocessar enviou $(( after - before )) e-mail(s) duplicado(s)"
for p in a b c; do mails_eq "$RUN-$p" "$N" || fail "duplicata no Mailpit ($RUN-$p)"; done
ok "tópico relido do início: 0 e-mails novos ($after enviados no total), duplicatas ignoradas"

echo ">> 5. mensagem envenenada"
dead_before=$(sql "SELECT count(*) FROM notification.dead_letters")
printf 'poison-%s:isto nao e json\n' "$RUN" | kafka kafka-console-producer.sh --bootstrap-server kafka:9092 \
  --topic account-events --reader-property parse.key=true --reader-property key.separator=: >/dev/null
wait_for "dead letter" 60 bash -c "[ \"\$(docker compose exec -T db psql -U ${DB_USER:-store} -d ${DB_NAME:-store} -tAc 'SELECT count(*) FROM notification.dead_letters')\" -gt $dead_before ]"
reason=$(sql "SELECT reason FROM notification.dead_letters ORDER BY id DESC LIMIT 1")
ok "JSON inválido foi para account-events-dlt sem retry ($reason)"
ms=$(register "$RUN-d")
wait_for "e-mails depois da mensagem envenenada" 60 mails_eq "$RUN-d" "$N"
ok "a partição continuou andando: $N cadastros depois -> $N e-mails"

echo ">> teste de mensageria passou"
