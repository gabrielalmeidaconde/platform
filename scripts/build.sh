#!/usr/bin/env bash
# Compila tudo na ordem certa: primeiro as interfaces (mvn install, para os
# serviços acharem store:account e store:auth no ~/.m2), depois os serviços
# (mvn package gera o target/*.jar que os Dockerfiles copiam).
# Também cria o .env com um JWT_SECRET_KEY aleatório se ele ainda não existir.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -f api/gateway-service/pom.xml ]; then
  echo ">> baixando os submódulos"
  git submodule update --init --recursive
fi

MVN_ARGS=(-B -q -DskipTests)

for lib in account auth; do
  echo ">> mvn install  api/$lib"
  (cd "api/$lib" && mvn "${MVN_ARGS[@]}" install)
done

for svc in account-service auth-service gateway-service; do
  echo ">> mvn package  api/$svc"
  (cd "api/$svc" && mvn "${MVN_ARGS[@]}" clean package)
done

if [ ! -f .env ]; then
  echo ">> criando .env com um JWT_SECRET_KEY aleatório"
  sed "s|^JWT_SECRET_KEY=.*|JWT_SECRET_KEY=$(openssl rand -base64 32)|" .env.example > .env
fi

echo ">> pronto. Agora: docker compose up -d --build"
