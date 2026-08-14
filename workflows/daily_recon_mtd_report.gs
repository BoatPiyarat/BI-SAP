/**
 * SOURCE ONLY / Class A. Install only after a Boat-reachable primary and independent fallback
 * recipient are approved and a rehearsal proves both success and failure behavior.
 * Required Script Properties: PROJECT_ID, RECON_MTD_RECIPIENT, RECON_MTD_FALLBACK_RECIPIENT.
 * Optional: BQ_DATASET (default sap_integration_v3).
 *
 * Reads `recon_careos_charges` (already refreshed nightly at 21:00 ICT by
 * sp_nightly_state_and_recon_refresh via sp_recon_all_charges — see sql/ddl/005_recon_all_charges.sql).
 * This step performs no BigQuery write and calls no mutating procedure; it only aggregates and
 * emails an existing table's current month-to-date rows. Install the daily 06:00 ICT trigger on
 * sendDailyReconMtdReport only after deployment approval.
 */

const RECON_MTD = Object.freeze({ DATASET: 'sap_integration_v3', REGION: 'asia-southeast1' });

/** Install a daily 06:00 ICT trigger only after deployment approval. */
function sendDailyReconMtdReport() {
  const config = reconMtdConfig_();
  deliverReconMtdReport_(config);
}

function deliverReconMtdReport_(config) {
  const report = buildReconMtdReport_(config);
  try {
    MailApp.sendEmail(config.primaryRecipient, `SAP↔CareOS daily reconciliation — MTD ${report.monthLabel}`, report.body);
  } catch (error) {
    const message = reconMtdSanitize_(error);
    try {
      MailApp.sendEmail(config.fallbackRecipient,
        `[ACTION REQUIRED] SAP↔CareOS daily reconciliation failed — ${report.monthLabel}`,
        `Primary report delivery failed: ${message}`);
    } catch (fallbackError) {
      throw new Error(`RECON_MTD_ALERT_AND_FALLBACK_FAILED month=${report.monthLabel}`);
    }
    throw new Error(`RECON_MTD_ALERT_FAILED month=${report.monthLabel}: ${message}`);
  }
}

function buildReconMtdReport_(config) {
  const rows = reconMtdQuery_(config,
    `SELECT recon_status, COUNT(*) AS n, ROUND(SUM(total_amount_thb), 2) AS thb
     FROM \`${config.projectId}.${config.dataset}.recon_careos_charges\`
     WHERE first_paid_time >= TIMESTAMP(DATE_TRUNC(CURRENT_DATE('Asia/Bangkok'), MONTH))
     GROUP BY recon_status
     ORDER BY recon_status`, []).rows || [];
  const byStatus = {};
  rows.forEach((row) => {
    const values = row.f.map((field) => field.v);
    byStatus[values[0]] = { n: Number(values[1]), thb: Number(values[2]) };
  });
  const statuses = ['IN_SAP', 'MISSING_FROM_SAP', 'NO_ORDER_ITEM'];
  const lines = statuses.map((status) => {
    const s = byStatus[status] || { n: 0, thb: 0 };
    return `${status}: ${s.n} periods, ${s.thb.toFixed(2)} THB`;
  });
  const monthLabel = Utilities.formatDate(new Date(), 'Asia/Bangkok', 'yyyy-MM');
  const generatedAt = Utilities.formatDate(new Date(), 'Asia/Bangkok', "yyyy-MM-dd HH:mm 'ICT'");
  return {
    monthLabel,
    body: [
      `Month to date: ${monthLabel} (source: recon_careos_charges, refreshed nightly 21:00 ICT)`,
      `Generated: ${generatedAt}`,
      '',
      ...lines,
      '',
      'MISSING_FROM_SAP = CareOS shows a successful charge for this order_item/period with no',
      'matching invoiced row in SAP. NO_ORDER_ITEM = charge has no linked CareOS order at all.',
    ].join('\n'),
  };
}

function reconMtdConfig_() {
  const properties = PropertiesService.getScriptProperties();
  const projectId = properties.getProperty('PROJECT_ID');
  const primaryRecipient = properties.getProperty('RECON_MTD_RECIPIENT');
  const fallbackRecipient = properties.getProperty('RECON_MTD_FALLBACK_RECIPIENT');
  if (!projectId || !primaryRecipient || !fallbackRecipient || primaryRecipient === fallbackRecipient) {
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
  const result = JSON.parse(response.getContentText());
  if (!result.jobComplete) throw new Error('RECON_MTD_BQ_JOB_NOT_COMPLETE');
  return result;
}

function reconMtdSanitize_(value) { return String(value).replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/g, '<EMAIL>').slice(0, 300); }
