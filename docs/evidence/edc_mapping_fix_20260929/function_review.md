# Shared mapper update — independent source review

**PASS for helper update only**, SHA256 0c9e12ccc06b7a4715a84822b3f8a7098438169f861201e0a25953d2a6cfb77f. Final source includes authorized raw-method fallback (CHEQUE -> RCB-CHEQUE[-bank]), preserves known method mappings, and returns NULL channel for invalid ALL pairs while retaining ALL/ALL CMI. Unknown/NULL payment method remains unmapped. Does not approve consumer deployment or certify SAP master acceptance. No reviewer BQ queries or mutations.
