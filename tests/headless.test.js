const test = require('node:test')
const assert = require('node:assert')
const Headless = require('../Headless.js')

const ID = '4c5431f9-9390-4b99-a895-f62c72ed5b37'

test('only agents in the table run without a terminal', () => {
  assert.strictEqual(Headless.supports('claude'), true)
  for (const agent of ['codex', 'opencode', '', 'toString', '__proto__']) {
    assert.strictEqual(Headless.supports(agent), false, agent)
    assert.deepStrictEqual(Headless.runCommand(agent, 'p'), [])
  }
})

test('the prompt is one argument, last, and never parsed as an option', () => {
  const argv = Headless.runCommand('claude', '--dangerous prompt')
  assert.strictEqual(argv[argv.length - 1], '--dangerous prompt')
  assert.ok(argv.includes('-p'))
  assert.ok(argv.includes('json'))
})

test('sessionOf reads the session id from the real output shape', () => {
  assert.strictEqual(Headless.sessionOf('claude', JSON.stringify({ session_id: ID, result: 'ok' })), ID)
  assert.strictEqual(Headless.sessionOf('claude', 'not json'), '')
  assert.strictEqual(Headless.sessionOf('claude', JSON.stringify({ session_id: 'x; rm -rf ~' })), '')
  assert.strictEqual(Headless.sessionOf('codex', JSON.stringify({ session_id: ID })), '')
})

test('resumeLine quotes the folder and refuses a bad id', () => {
  assert.strictEqual(Headless.resumeLine('claude', ID, "/run/user/1000/it's"),
    "cd '/run/user/1000/it'\\''s' && 'claude' '--resume' '" + ID + "'")
  assert.strictEqual(Headless.resumeLine('claude', '$(reboot)', '/run'), '')
  assert.strictEqual(Headless.resumeLine('codex', ID, '/run'), '')
  assert.strictEqual(Headless.resumeLine('claude', ID, ''), '')
})
