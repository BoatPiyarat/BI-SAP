'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const sourcePath = path.join(__dirname, 'sap_result_ingestion.gs');
const context = vm.createContext({
  console,
  Date,
  JSON,
  Object,
  RegExp,
  Set,
  String,
});
vm.runInContext(fs.readFileSync(sourcePath, 'utf8'), context, {
  filename: sourcePath,
});

const sapReportedName =
  'RCB_MOTOR_INSURANCE_RCB_06_V3_DAILY_NEWPAYMENT_20260803_' +
  'V3DAILY-20260803-113257-55042e7c_000000000000.csv';
const productionName = sapReportedName.replace(/^RCB_MOTOR_/, '');
const emailBody = [
  'CompanyDB: RCB_LIVE_DB',
  'Status: success',
  'ImportType: INSURANCE_RCB',
  'Upload LogID: 21183',
  `FileName: ${sapReportedName}`,
].join('\r\n');

const metadata = context.parseMetadata_(emailBody);
assert.deepEqual(
  JSON.parse(JSON.stringify(metadata)),
  {
    companyDb: 'RCB_LIVE_DB',
    status: 'success',
    importType: 'INSURANCE_RCB',
    logId: '21183',
    fileName: sapReportedName,
    jeReference: null,
    reconciliationReference: null,
  },
  'exact LogID 21183-shaped email metadata must parse'
);
assert.equal(
  context.isExpectedSender_('SAP B1 <rcare_sap_b1@rabbitcare.com>'),
  true,
  'configured sender in a display-name envelope must match'
);
assert.equal(
  context.isExpectedSender_('attacker+rcare_sap_b1@rabbitcare.com@example.net'),
  false,
  'lookalike sender must not match'
);

const errors = context.parseTxtDetails_(
  'Info only\r\nError OrderItem L123-ABC period=4 invalid value\r\nfailed structural row 88'
);
assert.equal(errors.length, 2);
assert.equal(errors[0].errorClass, 'ROW_LEVEL');
assert.equal(errors[0].orderItem, 'L123-ABC');
assert.equal(errors[0].period, 4);
assert.equal(errors[0].template.includes('L123-ABC'), false);
assert.equal(errors[1].errorClass, 'STRUCTURAL');

const seenNames = [];
context.query_ = (_config, _sql, parameters) => {
  const requestedName = parameters[0].parameterValue.value;
  seenNames.push(requestedName);
  if (requestedName !== sapReportedName) return [];
  return [{ f: [{ v: 'V3DAILY-20260803-113257-55042e7c' }, { v: 'gs://interface-file/exact' }] }];
};
const grouped = context.groupByManifest_(
  { projectId: 'pacific-plating-282708', dataset: 'sap_integration_v3' },
  [{ fileName: sapReportedName }, { fileName: productionName }]
);
assert.deepEqual(seenNames, [sapReportedName, productionName]);
assert.equal(Object.keys(grouped).length, 1);
assert.equal(grouped['V3DAILY-20260803-113257-55042e7c'].length, 1);
assert.equal(
  grouped['V3DAILY-20260803-113257-55042e7c'][0].fileName,
  sapReportedName,
  'manifest matching must use the SAP-reported name, not the production basename'
);

context.query_ = () => [
  { f: [{ v: 'run-one' }, { v: 'gs://interface-file/one' }] },
  { f: [{ v: 'run-two' }, { v: 'gs://interface-file/two' }] },
];
assert.throws(
  () => context.groupByManifest_(
    { projectId: 'pacific-plating-282708', dataset: 'sap_integration_v3' },
    [{ fileName: sapReportedName }]
  ),
  /AMBIGUOUS_MANIFEST/,
  'more than one exact manifest must fail closed'
);

const pollConfig = { projectId: 'p', dataset: 'd' };
const pollCandidate = {
  logId: '21183',
  message: {
    getThread: () => ({
      addLabel: () => pollEvents.push('label'),
    }),
  },
};
let pollEvents = [];
context.getConfig_ = () => pollConfig;
context.findCandidates_ = () => [pollCandidate];
context.groupByManifest_ = () => ({ run: [pollCandidate] });
context.persistCandidate_ = () => pollEvents.push('persist');
context.requestPostImportRefresh_ = () => pollEvents.push('publish');
context.getOrCreateLabel_ = () => 'ingested';
context.writeHeartbeat_ = (_config, _startedAt, outcome, count) =>
  pollEvents.push(`heartbeat:${outcome}:${count}`);
context.notify_ = () => pollEvents.push('notify');
context.pollSapResultMailbox();
assert.deepEqual(
  pollEvents,
  ['persist', 'publish', 'label', 'heartbeat:SUCCESS:1'],
  'success must persist and publish before applying the ingested label'
);

pollEvents = [];
context.groupByManifest_ = () => ({});
context.pollSapResultMailbox();
assert.deepEqual(
  pollEvents,
  ['heartbeat:SUCCESS:1'],
  'a candidate without an exact manifest must remain unlabeled and unpersisted'
);

pollEvents = [];
const ambiguousCandidate = {
  logId: '21184',
  message: pollCandidate.message,
};
context.findCandidates_ = () => [pollCandidate, ambiguousCandidate];
context.groupByManifest_ = () => ({
  run: [pollCandidate, ambiguousCandidate],
});
assert.throws(
  () => context.pollSapResultMailbox(),
  /AMBIGUOUS_ACK/,
  'multiple candidates for one run must fail closed'
);
assert.deepEqual(
  pollEvents,
  ['heartbeat:FAILED:0', 'notify'],
  'ambiguity must write a failed heartbeat and alert without persistence or labeling'
);

console.log('sap_result_ingestion local contract tests: 18 assertions passed');
