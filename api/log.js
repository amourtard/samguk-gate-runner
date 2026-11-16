// POST /api/log : 게임이 보낸 플레이 사건 묶음을 저장한다.
import { toRows, insertRows } from '../lib/store.js';

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'POST만 받습니다' });
    return;
  }
  let body = req.body;
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch { body = null; }
  }
  const rows = toRows(body, req.headers['x-vercel-ip-country']);
  if (rows === null) {
    res.status(400).json({ error: '형식이 맞지 않습니다' });
    return;
  }
  try {
    await insertRows(rows);
    res.status(200).json({ saved: rows.length });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: '저장하지 못했습니다' });
  }
}
