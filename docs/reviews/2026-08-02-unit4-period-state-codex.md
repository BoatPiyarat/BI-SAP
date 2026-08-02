# Unit 4 period state-machine self-review

Class: A

Verdict: **PASS FOR DEFINITION DEPLOY + ONE-TIME SEED; CLOSE CALL TIME-GATED**.

The definition preserves the live legacy consumer contract while adding explicit OPEN/CLOSED/
PLANNED history. Seed requires one active legacy row and an empty history table. Close requires the
authoritative stored timestamp, calendar adjacency, exactly one OPEN row, a PLANNED successor, and
an explicit actor/next closing time. Both history and compatibility changes occur in one BigQuery
transaction. The TEMP-only rehearsal proved the successful transition, date behavior, and rollback
after a deliberate mid-transaction failure.

The source does not permit closing July early. Production close remains blocked until current time
is at or after July's stored `closing_at` and the next closing timestamp is supplied.
