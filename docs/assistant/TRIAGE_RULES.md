# TRIAGE_RULES — when to alert Boat (Gmail + Teams)

Version 1 (2026-11-25). Starting rules — expected to be wrong in places; Boat's feedback wins.

## Goal
Alert **only** when Boat must **decide** or **reply**. Everything else is silent.
Silence is the default; a missed FYI costs little, a noisy alert costs trust.

## Window
Each hourly run looks at messages received in the **last 70 minutes** (5-min overlap on each
side of the hour). Already-alerted items are not tracked across runs; the window is what stops
repeats. Exception: the **07:00 run** also covers 22:00–07:00 overnight.

## ALERT if ALL of these hold
1. Not sent by Boat, not an automated/no-reply/newsletter/notification sender.
2. Boat has not already replied after it (check the thread / chat for a later Boat message).
3. At least one of:
   - Boat is in **To** (email) or is **@mentioned / in a 1:1 chat / directly addressed by name**
     ("พี่โบ๊ท", "คุณโบ๊ท", "Boat", "K.Boat") in a group chat, **and** the message asks a question,
     requests approval/exception/waiver/sign-off, asks for a decision, or sets a deadline.
   - From K.Paul or K.Michael and addressed to Boat (To or direct) — any content.
   - Boat only in **CC**, but the text explicitly asks Boat by name to act/approve.
   - A data/dashboard problem reported to Boat or Boat's team ("ข้อมูลไม่ขึ้น", "dashboard ผิด",
     "ตัวเลขไม่ตรง") — BI owns this.

## Do NOT alert
- CC-only broadcasts with no direct ask to Boat (HR announcements, recruitment follow-ups,
  vendor notices, legal case updates addressed to others).
- Large group chats (>20 members) unless Boat is @mentioned or named.
- Messages Boat already answered; Boat's own messages; calendar auto-mails; system alerts
  already covered by the Data watch run.

## Priority (sort the alert by this, highest first)
| P | Meaning | Examples |
|---|---|---|
| P1 | From manager/CEO, or money/customer impact with deadline today, or production data broken | K.Paul asks for numbers; refund approval marked urgent; dashboard down for business users |
| P2 | Approval/decision requested of Boat, no same-day deadline | voucher/fee exception requests To: Boat; access requests |
| P3 | Question for Boat that needs a reply, low stakes | scheduling, clarifications |

Tie-break: older first within the same P.

## Alert format (push notification, ≤200 chars, one line, Thai)
`[P1] K.Paul: ขอตัวเลข X ภายในวันนี้ | [P2] คำขอยกเว้น voucher 2 เรื่อง | +1 P3`
Full list (sender, subject/first line, why it needs Boat, link) goes in the run's final message.
If nothing qualifies: no notification, final message = `ไม่มีเรื่องต้องตัดสินใจ/ตอบ (checked HH:MM)`.

## Never
- Never reply, send, forward, label, archive, mark read, or react on Boat's behalf.
- Never write message content into the repo (see README privacy rules).
