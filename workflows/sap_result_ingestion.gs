/**
 * SOURCE ONLY / Class A — deploy through clasp or the Apps Script editor only after DDL 064/070,
 * IAM, trigger, GCS, alert-recipient, and rehearsal approvals are recorded.
 *
 * Required Script Properties: PROJECT_ID, LOG_BUCKET, ALERT_RECIPIENT.
 * Optional: BQ_DATASET (default sap_integration_v3), POLL_MINUTES (default 15).
 * Required OAuth scopes are declared in sap_result_ingestion.appsscript.json.
 */

const SAP_RESULT = Object.freeze({
  DATASET: 'sap_integration_v3',
  INGESTOR: 'sap_result_gmail_v3',
  LABEL: 'notification SAP upload',
  INGESTED_LABEL: 'ingested',
  SENDER: 'rcare_sap_b1@rabbitcare.com',
  COMPANY_DB: 'RCB_LIVE_DB',
  LOOKBACK_MS: 60 * 60 * 1000,
  HEARTBEAT_MAX_MS: 55 * 60 * 1000,
  REGION: 'asia-southeast1',
});

/** Install a time trigger strictly shorter than the 60-minute lookup window (recommended: 15 min). */
function pollSapResultMailbox() {
  const config = getConfig_();
  const startedAt = new Date();
  try {
    const candidates = findCandidates_(startedAt);
    const byRun = groupByManifest_(config, candidates);
    let processed = 0;

    Object.keys(byRun).forEach((runId) => {
      const group = byRun[runId];
      const logIds = [...new Set(group.map((c) => c.logId))];
      if (group.length !== 1 || logIds.length !== 1) {
        throw new Error(`AMBIGUOUS_ACK run=${runId} candidates=${group.length} log_ids=${logIds.join(',')}`);
      }
      persistCandidate_(config, group[0]);
      group[0].message.getThread().addLabel(getOrCreateLabel_(SAP_RESULT.INGESTED_LABEL));
      processed += 1;
    });

    writeHeartbeat_(config, startedAt, 'SUCCESS', candidates.length, null);
  } catch (error) {
    const template = sanitizeError_(error);
    writeHeartbeat_(config, startedAt, 'FAILED', 0, template);
    notify_(config, `SAP result ingestion failed: ${template}`);
    throw error;
  }
}

/** Independent monitor trigger. It must be scheduled separately from pollSapResultMailbox. */
function checkSapResultIngestionHeartbeat() {
  const config = getConfig_();
  const rows = query_(config,
    `SELECT last_success_at FROM \`${config.projectId}.${config.dataset}.sap_result_ingestion_heartbeat_v3\`
     WHERE ingestor_name = @ingestor_name ORDER BY recorded_at DESC LIMIT 1`,
    [param_('ingestor_name', 'STRING', SAP_RESULT.INGESTOR)]);
  const lastSuccess = rows.length ? new Date(rows[0].f[0].v) : null;
  if (!lastSuccess || Date.now() - lastSuccess.getTime() >= SAP_RESULT.HEARTBEAT_MAX_MS) {
    notify_(config, `SAP result ingestion heartbeat missing or stale; last_success_at=${lastSuccess || 'NONE'}`);
  }
}

function findCandidates_(now) {
  const cutoff = new Date(now.getTime() - SAP_RESULT.LOOKBACK_MS);
  const query = `label:"${SAP_RESULT.LABEL}" -label:"${SAP_RESULT.INGESTED_LABEL}" from:${SAP_RESULT.SENDER} subject:"[LIVE]" newer_than:1h`;
  const candidates = [];
  GmailApp.search(query).forEach((thread) => thread.getMessages().forEach((message) => {
    if (message.getDate() < cutoff || !isExpectedSender_(message.getFrom())) return;
    const metadata = parseMetadata_(message.getPlainBody());
    if (!metadata || metadata.companyDb !== SAP_RESULT.COMPANY_DB || !metadata.logId || !metadata.fileName) return;
    candidates.push({ message, emailDate: message.getDate(), ...metadata });
  }));
  return candidates;
}

function groupByManifest_(config, candidates) {
  const result = {};
  candidates.forEach((candidate) => {
    const manifests = query_(config,
      `SELECT export_run_id, production_uri
       FROM \`${config.projectId}.${config.dataset}.sap_delivery_manifest_v3\`
       WHERE delivery_status = 'DELIVERED'
         AND sap_file_name = @file_name`,
      [param_('file_name', 'STRING', candidate.fileName)]);
    if (manifests.length === 0) return; // No current manifest: remain PENDING_ACK and do not label.
    if (manifests.length !== 1) throw new Error(`AMBIGUOUS_MANIFEST file=${candidate.fileName}`);
    const runId = manifests[0].f[0].v;
    candidate.productionUri = manifests[0].f[1].v;
    (result[runId] ||= []).push(candidate);
  });
  return result;
}

function persistCandidate_(config, candidate) {
  const attachments = candidate.message.getAttachments({ includeInlineImages: false, includeAttachments: true });
  const txt = attachments.filter((a) => /\.txt$/i.test(a.getName()));
  const xlsx = attachments.filter((a) => /\.xlsx$/i.test(a.getName()));
  if (txt.length !== 1 || xlsx.length > 1) {
    throw new Error(`ATTACHMENT_SHAPE log_id=${candidate.logId} txt=${txt.length} xlsx=${xlsx.length}`);
  }
  const txtUri = uploadAttachment_(config, candidate.logId, txt[0]);
  const xlsxUri = xlsx.length ? uploadAttachment_(config, candidate.logId, xlsx[0]) : null;
  const details = parseTxtDetails_(txt[0].getDataAsString());

  mergeHeader_(config, candidate, txtUri, xlsxUri);
  mergeDetails_(config, candidate.logId, details);
}

function mergeHeader_(config, candidate, txtUri, xlsxUri) {
  const sql = `MERGE \`${config.projectId}.${config.dataset}.sap_import_result_header_v3\` t
USING (SELECT @log_id log_id) s ON t.log_id = s.log_id
WHEN MATCHED THEN UPDATE SET file_name=@file_name, status=@status, import_type=@import_type,
  company_db=@company_db, email_date=@email_date, gmail_message_id=@gmail_message_id,
  txt_gcs_uri=@txt_gcs_uri, xlsx_gcs_uri=@xlsx_gcs_uri, je_reference=@je_reference,
  reconciliation_reference=@reconciliation_reference, attachment_parse_status='PARSED', ingested_at=CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT (log_id,file_name,status,import_type,company_db,email_date,gmail_message_id,txt_gcs_uri,xlsx_gcs_uri,je_reference,reconciliation_reference,attachment_parse_status,ingested_at)
VALUES (@log_id,@file_name,@status,@import_type,@company_db,@email_date,@gmail_message_id,@txt_gcs_uri,@xlsx_gcs_uri,@je_reference,@reconciliation_reference,'PARSED',CURRENT_TIMESTAMP())`;
  query_(config, sql, [
    param_('log_id', 'STRING', candidate.logId), param_('file_name', 'STRING', candidate.fileName),
    param_('status', 'STRING', candidate.status), param_('import_type', 'STRING', candidate.importType || null),
    param_('company_db', 'STRING', candidate.companyDb), param_('email_date', 'TIMESTAMP', candidate.emailDate.toISOString()),
    param_('gmail_message_id', 'STRING', candidate.message.getId()), param_('txt_gcs_uri', 'STRING', txtUri),
    param_('xlsx_gcs_uri', 'STRING', xlsxUri), param_('je_reference', 'STRING', candidate.jeReference || null),
    param_('reconciliation_reference', 'STRING', candidate.reconciliationReference || null),
  ]);
}

function mergeDetails_(config, logId, details) {
  details.forEach((detail, index) => {
    const sql = `MERGE \`${config.projectId}.${config.dataset}.sap_import_error_detail_v3\` t
USING (SELECT @log_id log_id, @detail_seq detail_seq) s ON t.log_id=s.log_id AND t.detail_seq=s.detail_seq
WHEN MATCHED THEN UPDATE SET error_class=@error_class,error_template=@error_template,error_message_raw=@error_message_raw,row_ref=@row_ref,order_item=@order_item,period=@period,parsed_at=CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT (log_id,detail_seq,error_class,error_template,error_message_raw,row_ref,order_item,period,parsed_at)
VALUES (@log_id,@detail_seq,@error_class,@error_template,@error_message_raw,@row_ref,@order_item,@period,CURRENT_TIMESTAMP())`;
    query_(config, sql, [
      param_('log_id', 'STRING', logId), param_('detail_seq', 'INT64', index + 1),
      param_('error_class', 'STRING', detail.errorClass), param_('error_template', 'STRING', detail.template),
      param_('error_message_raw', 'STRING', detail.raw), param_('row_ref', 'STRING', detail.rowRef),
      param_('order_item', 'STRING', detail.orderItem), param_('period', 'INT64', detail.period),
    ]);
  });
}

function writeHeartbeat_(config, startedAt, outcome, count, errorTemplate) {
  const sql = `MERGE \`${config.projectId}.${config.dataset}.sap_result_ingestion_heartbeat_v3\` t
USING (SELECT @ingestor_name ingestor_name) s ON t.ingestor_name=s.ingestor_name
WHEN MATCHED THEN UPDATE SET last_success_at=IF(@outcome='SUCCESS',CURRENT_TIMESTAMP(),t.last_success_at),last_poll_started_at=@started_at,last_poll_outcome=@outcome,last_message_count=@message_count,last_error_template=@error_template,recorded_at=CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT (ingestor_name,last_success_at,last_poll_started_at,last_poll_outcome,last_message_count,last_error_template,recorded_at)
VALUES (@ingestor_name,IF(@outcome='SUCCESS',CURRENT_TIMESTAMP(),TIMESTAMP '1970-01-01 00:00:00+00'),@started_at,@outcome,@message_count,@error_template,CURRENT_TIMESTAMP())`;
  query_(config, sql, [param_('ingestor_name', 'STRING', SAP_RESULT.INGESTOR), param_('started_at', 'TIMESTAMP', startedAt.toISOString()), param_('outcome', 'STRING', outcome), param_('message_count', 'INT64', count), param_('error_template', 'STRING', errorTemplate)]);
}

function uploadAttachment_(config, logId, blob) {
  const name = `sap_import_logs/${logId}/${blob.getName().replace(/[^A-Za-z0-9._-]/g, '_')}`;
  const url = `https://storage.googleapis.com/upload/storage/v1/b/${encodeURIComponent(config.bucket)}/o?uploadType=media&name=${encodeURIComponent(name)}&ifGenerationMatch=0`;
  const response = UrlFetchApp.fetch(url, { method: 'post', payload: blob.getBytes(), contentType: blob.getContentType(), headers: { Authorization: `Bearer ${ScriptApp.getOAuthToken()}` }, muteHttpExceptions: true });
  if (![200, 201, 412].includes(response.getResponseCode())) throw new Error(`GCS_UPLOAD_${response.getResponseCode()} log_id=${logId}`);
  return `gs://${config.bucket}/${name}`;
}

function parseMetadata_(body) {
  const get = (name) => { const m = body.match(new RegExp(`^${name}:\\s*(.+)$`, 'mi')); return m ? m[1].trim() : null; };
  return { companyDb: get('CompanyDB'), status: get('Status'), importType: get('ImportType'), logId: get('Upload LogID'), fileName: get('FileName'), jeReference: get('RefNo'), reconciliationReference: get('RCL_BPInstallment-RecconNo') };
}

function parseTxtDetails_(text) {
  return text.split(/\r?\n/).filter((line) => /error|invalid|failed|reject/i.test(line)).map((raw) => {
    const orderItem = (raw.match(/\bL\d+(?:-[A-Za-z0-9]+)?\b/) || [null])[0];
    const period = Number((raw.match(/\b(?:period|p)\s*[:=#-]?\s*(\d+)\b/i) || [null, null])[1]) || null;
    return { errorClass: orderItem ? 'ROW_LEVEL' : 'STRUCTURAL', template: raw.replace(/L\d+(?:-[A-Za-z0-9]+)?/g, '<ORDER_ITEM>').replace(/\d+/g, '<N>'), raw, rowRef: orderItem, orderItem, period };
  });
}

function query_(config, sql, parameters) {
  const response = UrlFetchApp.fetch(`https://bigquery.googleapis.com/bigquery/v2/projects/${config.projectId}/queries`, { method: 'post', contentType: 'application/json', headers: { Authorization: `Bearer ${ScriptApp.getOAuthToken()}` }, payload: JSON.stringify({ query: sql, useLegacySql: false, location: SAP_RESULT.REGION, maximumBytesBilled: '21474836480', parameterMode: 'NAMED', queryParameters: parameters }), muteHttpExceptions: true });
  if (response.getResponseCode() !== 200) throw new Error(`BQ_QUERY_${response.getResponseCode()}: ${sanitizeError_(response.getContentText())}`);
  const result = JSON.parse(response.getContentText());
  if (!result.jobComplete) throw new Error('BQ_JOB_NOT_COMPLETE');
  return result.rows || [];
}

function param_(name, type, value) { return { name, parameterType: { type }, parameterValue: { value } }; }
function getConfig_() { const p = PropertiesService.getScriptProperties(); const projectId = p.getProperty('PROJECT_ID'); const bucket = p.getProperty('LOG_BUCKET'); const alertRecipient = p.getProperty('ALERT_RECIPIENT'); if (!projectId || !bucket || !alertRecipient) throw new Error('Missing required Script Properties PROJECT_ID, LOG_BUCKET, ALERT_RECIPIENT'); return { projectId, bucket, alertRecipient, dataset: p.getProperty('BQ_DATASET') || SAP_RESULT.DATASET }; }
function getOrCreateLabel_(name) { return GmailApp.getUserLabelByName(name) || GmailApp.createLabel(name); }
function isExpectedSender_(from) { return new RegExp(`(?:^|<)${SAP_RESULT.SENDER.replace('.', '\\.')}(?:>|$)`, 'i').test(from); }
function notify_(config, body) { MailApp.sendEmail(config.alertRecipient, '[ACTION REQUIRED] SAP result ingestion', body); }
function sanitizeError_(value) { return String(value).replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/g, '<EMAIL>').replace(/L\d+(?:-[A-Za-z0-9]+)?/g, '<ORDER_ITEM>').slice(0, 300); }
