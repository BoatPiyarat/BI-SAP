# Domain docs

This is a single-context repository. Engineering skills may read a root `CONTEXT.md` and relevant
ADRs under `docs/adr/` when those files exist. Their absence is not an error; create them lazily
only when domain modeling resolves new terminology or an architectural decision.

The SAP project's existing canonical hierarchy remains authoritative:

1. `docs/knowledge/10_SAP_CONTEXT.md` for confirmed business rules and terminology.
2. `docs/knowledge/20_SAP_PROGRESS.md` for current implementation state.
3. `docs/AS_BUILT_V3.md` for deployed V3 objects.
4. `docs/INPUTS_NEEDED.md` for human-owned decisions.

Use canonical vocabulary and surface any proposed ADR that conflicts with these sources rather
than silently overriding it.
