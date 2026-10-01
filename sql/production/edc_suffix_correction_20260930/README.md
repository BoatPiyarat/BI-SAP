# Correct EDC bank suffix only

Supersedes edc_mapping_20260929 for the 15 view and 4 routine definitions here. Keep EDC EDC for existing EDC, derive only its bank suffix, omit suffix when unknown. Original non-EDC branches are restored. The shared helper remains installed, but these EDC callers use literal EDC. User approved correction of production legacy and downstream objects.

Validation and review: docs/evidence/edc_suffix_correction_20260930. No interface file or historical SAP write. Metadata backup: local outputs/edc_suffix_correction_20260930/production_before_correction.json.
