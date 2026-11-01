const test = require('node:test')
const assert = require('node:assert')
const fs = require('node:fs')
const path = require('node:path')

// QML needs ".pragma library" on the first line, which is not valid JS.
// Strip it, then compile the rest as a CommonJS module.
function loadModel() {
  const file = path.join(__dirname, '..', 'Model.js')
  const source = fs.readFileSync(file, 'utf8').replace(/^\.pragma library\s*$/m, '')
  const m = { exports: {} }
  new Function('module', 'exports', source)(m, m.exports)
  return m.exports
}
const Model = loadModel()

function summary(over) {
  return Object.assign({
    state: 'ok', message: '', generatedAt: '2026-11-01T10:00:00Z',
    omarchy: { pending: true, package: 'omarchy', from: '4.1-1', to: '4.2-1' },
    sources: { pacman: 12, aur: 1, mise: 2 },
    total: 15, downloadMiB: 210, downloadPartial: false, reboot: false, notes: []
  }, over || {})
}

test('parseSummary rejects text that is not JSON', () => {
  const r = Model.parseSummary('not json')
  assert.strictEqual(r.ok, false)
  assert.strictEqual(r.summary, null)
  assert.ok(r.message.length > 0)
})

test('parseSummary rejects JSON without sources', () => {
  const r = Model.parseSummary(JSON.stringify({ state: 'ok', total: 1 }))
  assert.strictEqual(r.ok, false)
  assert.strictEqual(r.summary, null)
})

test('parseSummary accepts a real summary', () => {
  const r = Model.parseSummary(JSON.stringify(summary()))
  assert.strictEqual(r.ok, true)
  assert.strictEqual(r.summary.total, 15)
})

test('statusOf returns error when runState is error, even with a summary', () => {
  assert.strictEqual(Model.statusOf(summary(), 'error'), 'error')
  assert.strictEqual(Model.statusOf(null, 'error'), 'error')
})

test('statusOf returns checking when summary is null and loading', () => {
  assert.strictEqual(Model.statusOf(null, 'loading'), 'checking')
})

test('statusOf returns pending when total > 0', () => {
  assert.strictEqual(Model.statusOf(summary(), 'ok'), 'pending')
})

test('statusOf returns current when total is 0', () => {
  assert.strictEqual(Model.statusOf(summary({ total: 0 }), 'ok'), 'current')
})

test('statusOf keeps the last summary while a refresh loads', () => {
  assert.strictEqual(Model.statusOf(summary(), 'loading'), 'pending')
})

test('statusOf treats a summary in state error as error', () => {
  assert.strictEqual(Model.statusOf(summary({ state: 'error', total: 0 }), 'ok'), 'error')
})

test('tooltip covers every status', () => {
  assert.match(Model.tooltip(summary(), 'pending'), /15/)
  assert.ok(Model.tooltip(summary({ total: 0 }), 'current').length > 0)
  assert.strictEqual(Model.tooltip(summary({ state: 'error', message: 'boom' }), 'error'), 'boom')
  assert.ok(Model.tooltip(null, 'error').length > 0)
  assert.ok(Model.tooltip(null, 'checking').length > 0)
})

test('verdictLine says "at least 210 MiB" when downloadPartial', () => {
  assert.match(Model.verdictLine(summary({ downloadPartial: true })), /at least 210 MiB/)
})

test('verdictLine says "about 210 MiB" when not', () => {
  assert.match(Model.verdictLine(summary()), /about 210 MiB/)
})

test('verdictLine omits size when downloadMiB is null', () => {
  const line = Model.verdictLine(summary({ downloadMiB: null }))
  assert.doesNotMatch(line, /MiB/)
  assert.match(line, /15 items/)
})

test('verdictLine says "No reboot needed." / "Reboot needed."', () => {
  assert.match(Model.verdictLine(summary()), /No reboot needed\./)
  assert.match(Model.verdictLine(summary({ reboot: true })), /Reboot needed\./)
})

test('verdictLine uses the singular for one item', () => {
  assert.match(Model.verdictLine(summary({ total: 1 })), /1 item\b/)
})

test('sourceRows shows "4.1-1 to 4.2-1" for the Omarchy row when pending', () => {
  const rows = Model.sourceRows(summary())
  assert.deepStrictEqual(rows.map(r => r.id), ['omarchy', 'pacman', 'aur', 'mise'])
  assert.strictEqual(rows[0].label, 'Omarchy')
  assert.strictEqual(rows[0].value, '4.1-1 to 4.2-1')
  assert.strictEqual(rows[1].label, 'System packages')
  assert.strictEqual(rows[1].value, '12')
  assert.strictEqual(rows[2].label, 'AUR')
  assert.strictEqual(rows[3].label, 'Dev tools')
  assert.strictEqual(rows[3].value, '2')
})

test('sourceRows shows 0 for Omarchy when not pending', () => {
  const rows = Model.sourceRows(summary({ omarchy: { pending: false, package: '', from: '', to: '' } }))
  assert.strictEqual(rows[0].value, '0')
})

test('explainLabel gives "Explain with Claude Code" for claude and "Choose default agent" for empty', () => {
  assert.strictEqual(Model.explainLabel('claude'), 'Explain with Claude Code')
  assert.strictEqual(Model.explainLabel('codex'), 'Explain with Codex')
  assert.strictEqual(Model.explainLabel(''), 'Choose default agent')
  assert.strictEqual(Model.explainLabel('mystery'), 'Explain with mystery')
})

const PATH = '/run/user/1000/update-explainer/report.txt'

test('buildPrompt contains the data path', () => {
  assert.ok(Model.buildPrompt(PATH).includes(PATH))
})

test('buildPrompt tells the agent to stop if the file cannot be read', () => {
  assert.ok(Model.buildPrompt(PATH).includes('cannot read'))
})

test('buildPrompt forbids running the update', () => {
  assert.ok(Model.buildPrompt(PATH).includes('Never run'))
})

test('buildPrompt requires a final line starting "Sources:"', () => {
  assert.ok(Model.buildPrompt(PATH).includes('Sources:'))
})

test('buildPrompt asks for the user\'s language', () => {
  assert.match(Model.buildPrompt(PATH), /language/)
})

test('buildPrompt names no agent', () => {
  assert.doesNotMatch(Model.buildPrompt(PATH), /claude|codex|opencode|skill/i)
})

test('buildPrompt holds no em dash or en dash', () => {
  assert.doesNotMatch(Model.buildPrompt(PATH), /[\u2013\u2014]/)
})
