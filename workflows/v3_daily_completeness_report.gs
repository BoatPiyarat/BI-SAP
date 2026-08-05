/**
 * SOURCE ONLY / Class A. Install only after a Boat-reachable primary and independent fallback
 * recipient are approved and a rehearsal proves both success and failure behavior.
 * Required Script Properties: PROJECT_ID, COMPLETENESS_RECIPIENT, COMPLETENESS_FALLBACK_RECIPIENT.
 * Optional: BQ_DATASET (default sap_integration_v3).
 */

const COMPLETENESS = Object.freeze({ DATASET: 'sap_integration_v3', REGION: 'asia-southeast1' });

/** Install a trigger only after deployment approval. It delivers every pending immutable snapshot. */
function dispatchPendingV3DailyCompletenessReports() {
  const config = completenessConfig_();
  const pending = completenessQuery_(config,
    `SELECT pipeline_run_id FROM \`${config.projectId}.${config.dataset}.v3_daily_completeness_run\`
     WHERE snapshot_status='READY_TO_ALERT' AND alert_delivery_status='PENDING'
     ORDER BY created_at`, []).rows;
  pending.forEach((row) => deliverV3DailyCompletenessReport_(config, row.f[0].v));
}

function deliverV3DailyCompletenessReport_(config, pipelineRunId) {
  const report = buildV3DailyCompletenessReport_(config, pipelineRunId);
  try {
    MailApp.sendEmail(config.primaryRecipient, `SAP V3 daily completeness — ${pipelineRunId}`, report);
    setCompletenessAlertStatus_(config, pipelineRunId, 'DELIVERED');
  } catch (error) {
    const message = completenessSanitize_(error);
    setCompletenessAlertStatus_(config, pipelineRunId, 'ALERT_FAILED');
    try {
      MailApp.sendEmail(config.fallbackRecipient,
        `[ACTION REQUIRED] SAP V3 completeness alert failed — ${pipelineRunId}`,
        `Primary report delivery failed for pipeline run ${pipelineRunId}: ${message}`);
    } catch (fallbackError) {
      throw new Error(`COMPLETENESS_ALERT_AND_FALLBACK_FAILED run=${pipelineRunId}`);
    }
    throw new Error(`COMPLETENESS_ALERT_FAILED run=${pipelineRunId}: ${message}`);
  }
}

function buildV3DailyCompletenessReport_(config, pipelineRunId) {
  const runs = completenessQuery_(config,
    `SELECT snapshot_status,alert_delivery_status,unit1_complete_count,units2_5_complete_count,
       magnitude_status,gate_blocker_count,notification_rows,export_run_count,manifest_count
     FROM \`${config.projectId}.${config.dataset}.v3_daily_completeness_run\`
     WHERE pipeline_run_id=@pipeline_run_id`, [completenessParam_('pipeline_run_id', 'STRING', pipelineRunId)]).rows;
  if (runs.length !== 1) throw new Error(`COMPLETENESS_SNAPSHOT_NOT_UNIQUE run=${pipelineRunId}`);
  const run = runs[0].f.map((field) => field.v);
  if (run[0] !== 'READY_TO_ALERT' || run[1] !== 'PENDING') {
    throw new Error(`COMPLETENESS_SNAPSHOT_NOT_PENDING run=${pipelineRunId}`);
  }
  const metrics = completenessQuery_(config,
    `SELECT metric_group,population_grain,metric_code,records,orders,amount_satang
     FROM \`${config.projectId}.${config.dataset}.v3_daily_completeness_metric\`
     WHERE pipeline_run_id=@pipeline_run_id
     ORDER BY metric_group,population_grain,metric_code`, [completenessParam_('pipeline_run_id', 'STRING', pipelineRunId)]).rows;
  const metricLines = metrics.map((row) => {
    const values = row.f.map((field) => field.v == null ? 'NULL' : field.v);
    return `${values[0]}/${values[1]}/${values[2]}: records=${values[3]}, orders=${values[4]}, amount_satang=${values[5]}`;
  });
  return [
    `Pipeline run: ${pipelineRunId}`,
    `Unit 1 complete: ${run[2]}; Units 2-5 complete: ${run[3]}; magnitude: ${run[4]}`,
    `Automation blockers: ${run[5]}; notification rows: ${run[6]}; exports/manifests: ${run[7]}/${run[8]}`,
    '', 'Metrics:', ...(metricLines.length ? metricLines : ['(none)']),
  ].join('\n');
}

function setCompletenessAlertStatus_(config, pipelineRunId, status) {
  const result = completenessQuery_(config,
    `UPDATE \`${config.projectId}.${config.dataset}.v3_daily_completeness_run\`
     SET alert_delivery_status=@status
     WHERE pipeline_run_id=@pipeline_run_id AND snapshot_status='READY_TO_ALERT'
       AND alert_delivery_status='PENDING'`, [
      completenessParam_('pipeline_run_id', 'STRING', pipelineRunId),
      completenessParam_('status', 'STRING', status),
    ]);
  if (String(result.numDmlAffectedRows) !== '1') {
    throw new Error(`COMPLETENESS_ALERT_STATUS_NOT_UPDATED run=${pipelineRunId} status=${status}`);
  }
}

function completenessConfig_() {
  const properties = PropertiesService.getScriptProperties();
  const projectId = properties.getProperty('PROJECT_ID');
  const primaryRecipient = properties.getProperty('COMPLETENESS_RECIPIENT');
  const fallbackRecipient = properties.getProperty('COMPLETENESS_FALLBACK_RECIPIENT');
  if (!projectId || !primaryRecipient || !fallbackRecipient || primaryRecipient === fallbackRecipient) {
    throw new Error('Distinct PROJECT_ID, COMPLETENESS_RECIPIENT, and COMPLETENESS_FALLBACK_RECIPIENT are required');
  }
  return { projectId, primaryRecipient, fallbackRecipient, dataset: properties.getProperty('BQ_DATASET') || COMPLETENESS.DATASET };
}

function completenessQuery_(config, sql, parameters) {
  const response = UrlFetchApp.fetch(`https://bigquery.googleapis.com/bigquery/v2/projects/${config.projectId}/queries`, {
    method: 'post', contentType: 'application/json', headers: { Authorization: `Bearer ${ScriptApp.getOAuthToken()}` },
    payload: JSON.stringify({ query: sql, useLegacySql: false, location: COMPLETENESS.REGION,
      maximumBytesBilled: '21474836480', parameterMode: 'NAMED', queryParameters: parameters }), muteHttpExceptions: true,
  });
  if (response.getResponseCode() !== 200) throw new Error(`COMPLETENESS_BQ_${response.getResponseCode()}`);
  const result = JSON.parse(response.getContentText());
  if (!result.jobComplete) throw new Error('COMPLETENESS_BQ_JOB_NOT_COMPLETE');
  return result;
}

function completenessParam_(name, type, value) { return { name, parameterType: { type }, parameterValue: { value } }; }
function completenessSanitize_(value) { return String(value).replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/g, '<EMAIL>').slice(0, 300); }
