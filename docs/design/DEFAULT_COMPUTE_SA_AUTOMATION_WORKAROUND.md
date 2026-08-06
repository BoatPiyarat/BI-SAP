# Default Compute service-account automation workaround

Decision date: 2026-08-06 (Boat).

Status: binding source/runbook direction; production remains fail-closed and delivery remains
disabled until the replacement activation artifacts pass Class-A review.

## Decision

`data@rabbit.co.th` and `piyaratt@rabbit.co.th` are not administrators and do not have
`run.services.setIamPolicy`. Do not retry Cloud Run IAM-policy grants, custom-role creation,
project/bucket IAM grants, or service-account IAM grants under either account.

Reuse the project's existing default Compute service account for the unattended V3 components:

```text
919786098205-compute@developer.gserviceaccount.com
```

This is the identity already used by the live `v3-nightly-orchestrator`. The workaround deliberately
accepts the broader pre-existing identity instead of creating the dedicated least-privilege
identities described in the superseded administrator runbooks. It does **not** authorize adding a
role to that identity.

## Binding constraints

1. No command containing `add-iam-policy-binding`, `set-iam-policy`, custom-role creation, or
   service-account IAM mutation is part of this path.
2. Deploy runtime resources with the default Compute service account only.
3. Reuse existing effective permissions. Before activation, use read-only describes/checkers to
   prove that each required operation is available.
4. If a deploy or rehearsal reports a missing permission, stop and record the exact denied
   permission. Do not retry with `data@rabbit.co.th`, `piyaratt@rabbit.co.th`, a public principal,
   or a newly invented grant.
5. Cloud Run services stay non-public. `allUsers` and `allAuthenticatedUsers` are hard failures.
6. `delivery_enabled` stays `false`; recurring schedules stay `PAUSED` until the complete rehearsal
   and production cutover gates pass.
7. This decision changes identity/activation mechanics only. It does not relax exact filename,
   create-only generation, row conservation, ACK/reject, second-refresh, completeness, cutoff, or
   alert gates.

## Replacement resource contract

| Component | Runtime/caller identity |
|---|---|
| `v3-nightly-orchestrator` | default Compute service account |
| `sap-delivery-promoter` | default Compute service account |
| recurring `v3-nightly-orchestrator` scheduler OAuth | default Compute service account |
| `sap-post-import-dispatcher` | default Compute service account |
| `sap-post-import-watchdog` | default Compute service account |
| post-import Pub/Sub push OIDC | default Compute service account |
| post-import watchdog scheduler OAuth | default Compute service account |

The activation checkers validate this exact contract and public-access safety. They no longer
require dedicated service accounts, custom roles, conditional bucket bindings, or a Cloud Run
service-level `run.invoker` binding. Those were administrator-path requirements and cannot be
created by the available accounts.

## Read-only preflight and fail-closed activation

Run the checkers without changing live state:

```powershell
powershell -File scripts/check_v3_delivery_control_plane.ps1
powershell -File scripts/check_post_import_activation.ps1
```

The delivery checker must return JSON rather than terminate. In particular, it must not call the
nonexistent `gcloud workflows get-iam-policy` command identified by review
`RQ-20260805-2149-v3-delivery-control-plane-gate`.

A green identity/configuration preflight is necessary but not sufficient. Before unpausing:

1. Keep the scheduler PAUSED and `delivery_enabled:false`.
2. Perform the existing no-write/offline tests.
3. Use one controlled, non-production rehearsal to prove authenticated invocation and exact
   permission sufficiency. Do not turn a permission failure into an IAM change.
4. Prove no GCS production object, SAP-visible file, procedure mutation, or recurring execution was
   caused by the preflight itself.
5. Record the rehearsal evidence and obtain Class-A review.

If the existing default service account cannot invoke a required private service, this workaround
is blocked at that boundary. The permitted response is to redesign that call path using an
already-authorized GCP primitive or obtain an administrator action later—not to make the service
public.

## Superseded instructions

The IAM/deployment command sequences in:

- `docs/design/V3_DELIVERY_CONTROL_PLANE.md`
- `docs/design/POST_IMPORT_ADMIN_COMPLETION.md`

are retained as history only. Their dedicated identities and IAM mutations must not be run unless
Boat makes a newer explicit decision.

