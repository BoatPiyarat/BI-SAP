Hi Attila, hope you're having a good Friday — no rush on this, Monday is totally fine.

`sap-extract-schedule` has been failing every night for the past 3 nights (07-22 to 07-24), 401 UNAUTHENTICATED. `sap-extract-job`'s IAM policy is empty. Checked the audit logs — turns out this probably never actually got granted in the first place, not that it regressed: I found someone already tried this exact fix on 07-13 via Cloud Shell and got PERMISSION_DENIED, same as I did tonight. Neither of us has `run.jobs.setIamPolicy` on this resource — only you do, so it needs your account specifically:

```
gcloud run jobs add-iam-policy-binding sap-extract-job \
  --region=asia-southeast1 --project=pacific-plating-282708 \
  --member="serviceAccount:sap-bucket-csv@pacific-plating-282708.iam.gserviceaccount.com" \
  --role="roles/run.invoker"
```

Nothing's broken beyond the automation — someone's been running the extract manually to cover it in the meantime. Thanks, enjoy your weekend!
