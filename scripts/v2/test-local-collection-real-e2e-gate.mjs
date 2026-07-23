#!/usr/bin/env node
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

const runner = 'scripts/v2/run-local-collection-real-e2e.sh';
assert.equal(existsSync(runner), true, 'real Collection E2E runner must exist');

const result = spawnSync('bash', [runner], { encoding: 'utf8', timeout: 15_000 });
assert.notEqual(result.status, 0, 'real Collection E2E must refuse missing approval and inputs');
assert.match(`${result.stdout}${result.stderr}`, /--approve-real-persistence/, 'runner must name the persistence approval gate');

process.stdout.write('local_collection_real_e2e_gate: pass\n');
