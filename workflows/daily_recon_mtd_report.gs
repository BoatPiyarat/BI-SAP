/**
 * SOURCE ONLY / Class A. Install only after a Boat-reachable primary and independent fallback
 * recipient are approved and a rehearsal proves both success and failure behavior.
 * Required Script Properties: PROJECT_ID, RECON_MTD_RECIPIENT, RECON_MTD_FALLBACK_RECIPIENT.
 * Optional: BQ_DATASET (default sap_integration_v3).
 *
 * Reads `recon_careos_charges` (normally refreshed nightly at 21:00 ICT by
 * sp_nightly_state_and_recon_refresh via sp_recon_all_charges — see sql/ddl/005_recon_all_charges.sql).
 * This step performs no BigQuery write and calls no mutating procedure; it only aggregates and
 * emails an existing table's current-month-ICT rows, gated on the table's own freshness (see
 * FRESHNESS_STALE_AFTER_HOURS). Install the daily 06:00 ICT trigger on sendDailyReconMtdReport
 * only after deployment approval.
 *
 * Delta review fixes (2026-08-15, corrective to Codex BLOCK in
 * docs/reviews/2026-08-14-ff1db18-codex.md):
 *  1. ICT month window now converts DATETIME->TIMESTAMP via the 'Asia/Bangkok' zone (was
 *     TIMESTAMP(DATE), which BigQuery reads as UTC midnight — 7h early — excluding 00:00-06:59
 *     ICT on the 1st) and gets an explicit upper bound of "now" so future-dated rows can't enter.
 *  2. Report-build failures (query/API/JSON/unknown-status) now also route to the fallback
 *     channel — buildReconMtdReport_ moved inside the same try as the primary mail send.
 *  3. reconMtdQuery_ now polls jobs.getQueryResults on jobComplete:false and paginates via
 *     pageToken instead of throwing on a normal async response.
 *  4. Unknown recon_status values fail closed (throws) instead of being silently dropped from
 *     the three rendered rows.
 *  5. Recipient distinctness now compares trimmed lower-case values.
 *  6. Report states the freshness of the underlying table (MAX(recon_checked_at)) instead of
 *     unconditionally asserting "same-night data"; run is refused (fails closed, no email sent
 *     as if data were fine) when older than FRESHNESS_STALE_AFTER_HOURS.
 * Still NOT fixed here (requires Codex's environment): exact-SQL live dry-run (blocked by the
 * ongoing `bq` ReauthUnattendedError — see docs/INPUTS_NEEDED.md) and the exact Apps Script
 * project/manifest/trigger/rollback runbook (no browser/clasp session available on this machine).
 */

const RECON_MTD = Object.freeze({
  DATASET: 'sap_integration_v3',
  REGION: 'asia-southeast1',
  TIMEZONE: 'Asia/Bangkok',
  KNOWN_STATUSES: ['IN_SAP', 'MISSING_FROM_SAP', 'NO_ORDER_ITEM'],
  FRESHNESS_STALE_AFTER_HOURS: 15,
  MAX_POLL_ATTEMPTS: 10,
  POLL_INTERVAL_MS: 1000,
});

/** Install a daily 06:00 ICT trigger (accepted execution window, not an exact-instant guarantee
 *  — Apps Script time-driven triggers fire within their configured hour) only after deployment
 *  approval. */
function sendDailyReconMtdReport() {
  const config = reconMtdConfig_();
  deliverReconMtdReport_(config);
}

function deliverReconMtdReport_(config) {
  try {
    const report = buildReconMtdReport_(config);
    MailApp.sendEmail(config.primaryRecipient, `SAP↔CareOS daily reconciliation — MTD ${report.monthLabel}`, report.body);
  } catch (error) {
    const message = reconMtdSanitize_(error);
    try {
      MailApp.sendEmail(config.fallbackRecipient,
        '[ACTION REQUIRED] SAP↔CareOS daily reconciliation failed',
        `Primary report build/delivery failed: ${message}`);
    } catch (fallbackError) {
      throw new Error('RECON_MTD_ALERT_AND_FALLBACK_FAILED');
    }
    throw new Error(`RECON_MTD_ALERT_FAILED: ${message}`);
  }
}

function buildReconMtdReport_(config) {
  const now = new Date();
  // Same (month_start, now] partition filter on both queries below — recon_careos_charges is
  // PARTITION BY DATE(first_paid_time), and sp_recon_all_charges rebuilds the whole table with a
  // single CURRENT_TIMESTAMP() per run, so MAX(recon_checked_at) scoped to this month's rows is
  // an equally valid freshness signal while staying partition-pruned (cost-control rule).
  const boundParams = [
    reconMtdParam_('month_start', 'TIMESTAMP', reconMtdIctMonthStart_(now)),
    reconMtdParam_('now', 'TIMESTAMP', now.toISOString()),
  ];
  const filterSql = 'WHERE first_paid_time >= @month_start AND first_paid_time <= @now';

  const freshness = reconMtdQuery_(config,
    `SELECT MAX(recon_checked_at) AS latest
     FROM \`${config.projectId}.${config.dataset}.recon_careos_charges\`
     ${filterSql}`, boundParams).rows || [];
  const latestCheckedAt = freshness.length ? freshness[0].f[0].v : null;
  if (!latestCheckedAt) throw new Error('RECON_MTD_NO_FRESHNESS_EVIDENCE');
  const ageHours = (now.getTime() - Number(latestCheckedAt) * 1000) / 3600000;
  if (ageHours > RECON_MTD.FRESHNESS_STALE_AFTER_HOURS) {
    throw new Error(`RECON_MTD_STALE_DATA age_hours=${ageHours.toFixed(1)}`);
  }

  const rows = reconMtdQuery_(config,
    `SELECT recon_status, COUNT(*) AS n, ROUND(SUM(total_amount_thb), 2) AS thb
     FROM \`${config.projectId}.${config.dataset}.recon_careos_charges\`
     ${filterSql}
     GROUP BY recon_status
     ORDER BY recon_status`, boundParams).rows || [];

  const byStatus = {};
  const unknownStatuses = [];
  rows.forEach((row) => {
    const values = row.f.map((field) => field.v);
    const status = values[0];
    if (RECON_MTD.KNOWN_STATUSES.indexOf(status) === -1) {
      unknownStatuses.push(status);
      return;
    }
    byStatus[status] = { n: Number(values[1]), thb: Number(values[2]) };
  });
  if (unknownStatuses.length) {
    throw new Error(`RECON_MTD_UNKNOWN_RECON_STATUS: ${unknownStatuses.join(',')}`);
  }

  const lines = RECON_MTD.KNOWN_STATUSES.map((status) => {
    const s = byStatus[status] || { n: 0, thb: 0 };
    return `${status}: ${s.n} periods, ${s.thb.toFixed(2)} THB`;
  });
  const monthLabel = Utilities.formatDate(now, RECON_MTD.TIMEZONE, 'yyyy-MM');
  const generatedAt = Utilities.formatDate(now, RECON_MTD.TIMEZONE, "yyyy-MM-dd HH:mm 'ICT'");
  const freshnessLine = `Source freshness: recon_careos_charges last refreshed ${ageHours.toFixed(1)}h ago`;
  return {
    monthLabel,
    body: [
      `Month to date: ${monthLabel} (Asia/Bangkok calendar month, source: recon_careos_charges)`,
      `Generated: ${generatedAt}`,
      freshnessLine,
      '',
      ...lines,
      '',
      'MISSING_FROM_SAP = CareOS shows a successful charge for this order_item/period with no',
      'matching invoiced row in SAP. NO_ORDER_ITEM = charge has no linked CareOS order at all.',
    ].join('\n'),
  };
}

/** Returns the ISO instant for 00:00:00 on the 1st of the current Asia/Bangkok month, correctly
 *  converted to UTC (TIMESTAMP(DATE) alone is read as UTC midnight and was 7h early). */
function reconMtdIctMonthStart_(now) {
  const monthStartDate = Utilities.formatDate(now, RECON_MTD.TIMEZONE, "yyyy-MM-01'T'00:00:00");
  return Utilities.formatDate(
    new Date(Utilities.parseDate(monthStartDate, RECON_MTD.TIMEZONE, "yyyy-MM-dd'T'HH:mm:ss").getTime()),
    'Etc/UTC', "yyyy-MM-dd'T'HH:mm:ss'Z'"
  );
}

function reconMtdConfig_() {
  const properties = PropertiesService.getScriptProperties();
  const projectId = properties.getProperty('PROJECT_ID');
  const primaryRecipient = properties.getProperty('RECON_MTD_RECIPIENT');
  const fallbackRecipient = properties.getProperty('RECON_MTD_FALLBACK_RECIPIENT');
  const normalize = (value) => (value || '').trim().toLowerCase();
  if (!projectId || !primaryRecipient || !fallbackRecipient
      || normalize(primaryRecipient) === normalize(fallbackRecipient)) {
    throw new Error('Distinct PROJECT_ID, RECON_MTD_RECIPIENT, and RECON_MTD_FALLBACK_RECIPIENT are required');
  }
  return { projectId, primaryRecipient, fallbackRecipient, dataset: properties.getProperty('BQ_DATASET') || RECON_MTD.DATASET };
}

function reconMtdQuery_(config, sql, parameters) {
  const response = UrlFetchApp.fetch(`https://bigquery.googleapis.com/bigquery/v2/projects/${config.projectId}/queries`, {
    method: 'post', contentType: 'application/json', headers: { Authorization: `Bearer ${ScriptApp.getOAuthToken()}` },
    payload: JSON.stringify({ query: sql, useLegacySql: false, location: RECON_MTD.REGION,
      maximumBytesBilled: '21474836480', parameterMode: 'NAMED', queryParameters: parameters }), muteHttpExceptions: true,
  });
  if (response.getResponseCode() !== 200) throw new Error(`RECON_MTD_BQ_${response.getResponseCode()}`);
  let result = JSON.parse(response.getContentText());
  const jobId = result.jobReference && result.jobReference.jobId;
  let attempts = 0;
  while (!result.jobComplete) {
    if (!jobId) throw new Error('RECON_MTD_BQ_JOB_NOT_COMPLETE_NO_JOB_ID');
    if (attempts >= RECON_MTD.MAX_POLL_ATTEMPTS) throw new Error(`RECON_MTD_BQ_JOB_TIMEOUT job=${jobId}`);
    Utilities.sleep(RECON_MTD.POLL_INTERVAL_MS);
    attempts += 1;
    const pollResponse = UrlFetchApp.fetch(
      `https://bigquery.googleapis.com/bigquery/v2/projects/${config.projectId}/queries/${jobId}?location=${RECON_MTD.REGION}`,
      { method: 'get', headers: { Authorization: `Bearer ${ScriptApp.getOAuthToken()}` }, muteHttpExceptions: true }
    );
    if (pollResponse.getResponseCode() !== 200) throw new Error(`RECON_MTD_BQ_POLL_${pollResponse.getResponseCode()}`);
    result = JSON.parse(pollResponse.getContentText());
  }
  let rows = result.rows || [];
  let pageToken = result.pageToken;
  while (pageToken) {
    const pageResponse = UrlFetchApp.fetch(
      `https://bigquery.googleapis.com/bigquery/v2/projects/${config.projectId}/queries/${jobId}?location=${RECON_MTD.REGION}&pageToken=${encodeURIComponent(pageToken)}`,
      { method: 'get', headers: { Authorization: `Bearer ${ScriptApp.getOAuthToken()}` }, muteHttpExceptions: true }
    );
    if (pageResponse.getResponseCode() !== 200) throw new Error(`RECON_MTD_BQ_PAGE_${pageResponse.getResponseCode()}`);
    const page = JSON.parse(pageResponse.getContentText());
    rows = rows.concat(page.rows || []);
    pageToken = page.pageToken;
  }
  return { rows };
}

function reconMtdParam_(name, type, value) { return { name, parameterType: { type }, parameterValue: { value } }; }
function reconMtdSanitize_(value) { return String(value).replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/g, '<EMAIL>').slice(0, 300); }
