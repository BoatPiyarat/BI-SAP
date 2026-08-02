# Issue tracker: GitHub

Issues and PRDs for this repository live as GitHub issues in `BoatPiyarat/BI-SAP`. Use the `gh`
CLI from this clone so the remote determines the repository.

## Conventions

- Create, read, comment, label, and close issues with `gh issue`.
- When a skill says “publish to the issue tracker”, create a GitHub issue.
- When a skill says “fetch the relevant ticket”, use `gh issue view <number> --comments`.
- Pull requests are not a triage/request surface.
- GitHub sub-issues and native dependencies are preferred for `/wayfinder`; fall back to explicit
  task-list and `Blocked by:` links only when the native feature is unavailable.

