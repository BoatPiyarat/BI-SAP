# Boat's proactive assistant — context home

Purpose: durable memory for the scheduled Claude runs that watch Boat's inbox/Teams and BI data.
Every scheduled run is a **fresh session** with no memory; it reads these files first.
This folder is the only place the assistant "learns". It is separate from the SAP knowledge
base (`docs/knowledge/`) and does not change any SAP project rule in `docs/AGENT_RULES.md`.

| File | What it holds | Who updates it |
|---|---|---|
| `PROFILE.md` | Who Boat is, working style, people map | Claude, when Boat states a fact |
| `TRIAGE_RULES.md` | What deserves an alert, priority scheme, noise patterns | Claude, on Boat's feedback |
| `DATA_WATCH.md` + `data_watch.sql` | Daily BigQuery health + KPI checks and thresholds | Claude, on Boat's feedback |
| `FEEDBACK_LOG.md` | Append-only log of Boat's corrections and what changed | Claude, every time |

## Scheduled runs (claude.ai scheduled tasks, fresh session per run)
| Name | Schedule (ICT) | Does |
|---|---|---|
| `Inbox triage — hourly` | hourly 07:00–22:00, every day | Gmail + Teams → push alert only if a decision/reply is needed |
| `Data watch — daily` | 07:47 every day | Runs `data_watch.sql` → push alert only on ALERT/WARN |

## Learning loop
1. A run alerts Boat (push notification; details in that run's session).
2. Boat replies in that session or any session, e.g. "อันนี้ไม่ต้อง alert", "คนนี้ P1 เสมอ".
3. Claude edits the relevant rule file, appends one line to `FEEDBACK_LOG.md`, commits and pushes
   to the branch named in the scheduled-task prompt.
4. The next run reads the new rule. Nothing is learned that is not written here.

## Privacy rules for this folder (hard)
- **Never** copy email or chat bodies, attachments, customer data, order numbers, amounts from
  messages, HR/legal case details, or anything sensitive into these files. Store **rules and
  patterns only** (e.g. "voucher-exception requests addressed To: Boat = needs decision, P2").
- People are recorded by role and work email only, and only when Boat states the role.
- Run outputs (the actual alerts) stay in the run's session, not in git.
