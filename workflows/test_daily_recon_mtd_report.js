'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const sourcePath = path.join(__dirname, 'daily_recon_mtd_report.gs');
const context = vm.createContext({
  console,
  Error,
  JSON,
  Object,
  String,
  Number,
  Date,
  Utilities: {
    formatDate: (_date, _tz, pattern) => (pattern === 'yyyy-MM' ? '2026-08' : '2026-08-14 06:00 ICT'),
  },
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

context.reconMtdQuery_ = (_config, sql) => {
  assert.match(sql, /recon_careos_charges/);
  assert.match(sql, /DATE_TRUNC\(CURRENT_DATE\('Asia\/Bangkok'\), MONTH\)/);
  return {
    rows: [
      { f: [{ v: 'IN_SAP' }, { v: '100' }, { v: '5000.5' }] },
      { f: [{ v: 'MISSING_FROM_SAP' }, { v: '3' }, { v: '150' }] },
    ],
  };
};
const report = context.buildReconMtdReport_(config);
assert.equal(report.monthLabel, '2026-08');
assert.match(report.body, /IN_SAP: 100 periods, 5000\.50 THB/);
assert.match(report.body, /MISSING_FROM_SAP: 3 periods, 150\.00 THB/);
assert.match(report.body, /NO_ORDER_ITEM: 0 periods, 0\.00 THB/);
assert.equal(report.body.includes('primary@example.test'), false);
assert.equal(report.body.includes('fallback@example.test'), false);

let events = [];
context.buildReconMtdReport_ = () => ({ monthLabel: '2026-08', body: 'metric-only report' });
context.MailApp = {
  sendEmail: (recipient) => events.push(`mail:${recipient}`),
};
context.deliverReconMtdReport_(config);
assert.deepEqual(events, ['mail:primary@example.test'], 'success must send only to the primary recipient');

events = [];
context.MailApp = {
  sendEmail: (recipient) => {
    events.push(`mail:${recipient}`);
    if (recipient === config.primaryRecipient) throw new Error('primary down');
  },
};
assert.throws(
  () => context.deliverReconMtdReport_(config),
  /RECON_MTD_ALERT_FAILED/,
  'primary failure must remain visible even after fallback succeeds'
);
assert.deepEqual(events, ['mail:primary@example.test', 'mail:fallback@example.test']);

events = [];
context.MailApp = {
  sendEmail: (recipient) => {
    events.push(`mail:${recipient}`);
    throw new Error('mail down');
  },
};
assert.throws(
  () => context.deliverReconMtdReport_(config),
  /RECON_MTD_ALERT_AND_FALLBACK_FAILED/,
  'dual-channel failure must fail closed'
);
assert.deepEqual(events, ['mail:primary@example.test', 'mail:fallback@example.test']);

events = [];
context.reconMtdConfig_ = () => { throw new Error('Distinct PROJECT_ID, RECON_MTD_RECIPIENT, and RECON_MTD_FALLBACK_RECIPIENT are required'); };
assert.throws(
  () => context.sendDailyReconMtdReport(),
  /RECON_MTD_RECIPIENT/,
  'missing/duplicate recipient config must fail closed before any query or mail call'
);

console.log('daily_recon_mtd_report local contract tests: 10 assertions passed');
