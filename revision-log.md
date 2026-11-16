# Revision log — Agentic MSP Support Agent Lab (toc-v3)

Live test run 17 Nov 2026 (deployment 2474301). Scope of this revision: Getting Started, Exercise 1, Exercise 2 Tasks 1–3. Exercises 2 T4 to 7 not yet re-tested.

## Updated
- getting-started.md — Sign In to the Azure CLI: new step for the "Sign in to all apps and websites on this device?" prompt (select **No, this app only**).
- exercise-1.md T1 step 4 — Foundry shortcut opens a page with **Sign in**; added the sign-in and the "Your project is set up" dialog (**Skip**).
- exercise-1.md T2 step 4 Note — no longer says the agent "serves the latest one" without qualification; explains the `[check] … pinned to version @latest` message from `Update-AgentDefinition.ps1`.
- setup/assets/labfiles/tools/New-KnowledgeIndex.ps1 — polls index statistics for up to 90 s before reporting "no vectors"; the first run reported a false "[problem] … Lab staff" message because statistics lag the indexer.

## Added
- exercise-1.md T2 step 5 — Note on **Open consent** for servicedesk-write and servicedesk-read, including the **Confirmation required** page and its "I have verified this request" checkbox. It appears on the lab's first agent prompt, not first in Exercise 2.
- exercise-1.md T1 Troubleshooting — row for **AuthorizationFailed** on `listSecrets` / `az group show -n labvm` (missing role assignment → contact support, not "az login again").

## Removed
- Nothing.

## Not changed (needs a decision or more evidence)
- Citations render as raw markers (`【KB0007 – …】`, `【<guid>†source】`), not links. The guide's "select the citation link" steps (Ex1 T2 s5, Ex2 T1 s4) can't be followed as written.
- `get_similar_tickets` with `include_open = true` didn't return open TCK-10521 (Ex2 T1).
- Ex2 T3: agent cites CUST-019-PR1 instead of CUST-019-PR3 / Owen Fletcher.
- Environment tab shows `tier1.technician@…`; readiness check and validation scripts use different spellings.
- 136 `[SCREENSHOT PENDING …]` markers and 14 `REPLACE-WITH-VALIDATION-GUID` placeholders remain.
