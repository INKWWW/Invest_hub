#!/usr/bin/env node
import assert from 'node:assert/strict';
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

const runner = 'scripts/v2/run-local-x-identity-resolution.sh';
assert.equal(existsSync(runner), true, 'identity-resolution runner must exist');

const temporary = mkdtempSync(join(tmpdir(), 'invest-hub-x-identity-gate-'));
const probe = join(temporary, 'python-probe');
const marker = join(temporary, 'python-was-invoked');
writeFileSync(probe, `#!/usr/bin/env bash\ntouch ${JSON.stringify(marker)}\n`, { mode: 0o700 });
chmodSync(probe, 0o700);

const expectedOpencli = `${process.cwd()}/.runtime/v2/opencli-collection/current/bin/opencli-v2-collection`;
const privateArguments = [
  '--opencli-executable', expectedOpencli,
  '--source-config', join(temporary, 'config.toml'),
  '--credential', join(temporary, 'credential.json'),
  '--source-id', '00000000-0000-0000-0000-000000000001',
  '--evidence-dir', join(temporary, 'evidence'),
];

function invoke(args, environment = {}) {
  return spawnSync('bash', [runner, ...args], {
    encoding: 'utf8',
    timeout: 15_000,
    env: {
      ...process.env,
      V2_REAL_X_ACK: 'authorized',
      V2_PYTHON_BIN: probe,
      ...environment,
    },
  });
}

function assertRefusedBeforePython(result, expected) {
  assert.notEqual(result.status, 0, 'runner must refuse an incomplete or unsafe invocation');
  assert.match(`${result.stdout}${result.stderr}`, expected);
  assert.equal(existsSync(marker), false, 'runner must not invoke Python when a gate rejects the input');
}

try {
  for (const missingFlag of ['--opencli-executable', '--source-config', '--credential', '--source-id', '--evidence-dir']) {
    const index = privateArguments.indexOf(missingFlag);
    const args = [...privateArguments];
    args.splice(index, 2);
    assertRefusedBeforePython(
      invoke([...args, '--approve-identity-resolution']),
      /identity_resolution_private_runtime_inputs_required/,
    );
  }

  assertRefusedBeforePython(
    invoke(privateArguments),
    /--approve-identity-resolution/,
  );
  assertRefusedBeforePython(
    invoke([...privateArguments, '--approve-identity-resolution'], { V2_REAL_X_ACK: 'not-authorized' }),
    /V2_REAL_X_ACK=authorized/,
  );
  assertRefusedBeforePython(
    invoke([
      '--opencli-executable', 'opencli',
      '--source-config', join(temporary, 'config.toml'),
      '--credential', join(temporary, 'credential.json'),
      '--source-id', '00000000-0000-0000-0000-000000000001',
      '--evidence-dir', join(temporary, 'evidence'),
      '--approve-identity-resolution',
    ]),
    /dedicated local Collection executable/,
  );
  assertRefusedBeforePython(
    invoke([...privateArguments, '--approve-identity-resolution'], { V2_PYTHON_BIN: join(temporary, 'not-executable') }),
    /executable V2_PYTHON_BIN/,
  );

  const source = readFileSync(runner, 'utf8');
  assert.match(source, /opencli-v2-collection/, 'runner must bind to the dedicated controlled executable');
  assert.match(source, /git -C .* check-ignore -q/, 'runner must reject private paths that are not Git-ignored');
  assert.match(source, /owner_only/, 'runner must check owner-only private input permissions');
  const execution = source.slice(source.indexOf('V2_REAL_X_ACK=authorized'));
  assert.match(execution, /-m invest_hub_worker\.cli resolve-x-identity/, 'runner must use only the identity CLI command');
  assert.doesNotMatch(execution, /run-once|run-scheduled|codex|twitter collection/, 'runner must never invoke task, model, or collection commands');

  process.stdout.write('local_x_identity_resolution_gate: pass\n');
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
