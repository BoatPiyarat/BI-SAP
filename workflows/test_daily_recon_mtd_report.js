'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const sourcePath = path.join(__dirname, 'daily_recon_mtd_report.gs');

function freshContext() {
  const context = vm.createContext({
    console,
    Error,
    JSON,
    Object,
    String,
    Number,
    Date,
    Utilities: {
      formatDate: (date, _tz, pattern) => {
        if (pattern === 'yyyy-MM') return '2026-08';
        if (pattern === "yyyy-MM-dd HH:mm 'ICT'") return '2026-08-15 06:00 ICT';
        if (pattern === "yyyy-MM-01'T'00:00:00") return '2026-08-01T00:00:00';
        if (pattern === "yyyy-MM-dd'T'HH:mm:ss'Z'") return '2026-07-31T17:00:00Z';
        return date.toISOString();
      },
      parseDate: (value, _tz, _fmt) => new Date('2026-07-31T17:00:00.000Z'),
      sleep: () => {},
    },
  });
  vm.runInContext(fs.readFileSync(sourcePath, 'utf8'), context, { filename: sourcePath });
  return context;
}

const config = {
  projectId: 'pacific-plating-282708',
  dataset: 'sap_integration_v3',
  primaryRecipient: 'primary@example.test',
  fallbackRecipient: 'fallback@example.test',
};
const NOW_EPOCH_SECONDS = Math.floor(new Date('2026-08-15T06:00:00Z').getTime() / 1000);

// --- ICT month boundary: query must use parameterized bounds, not a raw TIMESTAMP(DATE) cast ---
{
  const context = freshContext();
  let calls = 0;
  context.reconMtdQuery_ = (_config, sql, parameters) => {
    calls += 1;
    assert.doesNotMatch(sql, /TIMESTAMP\(DATE_TRUNC/, 'must not use the UTC-midnight-misinterpreted form');
    assert.match(sql, /@month_start/, 'both freshness and grouped queries must stay partition-filtered');
    assert.match(sql, /@now/);
    assert.equal(parameters[0].name, 'month_start');
    assert.equal(parameters[1].name, 'now');
    if (calls === 1) {
      assert.match(sql, /MAX\(recon_checked_at\)/);
      return { rows: [{ f: [{ v: String(NOW_EPOCH_SECONDS - 3600) }] }] }; // 1h old: fresh
    }
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
  assert.match(report.body, /Source freshness:.*1\.0h ago/);
  assert.equal(report.body.includes('primary@example.test'), false);
}

// --- freshness gate: stale table must fail closed instead of silently claiming fresh data ---
{
  const context = freshContext();
  context.reconMtdQuery_ = () => ({ rows: [{ f: [{ v: String(NOW_EPOCH_SECONDS - 20 * 3600) }] }] }); // 20h old
  assert.throws(() => context.buildReconMtdReport_(config), /RECON_MTD_STALE_DATA/);
}

// --- unknown recon_status must fail closed, not be silently dropped ---
{
  const context = freshContext();
  let calls = 0;
  context.reconMtdQuery_ = () => {
    calls += 1;
    if (calls === 1) return { rows: [{ f: [{ v: String(NOW_EPOCH_SECONDS - 3600) }] }] };
    return { rows: [{ f: [{ v: 'SOME_NEW_STATUS' }, { v: '1' }, { v: '1' }] }] };
  };
  assert.throws(() => context.buildReconMtdReport_(config), /RECON_MTD_UNKNOWN_RECON_STATUS/);
}

// --- async jobComplete:false must be polled, not thrown on ---
{
  const context = freshContext();
  let fetchCalls = 0;
  context.UrlFetchApp = {
    fetch: (url) => {
      fetchCalls += 1;
      if (fetchCalls === 1) {
        return {
          getResponseCode: () => 200,
          getContentText: () => JSON.stringify({ jobComplete: false, jobReference: { jobId: 'job-1' } }),
        };
      }
      assert.match(url, /queries\/job-1/, 'poll must target the original job id');
      return {
        getResponseCode: () => 200,
        getContentText: () => JSON.stringify({ jobComplete: true, rows: [{ f: [{ v: String(NOW_EPOCH_SECONDS) }] }] }),
      };
    },
  };
  context.ScriptApp = { getOAuthToken: () => 'token' };
  const result = context.reconMtdQuery_(config, 'SELECT 1', []);
  assert.equal(result.rows.length, 1);
  assert.equal(fetchCalls, 2, 'must poll exactly once after the initial not-complete response');
}

// --- pagination: multiple pages must be concatenated ---
{
  const context = freshContext();
  let fetchCalls = 0;
  context.UrlFetchApp = {
    fetch: (url) => {
      fetchCalls += 1;
      if (fetchCalls === 1) {
        return {
          getResponseCode: () => 200,
          getContentText: () => JSON.stringify({
            jobComplete: true, jobReference: { jobId: 'job-2' },
            rows: [{ f: [{ v: 'a' }] }], pageToken: 'next',
          }),
        };
      }
      assert.match(url, /pageToken=next/);
      return {
        getResponseCode: () => 200,
        getContentText: () => JSON.stringify({ rows: [{ f: [{ v: 'b' }] }] }),
      };
    },
  };
  context.ScriptApp = { getOAuthToken: () => 'token' };
  const result = context.reconMtdQuery_(config, 'SELECT 1', []);
  assert.equal(result.rows.length, 2);
}

// --- recipient normalization: case/whitespace variants of the same mailbox must be rejected ---
{
  const context = freshContext();
  context.PropertiesService = {
    getScriptProperties: () => ({
      getProperty: (key) => ({
        PROJECT_ID: 'p',
        RECON_MTD_RECIPIENT: ' Ops@Example.Test ',
        RECON_MTD_FALLBACK_RECIPIENT: 'ops@example.test',
      }[key]),
    }),
  };
  assert.throws(() => context.reconMtdConfig_(), /Distinct PROJECT_ID/);
}

// --- report-build failure (not just primary-mail failure) must reach the fallback channel ---
{
  const context = freshContext();
  let events = [];
  context.buildReconMtdReport_ = () => { throw new Error('BQ query failed'); };
  context.MailApp = { sendEmail: (recipient) => events.push(`mail:${recipient}`) };
  assert.throws(() => context.deliverReconMtdReport_(config), /RECON_MTD_ALERT_FAILED/);
  assert.deepEqual(events, ['mail:fallback@example.test'], 'a build failure, not just a mail-send failure, must reach the fallback');
}

// --- successful delivery sends only to primary ---
{
  const context = freshContext();
  let events = [];
  context.buildReconMtdReport_ = () => ({ monthLabel: '2026-08', body: 'metric-only report' });
  context.MailApp = { sendEmail: (recipient) => events.push(`mail:${recipient}`) };
  context.deliverReconMtdReport_(config);
  assert.deepEqual(events, ['mail:primary@example.test']);
}

// --- primary mail-send failure still falls back, and both-channel failure fails closed ---
{
  const context = freshContext();
  let events = [];
  context.buildReconMtdReport_ = () => ({ monthLabel: '2026-08', body: 'metric-only report' });
  context.MailApp = {
    sendEmail: (recipient) => {
      events.push(`mail:${recipient}`);
      if (recipient === config.primaryRecipient) throw new Error('primary down');
    },
  };
  assert.throws(() => context.deliverReconMtdReport_(config), /RECON_MTD_ALERT_FAILED/);
  assert.deepEqual(events, ['mail:primary@example.test', 'mail:fallback@example.test']);

  events = [];
  context.MailApp = {
    sendEmail: (recipient) => { events.push(`mail:${recipient}`); throw new Error('mail down'); },
  };
  assert.throws(() => context.deliverReconMtdReport_(config), /RECON_MTD_ALERT_AND_FALLBACK_FAILED/);
  assert.deepEqual(events, ['mail:primary@example.test', 'mail:fallback@example.test']);
}

console.log('daily_recon_mtd_report local contract tests: 26 assertions passed');
