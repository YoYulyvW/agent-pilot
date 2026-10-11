/**
 * 中继版客户端：替换 feishu-client.js，把 Cuckoo-Code 的对话流推送到 AgentPilot 中继（手机）。
 *
 * 接口与 feishu-client.js 完全一致（connect/disconnect/sendText/sendMarkdown/sendCard/
 * sendLocalFile/getStatus/readConfig/listChats），ipc-feishu.js 无需任何改动。
 *
 * 配置：复用 feishu.json，新增字段：
 *   relayUrl        中继地址，如 http://192.168.2.250:8861
 *   targetOpenId    复用为手机 deviceId
 *   agentName       智能体名（默认 Cuckoo-Code）
 */
import fs from 'node:fs';
import path from 'node:path';
import { readConfig } from './config.js';

let relayUrl = '';
let targetDeviceId = '';
let agentName = 'Cuckoo-Code';
let deviceId = '';
let token = '';
let polling = false;
let callbacks = {};
let currentStatus = 'disconnected';
let statusDetail = '';

function setStatus(s, d) {
    currentStatus = s;
    statusDetail = d || '';
    try { callbacks.onStatusChange?.(s, statusDetail); } catch (_) { }
}

function getStatus() {
    return { status: currentStatus, detail: statusDetail };
}

function readRelayConfig() {
    const cfg = readConfig() || {};
    return {
        relayUrl: cfg.relayUrl || 'http://192.168.2.250:8861',
        targetDeviceId: cfg.targetOpenId || cfg.targetDeviceId || '',
        agentName: cfg.agentName || 'Cuckoo-Code',
        enabled: cfg.enabled === true,
    };
}

// ---- deviceId 持久化（同一智能体永远同一会话）----
function loadDeviceId() {
    const f = path.join(process.env.APPDATA || process.env.HOME || '.', 'cuckoo-relay-device-id');
    try {
        const v = fs.readFileSync(f, 'utf8').trim();
        if (v) return v;
    } catch (_) { }
    const id = 'agent-' + Math.random().toString(16).slice(2, 18);
    try { fs.writeFileSync(f, id, 'utf8'); } catch (_) { }
    return id;
}

// ---- HTTP ----
async function api(pathname, method = 'GET', body = null, auth = false) {
    const headers = { 'Content-Type': 'application/json' };
    if (auth && token) headers['Authorization'] = 'Bearer ' + token;
    const res = await fetch(relayUrl + pathname, {
        method, headers, body: body ? JSON.stringify(body) : undefined,
    });
    const txt = await res.text();
    try { return JSON.parse(txt); } catch { return {}; }
}

async function register() {
    const resp = await api('/relay/register', 'POST', {
        deviceId, deviceName: agentName, platform: 'agent', pushMode: 'poll', version: '1.0.0',
    }, false);
    if (resp.ok && resp.relayToken) { token = resp.relayToken; return true; }
    return false;
}

async function poll(timeout = 25) {
    const resp = await api('/relay/poll?timeout=' + timeout, 'GET', null, true);
    return (resp.ok && resp.messages) ? resp.messages : [];
}

async function ack(ids) {
    try { await api('/relay/ack', 'POST', { messageIds: ids }, true); } catch (_) { }
}

async function send(payload) {
    const resp = await api('/relay/send', 'POST', {
        to: targetDeviceId, type: 'agent', ttlHours: 24, payload,
    }, true);
    return resp.ok ? { success: true } : { success: false, error: resp.error || 'send failed' };
}

// ---- 长轮询主循环 ----
async function pollLoop() {
    while (polling) {
        try {
            const msgs = await poll(25);
            const ackIds = [];
            for (const m of msgs) {
                ackIds.push(m.messageId);
                if (m.type === 'agent') {
                    const text = (m.payload && m.payload.text) || '';
                    if (callbacks.onUserMessage) {
                        try { callbacks.onUserMessage(text, m.from || '', []); } catch (_) { }
                    }
                }
            }
            if (ackIds.length) await ack(ackIds);
        } catch (e) {
            if (String(e).includes('401') || String(e).includes('unauthorized')) {
                token = '';
                try { await register(); } catch (_) { }
            }
            await new Promise(r => setTimeout(r, 2000));
        }
    }
}

async function connect(opts = {}) {
    callbacks = opts || {};
    const c = readRelayConfig();
    relayUrl = c.relayUrl;
    targetDeviceId = c.targetDeviceId;
    agentName = c.agentName;
    deviceId = loadDeviceId();
    if (!c.enabled) { setStatus('disconnected', '未启用'); return; }
    setStatus('connecting', relayUrl);
    if (!(await register())) { setStatus('error', '注册失败：' + relayUrl); return; }
    setStatus('connected', relayUrl);
    polling = true;
    pollLoop();
}

function disconnect(silent) {
    polling = false;
    setStatus('disconnected');
}

// ---- 发送（接口对齐 feishu-client.js）----
async function sendText(text, chatId) {
    return await send({ v: 1, kind: 'text', text, agentId: deviceId, agentName, ts: Date.now() / 1000 });
}

async function sendMarkdown(md, chatId) {
    return await send({ v: 1, kind: 'text', text: md, agentId: deviceId, agentName, ts: Date.now() / 1000 });
}

function parseToolLine(text) {
    let state = 'running';
    if (/✅/.test(text)) state = 'done';
    else if (/❌/.test(text)) state = 'failed';
    const name = String(text || '')
        .replace(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/gu, '')
        .replace(/\*\*/g, '')
        .replace(/—.*$/, '')
        .trim() || '工具';
    return { name: name.slice(0, 40), state, output: '' };
}

function extractTools(elements) {
    const tools = [];
    for (const el of elements || []) {
        if (!el) continue;
        if (el.tag === 'markdown') {
            tools.push(parseToolLine(el.content));
        } else if (el.tag === 'collapsible_panel') {
            const title = (el.header && el.header.title && el.header.title.content) || '';
            const t = parseToolLine(title);
            const bodyEl = (el.elements || [])[0];
            t.output = (bodyEl && bodyEl.content) || '';
            tools.push(t);
        }
    }
    return tools;
}

async function sendCard(elements, chatId) {
    const tools = extractTools(elements);
    if (tools.length === 0) return { success: true };
    for (let i = 0; i < tools.length; i++) {
        const t = tools[i];
        const mid = 'tool-' + Date.now() + '-' + i;
        const text = t.state === 'running' ? '执行中…'
            : (t.output || (t.state === 'done' ? '完成' : '失败'));
        const r = await send({
            v: 1, kind: 'tool', messageId: mid, toolName: t.name,
            toolState: t.state, text, agentId: deviceId, agentName, ts: Date.now() / 1000,
        });
        if (!r.success) return r;
    }
    return { success: true };
}

async function sendLocalFile(filePath, chatId, text) {
    try {
        if (text) await sendText(text, chatId);
        const buf = fs.readFileSync(filePath);
        const name = path.basename(filePath);
        const kind = /\.(png|jpe?g|gif|webp|bmp|ico)$/i.test(name) ? 'image' : 'file';
        const att = {
            id: 'att-' + Date.now(), kind, name,
            mime: 'application/octet-stream', size: buf.length, data: buf.toString('base64'),
        };
        return await send({
            v: 1, kind: 'attachment', text: '', attachments: [att],
            agentId: deviceId, agentName, ts: Date.now() / 1000,
        });
    } catch (e) {
        return { success: false, error: e.message };
    }
}

async function listChats() {
    return [{ chatId: targetDeviceId, name: '手机' }];
}

export { connect, disconnect, sendText, sendMarkdown, sendCard, sendLocalFile, getStatus, readConfig, listChats };
