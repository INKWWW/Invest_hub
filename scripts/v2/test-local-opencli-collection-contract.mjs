#!/usr/bin/env node
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';

function readOption(name) {
  const index = process.argv.indexOf(name);
  if (index < 0 || !process.argv[index + 1]) {
    throw new Error(`missing required option: ${name}`);
  }
  return process.argv[index + 1];
}

function assertSha(value, name) {
  assert.equal(typeof value, 'string', `${name} must be a string`);
  assert.match(value, /^[0-9a-f]{40}$/, `${name} must be a full Git SHA`);
}

function collectionHelp() {
  const fixtureIndex = process.argv.indexOf('--fixture-help');
  if (fixtureIndex >= 0) {
    const fixture = process.argv[fixtureIndex + 1];
    if (!fixture || !existsSync(fixture)) {
      throw new Error('fixture help file must exist');
    }
    return readFileSync(fixture, 'utf8');
  }
  const executable = readOption('--executable');
  const result = spawnSync(executable, ['twitter', 'collection', '--help'], {
    encoding: 'utf8',
    timeout: 15_000,
  });
  if (result.error || result.status !== 0) {
    throw new Error('local Collection executable did not provide help');
  }
  return result.stdout;
}

const lockPath = resolve(readOption('--lock'));
if (!existsSync(lockPath)) {
  throw new Error('OpenCLI Collection lock file must exist');
}
const lock = JSON.parse(readFileSync(lockPath, 'utf8'));

assert.equal(lock.schema_version, 1, 'lock schema version must be 1');
assert.equal(lock.source_repository, 'https://github.com/INKWWW/OpenCLI.git');
assertSha(lock.base_commit, 'base_commit');
assertSha(lock.collection_commit, 'collection_commit');
assert.equal(lock.package_lock_sha256, 'e149339d464cf4f19c651fcae19471d67e1f29ad87502ae2d8e6b1e2fcf1f54e');
assert.equal(lock.license, 'Apache-2.0');
assert.equal(lock.runtime_dir, '.runtime/v2/opencli-collection');
assert.equal(lock.command, 'twitter collection');
assert.deepEqual(lock.success_stop_reasons, ['time_boundary_reached', 'cursor_exhausted']);

const help = collectionHelp();
assert.match(help, /twitter\s+collection/i, 'Collection help must name the command');
assert.match(help, /--until\b/, 'Collection help must require a lower boundary');

process.stdout.write('opencli_collection_contract: pass\n');
