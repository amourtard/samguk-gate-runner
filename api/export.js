// GET /api/export?token=...&after=0&limit=5000 : 모은 사건을 내려받는다. EXPORT_TOKEN이 맞아야 한다.
import { readRows } from '../lib/store.js';

const MAX_LIMIT = 5000;

export default async function handler(req, res) {
  const token = process.env.EXPORT_TOKEN;
  if (!token || req.query.token !== token) {
    res.status(401).json({ error: '토큰이 맞지 않습니다' });
    return;
  }
  const after = Number.parseInt(req.query.after ?? '0', 10) || 0;
  const limit = Math.min(Number.parseInt(req.query.limit ?? String(MAX_LIMIT), 10) || MAX_LIMIT, MAX_LIMIT);
  try {
    const rows = await readRows(after, limit);
    const next = rows.length === limit ? Number(rows[rows.length - 1].id) : null;
    res.status(200).json({ rows, next });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: '읽지 못했습니다' });
  }
}
