'use strict';

// Runs only against the integration harness's synthetic, in-memory library.
const { spawn } = require('node:child_process');
const readline = require('node:readline');
const assert = require('node:assert/strict');
const nativeBridge = process.env.JOTLEY_NATIVE_BRIDGE_BINARY;
const bridge = spawn(nativeBridge || process.execPath, nativeBridge ? ['--mcp-stdio'] : [process.env.JOTLEY_BRIDGE_SCRIPT], {
  env: process.env, stdio: ['pipe', 'pipe', 'pipe']
});
const pending = new Map();
let nextID = 0;
let diagnostics = '';
bridge.stderr.on('data', chunk => { diagnostics += chunk; });
readline.createInterface({ input: bridge.stdout }).on('line', line => {
  const message = JSON.parse(line);
  const request = pending.get(message.id);
  assert.ok(request, 'Unexpected or duplicate response');
  pending.delete(message.id);
  clearTimeout(request.timer);
  if (message.error) request.reject(new Error(message.error.message));
  else request.resolve(message.result);
});
bridge.on('exit', () => {
  for (const request of pending.values()) {
    clearTimeout(request.timer);
    request.reject(new Error('Bridge exited before responding'));
  }
});

function call(method, params) {
  return new Promise((resolve, reject) => {
    const id = ++nextID;
    const timer = setTimeout(() => reject(new Error('Bridge request timed out')), 15000);
    pending.set(id, { resolve, reject, timer });
    bridge.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
  });
}
function tool(name, args) { return call('tools/call', { name, arguments: args }); }
function json(result) {
  assert.notEqual(result.isError, true, 'Tool failed');
  return JSON.parse(result.content.filter(item => item.type === 'text').map(item => item.text).join('\n'));
}

async function main() {
  const initialized = await call('initialize', {
    protocolVersion: '2025-11-25', capabilities: {},
    clientInfo: { name: 'Jotley Claude extension test', version: '1.0.0' }
  });
  assert.equal(initialized.serverInfo.name, 'Jotley');
  assert.match(initialized.instructions, /Code tab/);
  assert.match(initialized.instructions, /Codex/);
  bridge.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');
  const tools = await call('tools/list', {});
  assert.equal(tools.tools.length, 25);
  const found = json(await tool('search_notes', { query: 'Maya' }));
  assert.ok(found.notes.length > 0);
  if (process.env.JOTLEY_BRIDGE_WRITE === '1') {
    const created = json(await tool('create_note', { title: 'Desktop extension test', summary: '- [ ] Review onboarding', date: '2026-11-10T12:30:00Z' }));
    const read = json(await tool('read_note', { id: created.id }));
    assert.match(JSON.stringify(read), /Review onboarding/);
    const updated = json(await tool('update_note', { id: created.id, expected_revision: read.revision, changes: { title: 'Desktop extension verified', description: 'Changed through the real bridge' } }));
    assert.equal(updated.title, 'Desktop extension verified');
    const deleted = json(await tool('delete_note', { id: created.id, expected_revision: updated.revision }));
    assert.equal(deleted.deleted, true);
  } else {
    const denied = await tool('create_note', { title: 'Must not be created' });
    assert.equal(denied.isError, true);
  }
  assert.equal(diagnostics, '');
  console.log('PASS: ' + (nativeBridge ? 'Bundled native STDIO' : 'Claude extension') + ' bridge handshake, 25 tools, reading and ' + (process.env.JOTLEY_BRIDGE_WRITE === '1' ? 'create/edit/delete' : 'read-only enforcement'));
}
main().catch(error => { console.error(error.message); process.exitCode = 1; }).finally(() => {
  bridge.stdin.end();
  bridge.kill();
});
