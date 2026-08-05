'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const sourcePath = path.join(__dirname, 'v3_daily_completeness_report.gs');
const context = vm.createContext({
  console,
  Error,
  JSON,
  Object,
  String,
});
vm.runInContext(fs.readFileSync(sourcePath, 'utf8'), context, {
  filename: sourcePath,
});

const config = {
  projectId: 'pacific-plating-282708',
  dataset: 'sap_integration_v3',
  primaryRecipient: 'primary@example.test',
  fallbackRecipient: 'fallback@example.test',
};
const runId = 'V3NIGHTLY-2026-08-05T13:30:00-abcd1234';

context.completenessQuery_ = (_config, sql) => {
  if (sql.includes('v3_daily_completeness_run')) {
    return {
      rows: [{
        f: [
          { v: 'READY_TO_ALERT' },
          { v: 'PENDING' },
          { v: '1' },
          { v: '1' },
          { v: 'PASS' },
          { v: '0' },
          { v: '3' },
          { v: '1' },
          { v: '1' },
        ],
      }],
    };
  }
  if (sql.includes('v3_daily_completeness_metric')) {
    return {
      rows: [{
        f: [
          { v: 'SAP_RESULT' },
          { v: 'EVENT' },
          { v: 'ACKNOWLEDGED' },
          { v: '558' },
          { v: '558' },
          { v: null },
        ],
      }],
    };
  }
  throw new Error('unexpected query');
};
const report = context.buildV3DailyCompletenessReport_(config, runId);
assert.match(report, /magnitude: PASS/);
assert.match(report, /SAP_RESULT\/EVENT\/ACKNOWLEDGED: records=558, orders=558/);
assert.equal(report.includes('primary@example.test'), false);
assert.equal(report.includes('fallback@example.test'), false);

let events = [];
context.buildV3DailyCompletenessReport_ = () => 'metric-only report';
context.setCompletenessAlertStatus_ = (_config, _run, status) =>
  events.push(`status:${status}`);
context.MailApp = {
  sendEmail: (recipient) => events.push(`mail:${recipient}`),
};
context.deliverV3DailyCompletenessReport_(config, runId);
assert.deepEqual(
  events,
  ['mail:primary@example.test', 'status:DELIVERED'],
  'DELIVERED must be persisted only after primary mail success'
);

events = [];
context.MailApp = {
  sendEmail: (recipient) => {
    events.push(`mail:${recipient}`);
    if (recipient === config.primaryRecipient) throw new Error('primary down');
  },
};
assert.throws(
  () => context.deliverV3DailyCompletenessReport_(config, runId),
  /COMPLETENESS_ALERT_FAILED/,
  'primary failure must remain visible even after fallback succeeds'
);
assert.deepEqual(
  events,
  [
    'mail:primary@example.test',
    'status:ALERT_FAILED',
    'mail:fallback@example.test',
  ],
  'ALERT_FAILED must be persisted before fallback is attempted'
);

events = [];
context.MailApp = {
  sendEmail: (recipient) => {
    events.push(`mail:${recipient}`);
    throw new Error('mail down');
  },
};
assert.throws(
  () => context.deliverV3DailyCompletenessReport_(config, runId),
  /COMPLETENESS_ALERT_AND_FALLBACK_FAILED/,
  'dual-channel failure must fail closed'
);
assert.deepEqual(
  events,
  [
    'mail:primary@example.test',
    'status:ALERT_FAILED',
    'mail:fallback@example.test',
  ]
);

events = [];
context.completenessConfig_ = () => config;
context.completenessQuery_ = () => ({
  rows: [
    { f: [{ v: 'run-fails' }] },
    { f: [{ v: 'run-succeeds' }] },
  ],
});
context.deliverV3DailyCompletenessReport_ = (_config, candidateRunId) => {
  events.push(`attempt:${candidateRunId}`);
  if (candidateRunId === 'run-fails') throw new Error('first run failed');
};
assert.throws(
  () => context.dispatchPendingV3DailyCompletenessReports(),
  /COMPLETENESS_DISPATCH_FAILURES count=1/,
  'batch must surface an aggregate failure'
);
assert.deepEqual(
  events,
  ['attempt:run-fails', 'attempt:run-succeeds'],
  'one failed report must not strand a later pending report'
);

console.log('v3_daily_completeness_report local contract tests: 11 assertions passed');
