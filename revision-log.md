# Revision log — Agentic MSP Support Agent Lab (toc-v3)

Live test run 17 Nov 2026 (deployment 2474301). Scope of this revision: Getting Started through Exercise 5 Task 2. Exercise 5 Task 3 onward, Exercise 6 and Exercise 7 not yet re-tested (Ex5 T3 was blocked: the Senior Technician saw no environment in the Power Platform admin center until a role was granted).

## Updated
- getting-started.md — Sign In to the Azure CLI: new step for the "Sign in to all apps and websites on this device?" prompt (select **No, this app only**).
- exercise-1.md T1 step 4 — Foundry shortcut opens a page with **Sign in**; added the sign-in and the "Your project is set up" dialog (**Skip**).
- exercise-1.md T2 step 4 Note — no longer says the agent "serves the latest one" without qualification; explains the `[check] … pinned to version @latest` message from `Update-AgentDefinition.ps1`.
- setup/assets/labfiles/tools/New-KnowledgeIndex.ps1 — polls index statistics for up to 90 s before reporting "no vectors"; the first run reported a false "[problem] … Lab staff" message because statistics lag the indexer.

- exercise-3.md T4 step 3 — revision list: the previous (`baseline-`) revision stays Active at 0 % traffic after a deploy, and provisioning can leave two `baseline-` revisions. Seen again after each deploy in Ex4.
- exercise-5.md T1 step 1 — Agent ID object ID and client ID can be identical; what to do if servicedesk-write shows *never for N tool(s)*.
- exercise-5.md T2 step 3 — removed the `.env.example` hit (the file isn't in the repo); `az containerapp secret list` can print nothing instead of `[]` (also in Expected results).
- exercise-5.md T1 Troubleshooting — sign out and back in after the admin-center role is granted.
- exercise-5.md T4 step 1 Note — Tier 1 needs Foundry User; Foundry Agent Consumer alone doesn't open the project.

## Added
- Screenshots in `Instructions/media/screenshots/` from the live run (deployment 2474301; only the VM screen is captured, never the Environment panel). 66 placeholders are now replaced across Getting Started and Exercises 1 to 7. Where the environment had moved on from the step (for example TCK-10561 already triaged, so the Untriaged view shows four rows), the screenshot shows the current state and the step text is unchanged.
- Still pending (73), to capture on a fresh deployment: E1T1S2, E1T1S4, E1T2S3, E2T1S4, E3T1S1, E3T1S3, E3T2S2, E3T2S3-2, E3T4S1, E3T4S2, E3T4S3, E4T1S1-2, E4T1S2-1, E4T1S2-2, E4T2S1-1, E4T2S1-2, E4T3S2, E4T3S3, E4T3S4-1, E4T3S4-2, E4T4S1, E4T4S2, E4T4S3, E4T5S2, E4T5S3-1, E4T5S4-1, E5T1S1-2, E5T1S1-3, E5T1S2, E5T1S3, E5T2S2, E5T2S4, E5T3S1, E5T3S3, E5T3S4-1, E5T3S4-2, E6T1S1-1, E6T1S1-2, E6T1S1-3, E6T1S2, E6T1S3-1, E6T1S3-2, E6T2S1, E6T2S2-1, E6T2S2-2, E6T2S3-1, E6T2S3-2, E6T2S4, E6T2S5, E6T3S2, E6T3S3-1, E6T3S3-2, E6T3S4-1, E6T3S5, E7T1S2, E7T1S3-1, E7T1S3-2, E7T1S3-3, E7T1S3-4, E7T1S4-1, E7T1S4-2, E7T2S1, E7T2S2, GS1, GS2, GS3, GS4, GS5, GS6, GS7, GS8, GS9, GS11. Reasons: CloudLabs portal views (GS1 to GS9) are outside the VM; write steps already applied in this run can't be repeated (E4T1S2, E4T2S1, E4T3S4, E4T5S4-1, E5T3S3/S4); the gpt-5.1 deployment hit its tokens-per-minute limit on the heavy prompts (E4T3S2, E4T3S3, E7T1S2 to E7T1S4); and Entra, APIM, Key Vault, Log Analytics, Purview and Visual Studio Code views were not reached in this session.
- exercise-4.md T1 step 1 — Note that **Approve** opens a menu (select **Approve once**); its *Always approve…* options turn approval off and save a new agent version (this happened in the test run and broke the Ex5 approval checks); how to recover with `Update-AgentDefinition.ps1 -Reset` then `-Instructions`; the refuse button is **Deny**.
- exercise-1.md T2 step 5 — Note on **Open consent** for servicedesk-write and servicedesk-read, including the **Confirmation required** page and its "I have verified this request" checkbox. It appears on the lab's first agent prompt, not first in Exercise 2.
- exercise-1.md T1 Troubleshooting — row for **AuthorizationFailed** on `listSecrets` / `az group show -n labvm` (missing role assignment → contact support, not "az login again").

## Removed
- Nothing.

## Not changed (needs a decision or more evidence)
- **Ex5 T3 boundary test didn't refuse the write:** after Ticket Write was set to Business Unit in Service Desk Agent Write, the approved update_ticket_priority on TCK-10511 succeeded (correlation 429bb84b-…). The MCP server calls Dataverse with `CallerObjectId` impersonation, so Dataverse checks the impersonated user's privileges, and narrowing the application user's role may never block a write. The tester's account had also just been made System Administrator. Needs a design check before the task is kept as written.
- **Ex5 T4 Tier 1 username:** the CloudLabs value `Tier 1 Technician Username` = `tier1.technician@…` doesn't exist; the real account is `tier1technician@…` (User 01 UPN), with a password rather than a Temporary Access Pass. Fix the CloudLabs output value.
- **Provisioning:** Tier 1 needs Foundry User on the project (only Foundry Agent Consumer is assigned), and the Senior Technician needs an admin-center-visible role on the Power Platform environment.
- Ex5 T1/T3: Power Platform admin center lists no environment for the Senior Technician with only the Dataverse roles; the Service Desk app's Advanced Settings is greyed out too. Provisioning should grant an admin-center-visible role (System Administrator or Environment Admin on this environment), or the task should be rewritten. Not fixed in the guide.
- `get_similar_tickets` also missed open TCK-10521 in Ex4 T3.
- Deploy output piped through `Tee-Object` crashes with a cp1252 UnicodeEncodeError; consider `PYTHONIOENCODING=utf-8` in `Deploy-McpServer.ps1` (mcp-server repo, not this one).
- Citations render as raw markers (`【KB0007 – …】`, `【<guid>†source】`), not links. The guide's "select the citation link" steps (Ex1 T2 s5, Ex2 T1 s4) can't be followed as written.
- `get_similar_tickets` with `include_open = true` didn't return open TCK-10521 (Ex2 T1).
- Ex2 T3: agent cites CUST-019-PR1 instead of CUST-019-PR3 / Owen Fletcher.
- Environment tab shows `tier1.technician@…`; readiness check and validation scripts use different spellings.
- 136 `[SCREENSHOT PENDING …]` markers and 14 `REPLACE-WITH-VALIDATION-GUID` placeholders remain.
