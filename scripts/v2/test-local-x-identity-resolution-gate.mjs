#!/usr/bin/env node
import assert from 'node:assert/strict';
import {
  chmodSync,
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  renameSync,
  rmSync,
  rmdirSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(scriptDirectory, '..', '..');
const runner = join(repoRoot, 'scripts/v2/run-local-x-identity-resolution.sh');
const verifier = join(repoRoot, 'scripts/v2/verify-local-opencli-collection.sh');
const contract = join(repoRoot, 'scripts/v2/test-local-opencli-collection-contract.mjs');
const lockPath = join(repoRoot, 'tools/opencli-v2-collection.lock.json');
assert.equal(existsSync(runner), true, 'identity-resolution runner must exist');

const localRuntimeRoot = join(repoRoot, '.runtime');
const localRuntimeV2 = join(localRuntimeRoot, 'v2');
const createdRuntimeDirectories = [];
if (!existsSync(localRuntimeRoot)) {
  mkdirSync(localRuntimeRoot, { mode: 0o700 });
  createdRuntimeDirectories.push(localRuntimeRoot);
}
if (!existsSync(localRuntimeV2)) {
  mkdirSync(localRuntimeV2, { mode: 0o700 });
  createdRuntimeDirectories.push(localRuntimeV2);
}

const fixtureRoot = mkdtempSync(join(localRuntimeV2, 'x-identity-gate-'));
const syntheticRepo = join(fixtureRoot, 'repository');
const syntheticRunner = join(syntheticRepo, 'scripts/v2/run-local-x-identity-resolution.sh');
const syntheticVerifier = join(syntheticRepo, 'scripts/v2/verify-local-opencli-collection.sh');
const syntheticContract = join(syntheticRepo, 'scripts/v2/test-local-opencli-collection-contract.mjs');
const syntheticLock = join(syntheticRepo, 'tools/opencli-v2-collection.lock.json');
const marker = join(fixtureRoot, 'python-was-invoked');
const probe = join(fixtureRoot, 'python-probe');
const privateRoot = join(syntheticRepo, '.runtime/v2/x-identity-gate/private');
const config = join(privateRoot, 'config.toml');
const credential = join(privateRoot, 'credential.json');
const evidence = join(privateRoot, 'evidence');
const expectedOpencli = join(syntheticRepo, '.runtime/v2/opencli-collection/current/bin/opencli-v2-collection');
const sourceId = '00000000-0000-0000-0000-000000000001';
const realGit = spawnSync('which', ['git'], { encoding: 'utf8' }).stdout.trim();
assert.notEqual(realGit, '', 'git must be available for the isolated synthetic fixture');

function writeExecutable(path, content) {
  writeFileSync(path, content, { mode: 0o700 });
  chmodSync(path, 0o700);
}

function makeFile(path, content = 'synthetic\n') {
  writeFileSync(path, content, { mode: 0o600 });
  chmodSync(path, 0o600);
}

function clearMarker() {
  rmSync(marker, { force: true });
}

function commandArguments() {
  return [
    '--opencli-executable', expectedOpencli,
    '--source-config', config,
    '--credential', credential,
    '--source-id', sourceId,
    '--evidence-dir', evidence,
  ];
}

function invoke(args, environment = {}) {
  return spawnSync('bash', [syntheticRunner, ...args], {
    encoding: 'utf8',
    timeout: 15_000,
    env: {
      ...process.env,
      PATH: `${join(fixtureRoot, 'bin')}:${process.env.PATH}`,
      V2_REAL_X_ACK: 'authorized',
      V2_PYTHON_BIN: probe,
      IDENTITY_GATE_MARKER: marker,
      IDENTITY_GATE_REAL_GIT: realGit,
      IDENTITY_GATE_COLLECTION_COMMIT: JSON.parse(readFileSync(syntheticLock, 'utf8')).collection_commit,
      IDENTITY_GATE_PACKAGE_LOCK_SHA256: JSON.parse(readFileSync(syntheticLock, 'utf8')).package_lock_sha256,
      ...environment,
    },
  });
}

function assertRefusedBeforePython(result, expected) {
  assert.notEqual(result.status, 0, 'runner must refuse an incomplete or unsafe invocation');
  assert.match(`${result.stdout}${result.stderr}`, expected);
  assert.equal(existsSync(marker), false, 'runner must not invoke Python when a gate rejects the input');
}

function assertSafeSuccess() {
  clearMarker();
  const result = invoke([...commandArguments(), '--approve-identity-resolution']);
  assert.equal(result.status, 0, `${result.stdout}${result.stderr}`);
  assert.equal(existsSync(marker), true, 'the harmless fake Python must run after every gate passes');
  assert.deepEqual(readFileSync(marker, 'utf8').trim().split('\n'), [
    '-m',
    'invest_hub_worker.cli',
    'resolve-x-identity',
    '--config',
    config,
    '--credential',
    credential,
    '--source-id',
    sourceId,
    '--evidence-dir',
    evidence,
    '--opencli-executable',
    expectedOpencli,
    '--worker-name',
    'v2-x-identity-worker',
  ]);
}

try {
  mkdirSync(join(syntheticRepo, 'scripts/v2'), { recursive: true, mode: 0o700 });
  mkdirSync(join(syntheticRepo, 'tools'), { recursive: true, mode: 0o700 });
  copyFileSync(runner, syntheticRunner);
  copyFileSync(verifier, syntheticVerifier);
  copyFileSync(contract, syntheticContract);
  copyFileSync(lockPath, syntheticLock);
  chmodSync(syntheticRunner, 0o700);
  chmodSync(syntheticVerifier, 0o700);
  writeFileSync(join(syntheticRepo, '.gitignore'), '.runtime/\n', { mode: 0o600 });
  assert.equal(spawnSync(realGit, ['init', '--quiet', syntheticRepo], { encoding: 'utf8' }).status, 0);

  mkdirSync(dirname(expectedOpencli), { recursive: true, mode: 0o700 });
  mkdirSync(join(syntheticRepo, '.runtime/v2/opencli-collection/current/source/dist/src'), { recursive: true, mode: 0o700 });
  writeExecutable(expectedOpencli, '#!/usr/bin/env bash\nif [[ "$1" == "twitter" && "$2" == "collection" && "$3" == "--help" ]]; then\n  printf "twitter collection --until\\n"\n  exit 0\nfi\nexit 2\n');
  writeFileSync(join(syntheticRepo, '.runtime/v2/opencli-collection/current/source/dist/src/main.js'), 'synthetic\n', { mode: 0o600 });
  writeFileSync(join(syntheticRepo, '.runtime/v2/opencli-collection/current/source/package-lock.json'), 'synthetic\n', { mode: 0o600 });
  writeFileSync(join(syntheticRepo, '.runtime/v2/opencli-collection/current/source/LICENSE'), 'Apache License\n', { mode: 0o600 });

  mkdirSync(join(fixtureRoot, 'bin'), { mode: 0o700 });
  writeExecutable(join(fixtureRoot, 'bin/git'), '#!/usr/bin/env bash\nif [[ "$1" == "-C" && "$3" == "rev-parse" && "$4" == "HEAD" ]]; then\n  printf "%s\\n" "$IDENTITY_GATE_COLLECTION_COMMIT"\n  exit 0\nfi\nexec "$IDENTITY_GATE_REAL_GIT" "$@"\n');
  writeExecutable(join(fixtureRoot, 'bin/shasum'), '#!/usr/bin/env bash\nprintf "%s  %s\\n" "$IDENTITY_GATE_PACKAGE_LOCK_SHA256" "${@: -1}"\n');
  writeExecutable(probe, '#!/usr/bin/env bash\nprintf "%s\\n" "$@" > "$IDENTITY_GATE_MARKER"\n');

  mkdirSync(privateRoot, { recursive: true, mode: 0o700 });
  chmodSync(privateRoot, 0o700);
  makeFile(config, '[worker]\n');
  makeFile(credential, '{}\n');
  mkdirSync(evidence, { mode: 0o700 });
  chmodSync(evidence, 0o700);

  for (const missingFlag of ['--opencli-executable', '--source-config', '--credential', '--source-id', '--evidence-dir']) {
    clearMarker();
    const args = commandArguments();
    const index = args.indexOf(missingFlag);
    args.splice(index, 2);
    assertRefusedBeforePython(
      invoke([...args, '--approve-identity-resolution']),
      /identity_resolution_private_runtime_inputs_required/,
    );
  }

  clearMarker();
  assertRefusedBeforePython(invoke(commandArguments()), /--approve-identity-resolution/);
  clearMarker();
  assertRefusedBeforePython(
    invoke([...commandArguments(), '--approve-identity-resolution'], { V2_REAL_X_ACK: 'not-authorized' }),
    /V2_REAL_X_ACK=authorized/,
  );
  clearMarker();
  assertRefusedBeforePython(
    invoke([
      '--opencli-executable', 'opencli',
      '--source-config', config,
      '--credential', credential,
      '--source-id', sourceId,
      '--evidence-dir', evidence,
      '--approve-identity-resolution',
    ]),
    /dedicated local Collection executable/,
  );
  clearMarker();
  assertRefusedBeforePython(
    invoke([...commandArguments(), '--approve-identity-resolution'], { V2_PYTHON_BIN: join(fixtureRoot, 'not-executable') }),
    /executable V2_PYTHON_BIN/,
  );

  const nonIgnored = join(syntheticRepo, 'public-config.toml');
  makeFile(nonIgnored);
  clearMarker();
  assertRefusedBeforePython(
    invoke([
      '--opencli-executable', expectedOpencli,
      '--source-config', nonIgnored,
      '--credential', credential,
      '--source-id', sourceId,
      '--evidence-dir', evidence,
      '--approve-identity-resolution',
    ]),
    /identity_resolution_private_path_not_ignored/,
  );

  for (const [field, insecurePath, insecureMode, secureMode] of [
    ['--source-config', config, 0o640, 0o600],
    ['--credential', credential, 0o640, 0o600],
    ['--evidence-dir', evidence, 0o750, 0o700],
  ]) {
    chmodSync(insecurePath, insecureMode);
    clearMarker();
    const args = commandArguments();
    args[args.indexOf(field) + 1] = insecurePath;
    assertRefusedBeforePython(
      invoke([...args, '--approve-identity-resolution']),
      /identity_resolution_owner_only_path_required/,
    );
    chmodSync(insecurePath, secureMode);
  }

  const unsafeParent = join(privateRoot, 'unsafe-parent');
  mkdirSync(unsafeParent, { mode: 0o700 });
  chmodSync(unsafeParent, 0o770);
  const unsafeConfig = join(unsafeParent, 'config.toml');
  makeFile(unsafeConfig);
  clearMarker();
  assertRefusedBeforePython(
    invoke([
      '--opencli-executable', expectedOpencli,
      '--source-config', unsafeConfig,
      '--credential', credential,
      '--source-id', sourceId,
      '--evidence-dir', evidence,
      '--approve-identity-resolution',
    ]),
    /identity_resolution_owner_only_path_required/,
  );
  chmodSync(unsafeParent, 0o700);

  const configLink = join(privateRoot, 'config-link.toml');
  const credentialLink = join(privateRoot, 'credential-link.json');
  const evidenceLink = join(privateRoot, 'evidence-link');
  symlinkSync(config, configLink);
  symlinkSync(credential, credentialLink);
  symlinkSync(evidence, evidenceLink);
  for (const [field, linkedPath] of [
    ['--source-config', configLink],
    ['--credential', credentialLink],
    ['--evidence-dir', evidenceLink],
  ]) {
    clearMarker();
    const args = commandArguments();
    args[args.indexOf(field) + 1] = linkedPath;
    assertRefusedBeforePython(
      invoke([...args, '--approve-identity-resolution']),
      /identity_resolution_owner_only_path_required/,
    );
  }

  const realOpencli = `${expectedOpencli}.real`;
  renameSync(expectedOpencli, realOpencli);
  symlinkSync(realOpencli, expectedOpencli);
  clearMarker();
  assertRefusedBeforePython(
    invoke([...commandArguments(), '--approve-identity-resolution']),
    /identity_resolution_controlled_opencli_required/,
  );
  rmSync(expectedOpencli);
  renameSync(realOpencli, expectedOpencli);

  assertSafeSuccess();

  const source = readFileSync(runner, 'utf8');
  assert.match(source, /opencli-v2-collection/, 'runner must bind to the dedicated controlled executable');
  assert.match(source, /git -C .* check-ignore -q/, 'runner must reject private paths that are not Git-ignored');
  assert.match(source, /require_secure_path_component/, 'runner must validate every existing private path component');
  const finalCommandIndex = source.lastIndexOf('\nV2_REAL_X_ACK=authorized PYTHONPATH=');
  assert.notEqual(finalCommandIndex, -1, 'runner must contain one final Worker command');
  const finalCommand = source.slice(finalCommandIndex + 1).trim();
  assert.match(
    finalCommand,
    /^V2_REAL_X_ACK=authorized PYTHONPATH="\$repo_root\/workers\/v0\/src" "\$V2_PYTHON_BIN" \\\n+  -m invest_hub_worker\.cli resolve-x-identity \\\n+  --config "\$source_config" \\\n+  --credential "\$credential" \\\n+  --source-id "\$source_id" \\\n+  --evidence-dir "\$evidence_dir" \\\n+  --opencli-executable "\$opencli_executable" \\\n+  --worker-name "\$worker_name"$/,
    'runner must execute exactly the approved identity Worker vector',
  );
  assert.equal((source.match(/-m invest_hub_worker\.cli resolve-x-identity/g) ?? []).length, 1, 'runner must have one Worker command');
  assert.doesNotMatch(finalCommand, /run-once|run-scheduled|codex|twitter\s+collection/i, 'final Worker command must not execute tasks, models, or collection');

  process.stdout.write('local_x_identity_resolution_gate: pass\n');
} finally {
  rmSync(fixtureRoot, { recursive: true, force: true });
  for (const directory of createdRuntimeDirectories.reverse()) {
    try {
      rmdirSync(directory);
    } catch {
      // Another local runtime may have appeared; never remove it.
    }
  }
}
