#!/usr/bin/env node
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

const installer = 'scripts/v2/install-local-opencli-collection.sh';
assert.equal(existsSync(installer), true, 'local Collection installer must exist');

const result = spawnSync('bash', [installer, '--lock', 'tools/opencli-v2-collection.lock.json'], {
  encoding: 'utf8',
  timeout: 15_000,
});
assert.notEqual(result.status, 0, 'installer must refuse a build without explicit approval');
assert.match(`${result.stdout}${result.stderr}`, /--approve-local-build/, 'installer must explain the approval gate');

process.stdout.write('opencli_collection_installer_safety: pass\n');
