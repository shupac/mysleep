'use strict';
const $ = id => document.getElementById(id);
const state = { configured: false, demo: false, busy: false, podChecked: 0, history: [], report: null };
const duration = value => {
  if (value == null) return '—';
  const minutes = Math.round(value / 60);
  return minutes >= 60 ? `${Math.floor(minutes / 60)}h ${minutes % 60}m` : `${minutes}m`;
};
const number = (value, decimals = 0) => value == null ? '—' : Number(value).toFixed(decimals);
function notice(message, success = false) {
  $('notification').textContent = message || '';
  $('notification').hidden = !message;
  $('notification').classList.toggle('success', success);
}
function updateControls() {
  document.querySelectorAll('button').forEach(button => { button.disabled = state.busy; });
  const enabled = state.configured && !state.demo && !state.busy && Date.now() - state.podChecked < 60000;
  document.querySelectorAll('[data-control]').forEach(button => { button.disabled = !enabled; });
  $('refresh').disabled = state.busy || state.demo;
  $('pod-refresh').disabled = state.busy || state.demo || !state.configured;
  $('connection').textContent = state.busy ? 'Contacting Eight Sleep…' : state.demo ? 'Demo · no live requests' : state.configured ? 'Connected locally' : 'Not connected';
  $('connection').classList.toggle('live', state.configured && !state.demo);
  $('connect-panel').hidden = state.configured || state.demo;
  $('workspace').hidden = !state.configured && !state.demo;
}
function renderReport(envelope) {
  state.report = envelope;
  $('report-content').hidden = !envelope;
  $('empty-report').hidden = !!envelope;
  if (!envelope) { $('report-date').textContent = 'Waiting for your report'; return; }
  const r = envelope.report;
  $('report-date').textContent = new Date(`${r.date}T12:00:00Z`).toLocaleDateString(undefined, { month: 'long', day: 'numeric', year: 'numeric', timeZone: 'UTC' });
  $('score').textContent = number(r.score);
  $('total-sleep').textContent = duration(r.totalSleepSeconds);
  $('heart-rate').textContent = number(r.heartRateBpm);
  $('hrv').textContent = number(r.hrvMs, 1);
  $('deep-sleep').textContent = duration(r.stages.deep.seconds);
  $('rem-sleep').textContent = duration(r.stages.rem.seconds);
  const time = value => value ? new Date(value).toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit', timeZone: r.timezone }) : '—';
  $('bedtime-label').textContent = r.timesArePresence ? 'In bed' : 'Bedtime';
  $('wake-label').textContent = r.timesArePresence ? 'Out of bed' : 'Wake time';
  $('bedtime').textContent = time(r.bedtime);
  $('wake-time').textContent = time(r.wakeTime);
  const fetched = new Date(envelope.fetchedAt).toLocaleString();
  $('score-note').textContent = state.demo ? 'Synthetic demo report' : envelope.stale ? 'Saved report · live refresh failed' : 'Latest completed report';
  $('report-meta').textContent = `${state.demo ? 'Demo data' : envelope.stale ? 'Saved data' : 'Fetched'} · ${fetched} · ${r.timezone}${[['Sleep score', r.score], ['HR', r.heartRateBpm], ['HRV', r.hrvMs], ['Deep', r.stages.deep.seconds], ['REM', r.stages.rem.seconds]].some(([, value]) => value == null) ? ' · — means unavailable from Eight Sleep' : ''}`;
  if (envelope.warning) notice(envelope.warning);
}
function renderDiagnostics() {
  const list = $('diagnostic-list'); list.replaceChildren();
  const count = state.history.reduce((sum, entry) => sum + entry.requests.length, 0);
  $('request-count').textContent = `${count} REQUEST${count === 1 ? '' : 'S'}`;
  $('diagnostic-empty').hidden = state.history.length > 0;
  for (const entry of [...state.history].reverse()) {
    const heading = document.createElement('div'); heading.className = `operation${entry.error ? ' error' : ''}`;
    heading.textContent = `${entry.time} · ${entry.command}${entry.error ? ` · ${entry.error}` : entry.message ? ` · ${entry.message}` : ''}`;
    list.append(heading);
    if (!entry.requests.length) {
      const line = document.createElement('p'); line.className = 'muted small'; line.textContent = 'No network requests. Operation used local state or a retry cooldown.'; list.append(line);
    }
    for (const request of entry.requests) {
      const row = document.createElement('div'); row.className = 'request';
      const title = document.createElement('div'); title.className = 'request-heading';
      const status = document.createElement('span'); status.className = `status${request.error || request.status >= 400 ? ' failed' : ''}`; status.textContent = request.status ?? 'ERROR';
      const endpoint = document.createElement('span'); endpoint.className = 'endpoint'; endpoint.textContent = `${request.method} ${request.host}${request.path}`;
      const timing = document.createElement('span'); timing.className = 'muted'; timing.textContent = `${request.milliseconds} ms`;
      title.append(status, endpoint, timing); row.append(title);
      if (request.days || request.error) {
        const pre = document.createElement('pre'); pre.textContent = JSON.stringify(request.days ? { model: request.model, days: request.days } : { error: request.error }, null, 2); row.append(pre);
      }
      list.append(row);
    }
  }
}
async function command(payload) {
  if (state.busy) return null;
  state.busy = true; updateControls(); notice('');
  try {
    const response = await fetch('/api/command', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload), cache: 'no-store' });
    if (!response.ok) throw new Error('The local server could not complete the request.');
    const result = await response.json();
    if (typeof result.configured === 'boolean') state.configured = result.configured;
    if (typeof result.demo === 'boolean') state.demo = result.demo;
    if (payload.command !== 'state') {
      state.history.push({ command: payload.command === 'control' ? `control: ${payload.action}` : payload.command, time: new Date().toLocaleTimeString(), error: result.error, message: result.message, requests: result.diagnostics || [] });
      state.history = state.history.slice(-20); renderDiagnostics();
    }
    if (result.report) renderReport(result.report);
    if (!result.ok) { notice(result.error || 'The request failed.'); $('diagnostic-panel').open = true; }
    else if (result.message) notice(result.message, true);
    return result;
  } catch (error) {
    notice('Can’t reach the local web server. Check that python3 web/server.py is still running.');
    return null;
  } finally { state.busy = false; updateControls(); }
}
$('timezone').value = Intl.DateTimeFormat().resolvedOptions().timeZone || 'America/Los_Angeles';
$('login-form').addEventListener('submit', async event => {
  event.preventDefault();
  const fields = new FormData(event.target);
  renderReport(null); state.podChecked = 0;
  const payload = { command: 'configure', email: fields.get('email'), password: fields.get('password'), timezone: fields.get('timezone') };
  event.target.elements.password.value = '';
  await command(payload);
  payload.password = '';
});
$('demo').addEventListener('click', async () => {
  state.history = []; state.podChecked = 0;
  await command({ command: 'demo' });
});
$('refresh').addEventListener('click', () => command({ command: 'report' }));
$('disconnect').addEventListener('click', async () => {
  const result = await command({ command: 'disconnect' });
  if (result?.ok) { renderReport(null); state.podChecked = 0; state.history = []; renderDiagnostics(); $('login-form').reset(); $('timezone').value = Intl.DateTimeFormat().resolvedOptions().timeZone; notice('Disconnected. Credentials and saved report cleared from memory.', true); }
});
$('pod-refresh').addEventListener('click', async () => {
  state.podChecked = 0;
  const result = await command({ command: 'status' });
  if (result?.pod) {
    state.podChecked = Date.now();
    $('pod-status').textContent = `Mode: ${result.pod.mode} · Setting: ${result.pod.fahrenheit}°F · Checked ${new Date().toLocaleTimeString()}`;
    $('temperature').value = Math.min(110, Math.max(55, result.pod.fahrenheit));
    $('temperature-value').textContent = `${$('temperature').value}°F`;
  } else $('pod-status').textContent = 'Status unavailable. Refresh before sending a command.';
  updateControls();
});
async function control(action, fahrenheit) {
  if (!state.configured || state.demo || Date.now() - state.podChecked >= 60000) { notice('Refresh Pod status before sending a command.'); return; }
  state.podChecked = 0;
  const result = await command({ command: 'control', action, fahrenheit });
  $('pod-status').textContent = result?.ok ? 'Command accepted. Refresh status to check the current setting.' : 'Command could not be confirmed. Refresh status before retrying.';
}
$('pod-on').addEventListener('click', () => control('on'));
$('pod-off').addEventListener('click', () => {
  if (window.confirm('Turn off heating/cooling for your saved Eight Sleep profile?')) control('off');
});
$('temperature').addEventListener('input', event => { $('temperature-value').textContent = `${event.target.value}°F`; });
$('temperature-form').addEventListener('submit', event => { event.preventDefault(); control('temperature', Number($('temperature').value)); });
$('copy-diagnostics').addEventListener('click', async event => {
  event.preventDefault(); event.stopPropagation();
  try { await navigator.clipboard.writeText(JSON.stringify({ client: 'MySleep web / shared Swift core', history: state.history }, null, 2)); notice('Diagnostics copied. Credentials and report values are excluded.', true); }
  catch { notice('Clipboard unavailable. Select the diagnostic text to copy it.'); }
});
setInterval(updateControls, 10000);
(async () => {
  const result = await command({ command: 'state' });
  if (result?.configured) { renderReport(null); await command({ command: 'report' }); }
  else if (result?.demo) await command({ command: 'demo' });
})();
