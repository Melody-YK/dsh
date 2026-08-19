/**
 * DSH Mobile 配套端口转发器：把局域网流量转发到本机 127.0.0.1 上的 DSH 实例。
 *
 * 背景：DSH 出于安全禁止 `--host 0.0.0.0`，只能绑定 127.0.0.1；
 * 手机要访问就需要一个用户级 TCP 转发（无需管理员权限）。
 *
 * 用法：
 *   node tools/port-forward.mjs [listenPort] [targetPort]
 *   默认：监听 0.0.0.0:3081 → 转发 127.0.0.1:3081
 *
 * 注意：首次监听时 Windows 防火墙会弹窗，请勾选"专用网络"允许。
 */
import net from 'node:net';

const LISTEN_PORT = Number(process.argv[2] ?? 3081);
const TARGET_PORT = Number(process.argv[3] ?? 3081);
const TARGET_HOST = '127.0.0.1';

const server = net.createServer((client) => {
  const upstream = net.connect({ host: TARGET_HOST, port: TARGET_PORT }, () => {
    client.pipe(upstream);
    upstream.pipe(client);
  });
  const cleanup = () => {
    client.destroy();
    upstream.destroy();
  };
  client.on('error', cleanup);
  upstream.on('error', cleanup);
  client.on('close', () => upstream.destroy());
  upstream.on('close', () => client.destroy());
});

server.listen(LISTEN_PORT, '0.0.0.0', () => {
  console.log(`[port-forward] 监听 0.0.0.0:${LISTEN_PORT} -> ${TARGET_HOST}:${TARGET_PORT}`);
  console.log(`手机访问: http://<电脑局域网IP>:${LISTEN_PORT}`);
});

server.on('error', (err) => {
  console.error(`[port-forward] 启动失败: ${err.message}`);
  process.exit(1);
});
