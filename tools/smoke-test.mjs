/**
 * DSH /api 协议冒烟测试（只读，无副作用）。
 *
 * 用 Node 模拟 DSH Mobile（Flutter）客户端将发出的请求，验证：
 * 1. 一元 RPC 信封格式（POST /api/<method>）
 * 2. host.describe / session.list / session.history 响应结构
 * 3. WS /api/events.mux 下行流订阅确认
 *
 * 用法：node tools/smoke-test.mjs [baseUrl]
 * 默认 http://127.0.0.1:3080
 */
import { randomUUID } from 'node:crypto';

const BASE = process.argv[2] ?? 'http://127.0.0.1:3080';

function assert(cond, msg) {
  if (!cond) {
    console.error(`✗ FAIL: ${msg}`);
    process.exitCode = 1;
    throw new Error(msg);
  }
  console.log(`✓ ${msg}`);
}

async function callUnary(method, payload) {
  const rpcId = randomUUID();
  const res = await fetch(`${BASE}/api/${method}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ type: 'client-request', rpcId, method, payload }),
  });
  assert(res.ok, `POST /api/${method} → HTTP ${res.status}`);
  const envelope = await res.json();
  assert(envelope.type === 'server-response', `envelope.type == server-response`);
  assert(envelope.rpcId === rpcId, `rpcId 回显一致`);
  assert(typeof envelope.result?.ok === 'boolean', `result.ok 存在`);
  if (!envelope.result.ok) {
    console.error(`  error: ${JSON.stringify(envelope.result.error)}`);
    throw new Error(`${method} failed`);
  }
  return envelope.result.value;
}

// 1. 握手
const describe = await callUnary('host.describe', {});
console.log(`  version=${describe.version} cwd=${describe.cwd}`);
assert(typeof describe.version === 'string' && typeof describe.cwd === 'string', 'host.describe 返回 version/cwd');

// 2. 会话列表
const list = await callUnary('session.list', {});
assert(Array.isArray(list.items), 'session.list 返回 items 数组');
console.log(`  共 ${list.items.length} 个会话`);
if (list.items.length > 0) {
  const first = list.items[0];
  for (const k of ['sessionId', 'updatedAt', 'running', 'blank']) {
    assert(first[k] !== undefined, `session 行包含 ${k}`);
  }
  console.log(`  首个会话: ${first.sessionId} running=${first.running} blank=${first.blank}`);

  // 3. 历史
  const hist = await callUnary('session.history', { sessionId: first.sessionId, maxMessages: 3 });
  assert(Array.isArray(hist.events), 'session.history 返回 events 数组');
  assert(typeof hist.hasMore === 'boolean', 'session.history 返回 hasMore');
  if (hist.events.length > 0) {
    const ev = hist.events[0].event ?? hist.events[0];
    console.log(`  最近事件: type=${ev.type} seq=${ev.seq} surfaceOp=${JSON.stringify(ev.surfaceOp)}`);
    assert(typeof ev.type === 'string' && typeof ev.seq === 'number', 'event 信封含 type/seq');
    assert('data' in ev, 'event 含 data');
    console.log(`  data 键: ${Object.keys(ev.data ?? {}).join(', ')}`);
  }

  // 4. WS mux 流订阅
  await new Promise((resolve, reject) => {
    const wsUrl = BASE.replace(/^http/, 'ws') + '/api/events.mux';
    const ws = new WebSocket(wsUrl);
    const timer = setTimeout(() => reject(new Error('WS 订阅 8s 超时')), 8000);
    ws.onmessage = (msg) => {
      const frame = JSON.parse(msg.data);
      if (frame.type === 'server-request' && frame.payload?.type === 'session/subscribed') {
        clearTimeout(timer);
        assert(frame.payload.sessionId === first.sessionId, 'session/subscribed 帧确认订阅');
        console.log(`  lastSeq=${frame.payload.lastSeq}`);
        ws.close();
        resolve();
      }
    };
    ws.onerror = (e) => {
      clearTimeout(timer);
      reject(new Error(`WS 错误: ${e.message ?? 'unknown'}`));
    };
  });
}

console.log('\n全部通过 ✅');
