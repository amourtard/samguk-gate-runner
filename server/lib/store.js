// 플레이 기록 저장소. Postgres 표 하나(events)에 사건을 한 줄씩 쌓는다.
// 연결 주소는 Vercel 저장소 연동(Neon)이 넣어 주는 환경 변수에서 읽는다.
import pg from 'pg';

const MAX_EVENTS = 100;
const MAX_TEXT = 64;
const MAX_DATA_BYTES = 4000;

let pool = null;
let ready = null;

// 시험할 때 다른 연결(메모리 DB)을 끼워 넣는다.
export function usePool(other) {
  pool = other;
  ready = null;
}

function getPool() {
  if (pool === null) {
    const url = process.env.DATABASE_URL || process.env.POSTGRES_URL;
    if (!url) throw new Error('DATABASE_URL 환경 변수가 없습니다');
    pool = new pg.Pool({ connectionString: url, max: 1, ssl: { rejectUnauthorized: false } });
  }
  return pool;
}

// 표가 없으면 만든다(처음 한 번).
async function ensureTable() {
  if (ready === null) {
    ready = getPool().query(`
      CREATE TABLE IF NOT EXISTS events (
        id BIGSERIAL PRIMARY KEY,
        received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        client_time BIGINT,
        player TEXT NOT NULL,
        session TEXT NOT NULL,
        run TEXT,
        type TEXT NOT NULL,
        stage TEXT,
        hero TEXT,
        build TEXT,
        country TEXT,
        data JSONB
      )`);
  }
  return ready;
}

function text(value) {
  return typeof value === 'string' ? value.slice(0, MAX_TEXT) : '';
}

// 받은 묶음을 검사해 넣을 줄로 바꾼다. 형식이 틀리면 null.
export function toRows(body, country) {
  if (!body || typeof body !== 'object' || !Array.isArray(body.events)) return null;
  const player = text(body.player);
  const session = text(body.session);
  if (player === '' || session === '' || body.events.length === 0 || body.events.length > MAX_EVENTS) return null;
  const rows = [];
  for (const event of body.events) {
    if (!event || typeof event !== 'object' || text(event.type) === '') return null;
    const data = JSON.stringify(event.data ?? {});
    if (data.length > MAX_DATA_BYTES) return null;
    rows.push([
      Number.isFinite(event.time) ? Math.round(event.time) : null,
      player, session, text(event.run), text(event.type), text(event.stage), text(event.hero),
      text(body.build), text(country), data,
    ]);
  }
  return rows;
}

export async function insertRows(rows) {
  await ensureTable();
  const values = [];
  const groups = rows.map((row, i) => {
    values.push(...row);
    const base = i * row.length;
    return '(' + row.map((_, j) => '$' + (base + j + 1)).join(',') + ')';
  });
  await getPool().query(
    'INSERT INTO events (client_time, player, session, run, type, stage, hero, build, country, data) VALUES ' + groups.join(','),
    values);
}

// id가 after보다 큰 줄을 id 순서로 limit개까지 돌려준다.
export async function readRows(after, limit) {
  await ensureTable();
  const result = await getPool().query(
    'SELECT id, received_at, client_time, player, session, run, type, stage, hero, build, country, data FROM events WHERE id > $1 ORDER BY id LIMIT $2',
    [after, limit]);
  return result.rows;
}
