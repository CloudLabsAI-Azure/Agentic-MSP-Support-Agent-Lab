# Screenshot To-Do

> **Delivery path: Phase 5 of 8, run the pilot.** Capture these screenshots during the pilot walk-through,
> after the template is published and the environment is prepared. Start of the path: [README.md](README.md#delivery-path).

**Who:** the lab author and the CloudLabs engineer, during the pilot. **Time:** about 7 hours for 136 screenshots at about 3 minutes each.

Every screenshot the lab guide still needs, generated from the screenshot placeholder markers in the guide
pages (masterdoc.json) by `tools/qa/make_screenshot_todo.py`. Regenerate it after editing the guide, and do not edit it by hand.

How to produce them:

- Capture with a **participant** account (the role set learners get), so the screenshots show exactly what
  learners see. Capture admin-only screens (marked Read Only in the guide) with the instructor account.
- Use the lab's fictional company and seeded data. Never show a real customer, a real person's name or
  email address, or a secret or credential: passwords, Temporary Access Passes, keys, connection strings, tokens, consent URLs or any file or setting that holds one. Crop to the relevant pane.
- Add numbered balloons where the step text uses **(1)**, **(2)** markers.
- Save each image as `<ID>.png` in the media folder next to its page (`Instructions/media`), then replace
  the marker line, at the same indentation, with a Markdown image embed whose alt text is the description
  and whose path is `./media/<ID>.png`.
- `source: learn <url>` gives a Microsoft Learn image to use as the reference for framing: capture the real
  environment rather than copying the Learn image. `source: reuse` means the standard CloudLabs
  getting-started image, and `source: capture` means a new capture in the pilot.

**Total: 136** (6 reuse, 4 with a Microsoft Learn reference, 126 capture only).

## getting-started.md

[Instructions/getting-started.md](Instructions/getting-started.md): 11 screenshots.

| ID | What it must show | Source | Line |
|---|---|---|---|
| GS1 | Lab environment with the virtual machine on the left and the lab guide on the right | reuse | 93 |
| GS2 | Environment tab showing the lab credentials and resource details | reuse | 99 |
| GS3 | Split Window button in the top right corner of the lab guide | reuse | 105 |
| GS4 | Resources tab with the virtual machine Start, Stop, and Restart controls | reuse | 111 |
| GS5 | Zoom control next to the lab timer | reuse | 119 |
| GS6 | Lab Validation tab with the Validate button per step | reuse | 128 |
| GS7 | Sign-in screen with the username field highlighted | capture | 154 |
| GS8 | Sign-in screen with the Temporary Access Pass field highlighted | capture | 160 |
| GS9 | Resource groups page with the lab resource group selected | capture | 178 |
| GS10 | PowerShell 7 window showing az account show output with the Senior Technician account | capture | 209 |
| GS11 | Lab VM desktop with the lab shortcuts and Lab notes.txt | capture | 217 |

## exercise-1.md

[Instructions/exercise-1.md](Instructions/exercise-1.md): 14 screenshots.

| ID | What it must show | Source | Line |
|---|---|---|---|
| E1T1S2 | Lab readiness check window with every component Ready | capture | 50 |
| E1T1S3 | Service Desk app Tickets list with the Open Tickets view and its row count | capture | 75 |
| E1T1S4 | Agent playground Tools section listing servicedesk-read and servicedesk-write with no knowledge source | capture | 85 |
| E1T1S5 | PowerShell 7 window with the get_ticket result for TCK-10524 and its correlation_id | capture | 97 |
| E1T2S1 | New-KnowledgeIndex.ps1 -ReviewOnly output listing the fields and their purpose | capture | 126 |
| E1T2S3 | Azure AI Search Indexes page with servicedesk-knowledge and 753 documents | capture | 138 |
| E1T2S4 | Agent playground Tools section with the Azure AI Search tool and both MCP tools | capture | 150 |
| E1T2S5 | Playground answer about RBA-1043 citing KB0007 | capture | 166 |
| E1T3S1 | Answer about Woodgrove Bank citing its profile and documents | capture | 209 |
| E1T3S2 | Answer citing KB0031 with the client 3.8.x and 3.9.x range | capture | 225 |
| E1T3S3 | Answer saying the data does not contain Woodgrove Bank's IT budget | capture | 241 |
| E1T4S1 | KB0031 and KB0058 in the Service Desk app with their Applies to fields | capture | 277 |
| E1T4S2 | Answer recommending KB0058 for Woodgrove Bank with the firmware and client versions | capture | 293 |
| E1T5S1 | List of sources with identifiers and reasons | capture | 327 |

## exercise-2.md

[Instructions/exercise-2.md](Instructions/exercise-2.md): 13 screenshots.

| ID | What it must show | Source | Line |
|---|---|---|---|
| E2T1S1 | Untriaged Tickets view with five rows, and TCK-10561 open with its Description and empty Priority, Category and Assigned Technician | capture | 34 |
| E2T1S2 | Playground answer that restates TCK-10561 and lists KB0023 tickets and the open TCK-10521 with citations | capture | 48 |
| E2T1S3 | Playground answer explaining the symptom, cause and trigger behind each match and naming decoys such as TCK-10532 | capture | 68 |
| E2T1S4 | TCK-10035 in the Service Desk app with Related Article KB0023, Priority P3 Medium, Assigned Technician Priya Raman and Escalation Level Account Manager | capture | 74 |
| E2T2S2 | Playground summary of Woodgrove Bank's six open tickets by category with remaining business hours, and its resolved history | capture | 163 |
| E2T2S3 | Playground answer flagging TCK-10518, TCK-10548 and TCK-10553 as one KB0058 issue and listing the eight escalated tickets with their levels | capture | 184 |
| E2T2S4 | Open Tickets view filtered on the Customer column for Woodgrove Bank, showing six rows | capture | 192 |
| E2T3S2 | Playground recommendation for TCK-10561 with Backup and Recovery, Storage quota, P3 Medium, Priya Raman, 32 business hours, CUST-019-PR3 and the KB0023 history cited | capture | 238 |
| E2T3S3 | Playground answer for TCK-10560 asking for the system, the error, the people affected and what last time means, with no triage | capture | 256 |
| E2T4S1 | Playground answer listing TCK-10540, TCK-10524 and TCK-10504 as closest to breach and TCK-10501 and TCK-10512 as breached | capture | 294 |
| E2T4S2 | Playground table of the five tickets with tier, priority, target, elapsed and remaining business hours and the calculation time | capture | 320 |
| E2T4S3-1 | TCK-10540 SLA section with Opened On, SLA Target 4.00, SLA Elapsed 3.50, SLA Remaining 0.50, SLA Due On, SLA Status At Risk and SLA Calculated On | capture | 330 |
| E2T4S3-2 | Open Tickets by SLA Remaining view with TCK-10501, TCK-10512, TCK-10540, TCK-10524 and TCK-10504 as the first five rows and 57 rows in total | capture | 334 |

## exercise-3.md

[Instructions/exercise-3.md](Instructions/exercise-3.md): 18 screenshots.

| ID | What it must show | Source | Line |
|---|---|---|---|
| E3T1S1 | Visual Studio Code with C:\LabFiles\mcp-server in the Explorer and the terminal showing the v3.0.0 commit | capture | 38 |
| E3T1S2 | Invoke-McpTool.ps1 -List output with 16 read tools on /read/mcp, approval not required, and 7 write tools on /write/mcp, approval required | capture | 59 |
| E3T1S3 | dataverse_repository.py in Visual Studio Code with DataverseRepository.get_ticket and the CallerObjectId line in _request | capture | 95 |
| E3T1S4 | Terminal with the 16 read tools and the relecloud/permission text of each | capture | 105 |
| E3T2S1 | Playground answer for TCK-10524 with its fields, its SLA figures and the correlation ID of the get_ticket call | capture | 141 |
| E3T2S2 | TCK-10524 in the Service Desk app with the Summary and SLA sections matching the agent's answer | capture | 166 |
| E3T2S3-1 | Show-McpServerLog.ps1 row for get_ticket with read, ok, Allowed, dataverse, the Senior Technician and the correlation ID | capture | 182 |
| E3T2S3-2 | Log Analytics result of the query with the get_ticket row for TCK-10524 on the read endpoint and its correlation ID | capture | 199 |
| E3T3S1 | Playground answer saying that ticket TCK-99999 does not exist, with no status or priority | capture | 242 |
| E3T3S2-1 | Terminal with the INVALID_ARGUMENT result of get_ticket called with no arguments, isError True | capture | 280 |
| E3T3S2-2 | Playground answer reporting INVALID_ARGUMENT for ticket_number, or asking which ticket to read | capture | 294 |
| E3T3S3-1 | Playground answer with the TICKET_NOT_FOUND result as JSON, with code, message, source, retryable, hint and correlation_id | capture | 324 |
| E3T3S3-2 | Show-McpServerLog.ps1 rows for the TICKET_NOT_FOUND call and the INVALID_ARGUMENT calls | capture | 344 |
| E3T3S4 | Playground answer finding TCK-10524 through a search after the TCK-99999 error | capture | 358 |
| E3T4S1 | tools_read.py with the new sentence in the get_sla_status docstring, and the git diff output in the terminal | capture | 413 |
| E3T4S2 | Deploy-McpServer.ps1 stage 1/3 with the build log, and az acr repository show-tags listing 3.0.0 and 3.0.1 | capture | 437 |
| E3T4S3 | Deploy-McpServer.ps1 stages 2/3 and 3/3, the revision table, and the Build took and full cycle line | capture | 456 |
| E3T4S4 | Playground answer quoting the get_sla_status description that ends with the new business hours sentence | capture | 488 |

## exercise-4.md

[Instructions/exercise-4.md](Instructions/exercise-4.md): 29 screenshots.

| ID | What it must show | Source | Line |
|---|---|---|---|
| E4T1S1-1 | Invoke-McpTool.ps1 -List output with the seven write tools showing Kind write, Endpoint /write/mcp and Approval required | capture | 57 |
| E4T1S1-2 | Get-AgentIdentity.ps1 tools table with servicedesk-read approval never and servicedesk-write approval always for every tool the endpoint lists | capture | 59 |
| E4T1S2-1 | Playground approval request for update_ticket_priority with ticket_number TCK-10544, priority 3 and a reason | capture | 79 |
| E4T1S2-2 | Agent's report of the change from P4 Low to P3 Medium with the 16-hour SLA target, the audit note and the correlation ID | capture | 81 |
| E4T1S3 | Declined approval request for update_ticket_status on TCK-10544, and the agent saying the call was not approved and the ticket is unchanged | capture | 103 |
| E4T1S4-1 | TCK-10544 form with Priority P3 Medium, Status New, SLA Target (business hours) 16.00 and the Last Correlation ID | capture | 120 |
| E4T1S4-2 | All Agent Actions view with the update_ticket_priority row for TCK-10544, Allowed and Succeeded, and its correlation ID | capture | 122 |
| E4T1S4-3 | Show-McpServerLog.ps1 output with the update_ticket_priority row, outcome ok and Allowed, and no update_ticket_status call | capture | 138 |
| E4T2S1-1 | Playground approval request for add_public_reply on TCK-10524 with the reply text as the body | capture | 193 |
| E4T2S1-2 | Agent's report of the two notes with their codes, visibility and correlation IDs | capture | 195 |
| E4T2S2 | TCK-10524 Related Ticket Notes with the new reply marked Customer visible and the new note marked Internal, both by Service desk agent (MCP) | capture | 212 |
| E4T2S3 | Playground draft of a customer update for TCK-10524 with no internal note content | capture | 228 |
| E4T3S1 | Playground answer restating TCK-10561 from A. Datum Corporation with no priority, category or technician | capture | 285 |
| E4T3S2 | Playground answer with A. Datum's profile and CUST-019-PR3, the KB0023 history and TCK-10521, KB0023 and RB-002, and Priya Raman available | capture | 306 |
| E4T3S3 | Playground recommendation for TCK-10561: Backup and Recovery, Storage quota, P3 Medium with 32 business hours, Priya Raman, each with its sources | capture | 330 |
| E4T3S4-1 | Playground approval request for update_ticket_priority on TCK-10561 with priority 3 and a reason that cites the KB0023 history | capture | 354 |
| E4T3S4-2 | Agent's report of the three outcomes on TCK-10561, each with its correlation ID | capture | 356 |
| E4T3S5-1 | TCK-10561 form with In Progress, P3 Medium, Backup and Recovery, Storage quota, Priya Raman and SLA Target (business hours) 32.00 | capture | 373 |
| E4T3S5-2 | All Agent Actions view with the three TCK-10561 rows, Allowed and Succeeded | capture | 375 |
| E4T4S1 | policy.py with MAX_OPEN_TICKETS_LIMIT = 50, and the limit 30 call returning ok True and 30 tickets | capture | 416 |
| E4T4S2 | policy.py with MAX_OPEN_TICKETS_LIMIT = 20 and __init__.py with version 3.0.2 in Visual Studio Code | capture | 448 |
| E4T4S3 | Deploy-McpServer.ps1 output with the new revision ready at version 3.0.2, the revision table and the build and cycle times | capture | 458 |
| E4T4S4 | Invoke-McpTool.ps1 output with isError True, INVALID_ARGUMENT, received 30 and the constraint le 20 | capture | 476 |
| E4T5S2 | Lab notes.txt with the scoped tool line completed for escalate_ticket | capture | 525 |
| E4T5S3-1 | tools_write.py in Visual Studio Code with the escalate_ticket block at the end of register(), after add_public_reply | capture | 573 |
| E4T5S3-2 | Invoke-McpTool.ps1 -List output with escalate_ticket as a write tool on /write/mcp with Approval required | capture | 575 |
| E4T5S4-1 | Playground approval request for escalate_ticket with ticket_number TCK-10561, level Account Manager and a reason | capture | 597 |
| E4T5S4-2 | TCK-10561 Escalation section with Escalated, Escalation Level Account Manager, Escalated On (UTC) and Escalation Reason | capture | 603 |
| E4T5S4-3 | All Agent Actions view with the escalate_ticket row for TCK-10561, Allowed and Succeeded | capture | 605 |

## exercise-5.md

[Instructions/exercise-5.md](Instructions/exercise-5.md): 20 screenshots.

| ID | What it must show | Source | Line |
|---|---|---|---|
| E5T1S1-1 | PowerShell 7 window with Get-AgentIdentity.ps1 output: the Agent ID object ID and client ID, the tools table and the six-hop identity map | capture | 38 |
| E5T1S1-2 | Microsoft Entra admin center, Entra ID > Agents > Agent identities, with the agent identity found by its object ID | capture | 47 |
| E5T1S1-3 | Power Platform admin center, Application users, Details of the id-mcp application user with its Microsoft Entra application ID and the roles Service Desk Agent Read, Service Desk Agent Write and Delegate | capture | 49 |
| E5T1S2 | API Management, Service Desk MCP (write) policy with validate-azure-ad-token, the x-user-oid and x-backend-key headers and the deletion of Authorization | capture | 63 |
| E5T1S3 | Agent identity details in the Microsoft Entra admin center with no permissions or roles granted | capture | 83 |
| E5T2S1 | Key vault Secrets list with mcp-backend-key and its properties visible to a Key Vault Reader, and the az keyvault secret show command refused with Forbidden | [Learn reference](https://learn.microsoft.com/azure/key-vault/media/rbac/image-12.png) | 126 |
| E5T2S2 | Log Analytics results with key_vault_secret_read and startup lines for each MCP server revision, key_source key vault | capture | 144 |
| E5T2S3 | PowerShell 7 window with the two git grep searches, az containerapp secret list returning an empty list, and the table of environment variables | capture | 174 |
| E5T2S4 | Log Analytics results with SecretGet rows for mcp-backend-key: status 200 by the MCP server's identity at each start, status 200 by API Management's identity, and the refused read with status 403 | capture | 201 |
| E5T3S1 | Service Desk Agent Write in the security role editor, Tables tab, Custom Tables with Ticket Write, Append and Append to at Organization | capture | 246 |
| E5T3S2 | Service Desk Agent Write, Ticket row with Write set to Business Unit and Append and Append to still at Organization | capture | 254 |
| E5T3S3 | Playground with the approved update_ticket_priority call on TCK-10511 and the agent reporting that Dataverse refused the change | capture | 272 |
| E5T3S4-1 | Agent answer quoting DATAVERSE_ACCESS_DENIED, source dataverse, status 403, the code 0x80048306 and the Dataverse message, with the correlation ID | capture | 288 |
| E5T3S4-2 | Log Analytics row for update_ticket_priority on TCK-10511: outcome denied, Denied by Dataverse, decided by dataverse, PATCH with status 403 | capture | 308 |
| E5T4S1 | InPrivate Edge window with the Foundry portal signed in as the Tier 1 Technician, on the Playground tab of msp-support-agent | capture | 357 |
| E5T4S2-1 | Open Consent in the Tier 1 Technician's playground | [Learn reference](https://learn.microsoft.com/azure/foundry/media/mcp/foundry-open-consent.png) | 371 |
| E5T4S2-2 | Tier 1 Technician's playground with the approved update_ticket_priority call on TCK-10543 refused by Dataverse | capture | 377 |
| E5T4S3 | Senior Technician's playground with the approved update_ticket_priority call, and TCK-10543 in the Service Desk app with Priority P2 High, SLA Target 8 and the Last Correlation ID | capture | 397 |
| E5T4S4-1 | Agent Actions view with the denied and the allowed update_ticket_priority rows on TCK-10543 and their user names | capture | 407 |
| E5T4S4-2 | Audit History of TCK-10543 with the priority change from P3 Medium to P2 High by the Senior Technician | [Learn reference](https://learn.microsoft.com/power-platform/admin/media/dataverse-audit-log-single-record.png) | 409 |

## exercise-6.md

[Instructions/exercise-6.md](Instructions/exercise-6.md): 20 screenshots.

| ID | What it must show | Source | Line |
|---|---|---|---|
| E6T1S1-1 | Playground answer listing Woodgrove Bank's three contacts with their email addresses and the phone numbers reported as restricted | capture | 49 |
| E6T1S1-2 | Email column of the Contact table with Advanced options expanded and Enable column security selected | [Learn reference](https://learn.microsoft.com/power-platform/admin/media/field-security-advanced-options-enable.png) | 55 |
| E6T1S1-3 | Contact Phone Protection, Column Permission tab, with Read Allowed on the contact columns emailaddress1, telephone1 and mobilephone | capture | 59 |
| E6T1S2 | Playground answer listing the three Woodgrove Bank contacts with email, phone and mobile reported as restricted | capture | 77 |
| E6T1S3-1 | Playground answer that declines to guess Elif Evans's email address because it is restricted | capture | 93 |
| E6T1S3-2 | Service Desk app Customer Contacts view filtered on Woodgrove Bank, with Email, Business Phone and Mobile Phone visible | capture | 99 |
| E6T2S1 | Purview Data loss prevention Policies with Relecloud Service Desk card numbers open, showing the app location and the Credit Card Number rule | capture | 144 |
| E6T2S2-1 | Get-DocumentLabel.ps1 output with the label Relecloud Confidential, Enabled true and your tenant ID | capture | 156 |
| E6T2S2-2 | Purview Information Protection Sensitivity labels list with Relecloud Confidential | capture | 158 |
| E6T2S3-1 | Playground answer reporting the internal note on TCK-10521 as withheld by a Microsoft Purview DLP policy, with its correlation ID | capture | 174 |
| E6T2S3-2 | Playground answer reporting CONTENT_BLOCKED_BY_LABEL for Woodgrove-Bank-Secure-Gateway-configuration.docx, with its correlation ID | capture | 190 |
| E6T2S4 | Show-McpServerLog.ps1 rows for get_ticket_notes (ok) and get_customer_document (blocked, CONTENT_BLOCKED_BY_LABEL) with their correlation IDs | capture | 208 |
| E6T2S5 | Purview DLP Activity explorer filtered on DLP rule matched, with the event for the TCK-10521 note selected | capture | 214 |
| E6T3S1 | TCK-10544 in the Service Desk app with Priority P3 Medium and the Traceability section showing Last Correlation ID | capture | 254 |
| E6T3S2 | Log Analytics results for the agent run of the TCK-10544 priority change, with the tool arguments and a tool result that ends with the correlation ID | capture | 275 |
| E6T3S3-1 | ContainerAppConsoleLogs result for update_ticket_priority with Authorization Allowed, the PATCH on spk_tickets and the outcome ok | capture | 296 |
| E6T3S3-2 | API Management result with the servicedesk-write request (HTTP 200) and the tools/call row for update_ticket_priority | capture | 316 |
| E6T3S4-1 | TCK-10544 Audit History with the Priority change from P4 Low to P3 Medium by the Senior Technician | capture | 322 |
| E6T3S4-2 | All Agent Actions view with the update_ticket_priority row for TCK-10544, Allowed and Succeeded, and its correlation ID | capture | 324 |
| E6T3S5 | Get-ActionTrail.ps1 Summary and Sources checked for the TCK-10544 priority change, every source Found, with the evidence file paths | capture | 338 |

## exercise-7.md

[Instructions/exercise-7.md](Instructions/exercise-7.md): 11 screenshots.

| ID | What it must show | Source | Line |
|---|---|---|---|
| E7T1S1-1 | Service Desk app, Untriaged Tickets view listing TCK-10562 from Consolidated Messenger and TCK-10559 from Lucerne Publishing | capture | 30 |
| E7T1S1-2 | TCK-10562 form with Status New, Channel Phone, Requester Victor Murphy, no priority, category or technician, and the description | capture | 32 |
| E7T1S2 | Playground answer for TCK-10562 citing CUST-020-PR3, KB0133, RB-005 and CDOC-032, recommending Line-of-Business App, Certificate, P2 High and Daniel Cho, and keeping TCK-10559 and TCK-10524 apart | capture | 56 |
| E7T1S3-1 | Playground approval request for update_ticket_priority with ticket_number TCK-10562, priority 2 and a reason that cites CUST-020-PR3 | capture | 81 |
| E7T1S3-2 | Agent's report of the four outcomes on TCK-10562, each with its correlation ID | capture | 83 |
| E7T1S3-3 | TCK-10562 form after the writes: In Progress, P2 High, Line-of-Business App, Certificate, Daniel Cho and SLA Target (business hours) 16 | capture | 93 |
| E7T1S3-4 | Agent Actions, All Agent Actions view with the four TCK-10562 rows, Allowed and Succeeded, with their correlation IDs | capture | 95 |
| E7T1S4-1 | PowerShell 7 window with the Get-ActionTrail.ps1 Summary and Sources checked for the TCK-10562 priority change, every source Found | capture | 109 |
| E7T1S4-2 | File Explorer showing C:\LabFiles\evidence with ten files, and the TCK-10562-priority.md preview in Visual Studio Code | capture | 135 |
| E7T2S1 | Lab notes.txt Business case section with What the agent does, Controls and Evidence from this lab completed, each claim followed by its evidence | capture | 175 |
| E7T2S2 | Lab notes.txt with every line of the Business case section completed and saved | capture | 187 |

---

**Next:** finish the rest of the pilot checklist, then deliver the session (Phase 6).
