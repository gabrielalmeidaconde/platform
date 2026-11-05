// Teste de carga da plataforma (k6). Rodar com ./scripts/load-test.sh.
//
// Variáveis:
//   BASE_URL  http://lb (dentro da rede do compose) ou o endereço do ELB
//   SCENARIO  auth | exchange | login | mixed           (padrão: mixed)
//   PROFILE   smoke | load | stress | spike              (padrão: load)
//   VUS       usuários virtuais no platô                 (padrão: 50)
//   DURATION  duração do platô                           (padrão: 1m)
//   USERS     contas criadas no setup e reutilizadas     (padrão: 20)
//   NAME      nome do resultado em load/results/          (padrão: SCENARIO-PROFILE)
//
// Cenários:
//   auth      GET /auth/me + GET /accounts/{id}: rota protegida -> gateway valida o
//             token (Redis ou Auth) -> serviço. Mede cache do token e balanceamento.
//   exchange  GET /exchange/USD/BRL (e EUR/BRL): mede o cache da cotação.
//   login     POST /auth/login: caminho caro (hash da senha + emissão do JWT).
//   mixed     80% leitura autenticada, 15% câmbio, 5% login (uso "real" da loja).

import http from 'k6/http';
import { check, sleep } from 'k6';
import exec from 'k6/execution';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.1.0/index.js';

const BASE_URL = __ENV.BASE_URL || 'http://lb';
const SCENARIO = __ENV.SCENARIO || 'mixed';
const PROFILE = __ENV.PROFILE || 'load';
const VUS = parseInt(__ENV.VUS || '50', 10);
const DURATION = __ENV.DURATION || '1m';
const USERS = parseInt(__ENV.USERS || '20', 10);
const NAME = __ENV.NAME || `${SCENARIO}-${PROFILE}`;
const PASSWORD = 'carga-senha-123';

const PROFILES = {
  // 1 usuário, só para ver se o script e a plataforma funcionam
  smoke: [
    { duration: '1s', target: 1 },
    { duration: '20s', target: 1 },
  ],
  // carga esperada: sobe, mantém o platô, desce
  load: [
    { duration: '20s', target: VUS },
    { duration: DURATION, target: VUS },
    { duration: '10s', target: 0 },
  ],
  // aumenta até achar o ponto de quebra (onde p95 ou erros estouram)
  stress: [
    { duration: '30s', target: VUS },
    { duration: '30s', target: VUS * 2 },
    { duration: '30s', target: VUS * 4 },
    { duration: '30s', target: VUS * 8 },
    { duration: '20s', target: 0 },
  ],
  // pico repentino (ex.: promoção): a plataforma se recupera?
  spike: [
    { duration: '10s', target: Math.max(1, Math.floor(VUS / 10)) },
    { duration: '5s', target: VUS * 4 },
    { duration: '30s', target: VUS * 4 },
    { duration: '5s', target: Math.max(1, Math.floor(VUS / 10)) },
    { duration: '30s', target: Math.max(1, Math.floor(VUS / 10)) },
    { duration: '5s', target: 0 },
  ],
};

export const options = {
  scenarios: {
    [SCENARIO]: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: PROFILES[PROFILE] || PROFILES.load,
      gracefulRampDown: '10s',
    },
  },
  // SLO do projeto (ver docs/devops/custos-sla.md): o k6 sai com código 99 se estourar.
  // Só conta a fase de teste (phase:test): o cadastro/login do setup() fica de fora.
  thresholds: {
    'http_req_failed{phase:test}': ['rate<0.01'],
    'http_req_duration{phase:test,expected_response:true}': ['p(95)<500', 'p(99)<1500'],
    'http_reqs{phase:test}': ['count>0'],
    checks: ['rate>0.99'],
  },
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  setupTimeout: '2m',
  tags: { testid: NAME },
};

const JSON_HEADERS = { 'Content-Type': 'application/json' };

// tag "phase": separa o setup() (cadastro/login das contas) da carga medida
const tags = (name, phase = 'test') => ({ name, phase });

function login(email, phase = 'test') {
  const res = http.post(`${BASE_URL}/auth/login`, JSON.stringify({ email, password: PASSWORD }), {
    headers: JSON_HEADERS,
    tags: tags('POST /auth/login', phase),
  });
  const cookie = res.cookies.__store_jwt_token;
  return cookie && cookie.length ? cookie[0].value : null;
}

// Cria USERS contas e faz login uma vez: os VUs reutilizam os tokens, como
// usuários reais navegando logados (é isso que o cache do token aproveita).
export function setup() {
  const run = `${Date.now()}`;
  const users = [];
  for (let i = 0; i < USERS; i++) {
    const email = `carga+${run}-${i}@store.test`;
    const reg = http.post(
      `${BASE_URL}/auth/register`,
      JSON.stringify({ name: `Carga ${i}`, email, password: PASSWORD }),
      { headers: JSON_HEADERS, tags: tags('setup', 'setup') },
    );
    if (reg.status !== 200 && reg.status !== 201) {
      exec.test.abort(`POST /auth/register respondeu ${reg.status}: ${reg.body}`);
    }
    const token = login(email, 'setup');
    if (!token) exec.test.abort('login não devolveu o cookie __store_jwt_token');
    const me = http.get(`${BASE_URL}/auth/me`, {
      headers: { Cookie: `__store_jwt_token=${token}` },
      tags: tags('setup', 'setup'),
    });
    users.push({ email, token, id: me.json('id') });
  }
  return { users };
}

function authRead(user) {
  const params = { headers: { Cookie: `__store_jwt_token=${user.token}` } };
  const me = http.get(`${BASE_URL}/auth/me`, Object.assign({ tags: tags('GET /auth/me') }, params));
  check(me, { 'auth/me 200': (r) => r.status === 200 });
  const acc = http.get(`${BASE_URL}/accounts/${user.id}`, Object.assign({ tags: tags('GET /accounts/{id}') }, params));
  check(acc, { 'accounts/{id} 200': (r) => r.status === 200 });
}

function exchange(user) {
  const pair = Math.random() < 0.8 ? 'USD/BRL' : 'EUR/BRL';
  const res = http.get(`${BASE_URL}/exchange/${pair}`, {
    headers: { Cookie: `__store_jwt_token=${user.token}` },
    tags: tags('GET /exchange/{from}/{to}'),
  });
  check(res, {
    'exchange 200': (r) => r.status === 200,
    'exchange sell >= buy': (r) => r.status === 200 && r.json('sell') >= r.json('buy'),
  });
}

function doLogin(user) {
  check(login(user.email), { 'login devolve token': (t) => !!t });
}

export default function (data) {
  const user = data.users[(exec.vu.idInTest - 1) % data.users.length];
  switch (SCENARIO) {
    case 'auth':
      authRead(user);
      break;
    case 'exchange':
      exchange(user);
      break;
    case 'login':
      doLogin(user);
      break;
    default: {
      const r = Math.random();
      if (r < 0.8) authRead(user);
      else if (r < 0.95) exchange(user);
      else doLogin(user);
    }
  }
  // "tempo de leitura" do usuário: sem isso cada VU vira um loop sem pausa
  sleep(0.5 + Math.random());
}

// Resumo no terminal + JSON completo + uma linha de tabela markdown, para o
// scripts/load-matrix.sh juntar os resultados em load/results/RESULTS.md.
export function handleSummary(data) {
  const m = data.metrics;
  // só a fase de teste (submétricas criadas pelos thresholds com {phase:test})
  const d = m['http_req_duration{phase:test,expected_response:true}'];
  const reqs = m['http_reqs{phase:test}'];
  const failed = m['http_req_failed{phase:test}'];
  const fmt = (v) => (v === undefined ? '-' : v.toFixed(0));
  const row =
    `| ${NAME} | ${SCENARIO} | ${PROFILE} | ${m.vus_max ? m.vus_max.values.max : '-'} ` +
    `| ${reqs.values.count} | ${reqs.values.rate.toFixed(1)} ` +
    `| ${fmt(d.values.med)} | ${fmt(d.values['p(95)'])} | ${fmt(d.values['p(99)'])} ` +
    `| ${(failed.values.rate * 100).toFixed(2)} % |\n`;
  return {
    stdout: textSummary(data, { indent: ' ', enableColors: true }),
    [`/results/${NAME}.json`]: JSON.stringify(data, null, 2),
    [`/results/${NAME}.row.md`]: row,
  };
}
