Repeated RCL receipts are suppressed when their installment or latest period is already Paid. This change routes recent outstanding receipts by invoice identity, preserves the ordinary fallback invoice, prevents missing paid lineage from disappearing silently, and removes the unrelated order-year cutoff from the Motor newpayment wrapper.

Validated against the deployed dashboard: 26 receipt scenarios and 5 gate scenarios pass; positional schemas match; no baseline payload removals, duplicate event identities or incomplete schedules. Both reported additional receipts appear. Exact executed-source bindings and remaining blockers are in docs/FINDINGS_RCL_DOWNSTREAM_20260927.md.

Source handoff only, not deployed. Eight later-period principal mappings await a business decision; operational holds and carried-spine import idempotency remain release gates. V3 remains held.
