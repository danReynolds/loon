# Ideas to revisit

This folder records possible features and optimizations that are not part of the current implementation plan. Keep enough context to make a future decision without repeating the investigation. An idea is not a commitment to ship it.

Use one Markdown file per idea, named with a short, lowercase, hyphenated topic. Add it to the index below. Use the template's sections in order; write `Not measured` or `Unknown` where evidence is missing rather than treating an assumption as a result.

Statuses are `Exploring` (actively investigating), `Parked` (waiting for a reason to revisit), `Accepted` (selected for implementation, with an issue or PR link), and `Closed` (declined or superseded, with a reason). Update the date, evidence, and status when a decision changes. Keep measurements tied to their workload, runtime, baseline, and limitations.

## Index

| Idea | Status | Revisit when |
|---|---|---|
| [Adaptive query sorting](adaptive-query-sorting.md) | Parked | App profiling shows full sorting dominates large query updates with few changed documents. |

## Template

```markdown
# Descriptive feature name

- Status: Exploring | Parked | Accepted | Closed
- Updated: YYYY-MM-DD

## Problem

Describe the user or application workload, current behavior, and its cost. Include a concrete example.

## Proposal

Describe the smallest useful change, its scope, and any fallback behavior.

## Evidence

Record observations or measurements with the date, baseline, workload, runtime, and validation. Distinguish measured results from expectations. State what remains unproven.

## Costs and risks

Record complexity, memory or runtime costs, behavioral compatibility, and workloads that may regress.

## Revisit when

Name the evidence or product need that would justify further work.

## Next validation

List the smallest experiments or checks needed to decide whether to implement it.

## References

Link related code, issues, PRs, reports, or prototypes. Identify local-only artifacts and commits explicitly.
```
