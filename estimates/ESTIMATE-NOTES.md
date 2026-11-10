# Estimate notes: Agentic MSP Support Agent Guided Lab (TOC v3)

Arithmetic and meters behind `Cost-Estimation-Agentic-MSP-Support-Agent.xlsx` (generated from `cost-estimate-spec.json`) and the scope of `Effort-Estimate-Agentic-MSP-Support-Agent.xlsx` (from `effort-estimate-spec.json`). Prepared 2026-11-10 with the Lab Builder `lab-cost-estimate` skill. Both workbooks are AI generated and need a human review before anyone quotes from them.

Design priced: one seat = one participant environment, a dedicated Microsoft Entra tenant with its own Azure subscription in Canada Central (`canadacentral`), used by the Senior Technician and the Tier 1 Technician. Resources come from `setup/bicep/main.bicep` and its modules (compiled to `setup/deploy-01.json`).

## 1. Results

| Scope | Base (incl. licenses) | Up to (with overage rows) |
|---|---|---|
| Per seat | 41.66 USD | 53.78 USD |
| Per workshop (25 participants + 2 spares = 27 seats) | 1,124.94 USD | 1,452.11 USD |
| Total (4 workshops = 108 seats) | 4,499.75 USD | 5,808.44 USD |

Per seat, the base is 20.33 USD of Azure and Purview consumption plus 21.33 USD of licenses (4 days). If CloudLabs holds the licenses by the month instead, licenses are 160.00 USD per seat: 180.33 USD base and 192.45 USD up to per seat, 19,475.75 USD and 20,784.44 USD for 108 seats.

The workbook prices one seat (D4 = 1). Type 27 or 108 into D4 for a live total; note that the generator's license-total label then repeats the seat count while its value stays per seat.

## 2. Durations and seats

| Item | Composition | Value |
|---|---|---|
| Prior deployment | About 2 hours of provisioning (API Management alone takes 30 to 40 minutes) + 24 hours for the sensitivity label and DLP policy to take effect + about 4 hours for the Purview pay-as-you-go check, readiness sweep, consistency report and spare checks | 30 hours |
| Lab window | 10 min sign-in and readiness + 220 min of exercises + 10 min close | 4 hours |
| Review window | Reviewers judge submitted work; then CloudLabs deletes the environment | 24 hours |
| Duration (D2) | 30 + 4 + 24 | 58 hours |
| VM uptime (D3) | About 2 hours of provisioning and checks + 4-hour window + 2 hours of buffer; reviewer VM use adds hours (overage row, up to 4) | 8 hours |
| License days | CEILING(58/24)+1 | 4 days |
| Seats | 27 per workshop (spares priced as full seats), 4 workshops | 108 |

## 3. Meters used

Azure Retail Prices API (`https://prices.azure.com/api/retail/prices`, `api-version=2023-01-01-preview`, USD, `priceType eq 'Consumption'`), queried from Python with its default user agent on 2026-11-10. Region `canadacentral` unless stated. Monthly = hourly x 730; daily x 30.4167.

| Workbook row | Product: meter | Unit price (USD) | Used as |
|---|---|---|---|
| Lab VM | Virtual Machines Dsv5 Series Windows: D2s v5 | 0.199 per hour | 145.27 per month, uptime |
| Browser RDP container | Container Instances Standard: Standard vCPU Duration; Standard Memory Duration | 0.0446 per vCPU-hour; 0.00487 per GB-hour | 0.051905 per hour (1 vCPU, 1.5 GB) = 37.89 per month, uptime |
| VM OS disk | Premium SSD Managed Disks: P10 LRS Disk | 19.712 per month | 19.71 per month |
| Public IP address | IP Addresses: Standard IPv4 Static Public IP | 0.005 per hour | 3.65 per month |
| Azure AI Search | Azure AI Search: Basic Unit | 0.101 per hour | 73.73 per month |
| Semantic ranker | Azure AI Search: Semantic Ranker queries | 1.00 per 1K | Not billed: free plan |
| API Management | API Management: Developer Unit | 0.0658 per hour | 48.03 per month |
| Container Apps | Azure Container Apps Standard: vCPU Active Usage; vCPU Idle Usage; Memory Active Usage; Memory Idle Usage; Standard Requests | 0.000034; 0.000004 per vCPU-second; 0.000004; 0.000004 per GiB-second; 0.40 per 1M | Section 4 |
| Container Apps environment | Azure Container Apps Environment: Environment Management Hour (effective 2026-11-01) | 0.10 per hour | 73.00 per month, overage row |
| Container Registry | Container Registry Basic: Basic Registry Unit; Task vCPU Duration (0 for the first 6,000, then 0.0001); Data Stored | 0.1666 per day; 0.0001 per second; 0.10 per GB-month | 5.07 per month; Section 4 |
| Key Vault | Key Vault Standard: Operations | 0.03 per 10K | Section 4 |
| Log Analytics | Log Analytics: Analytics Logs Data Ingestion (0 for the first 5 GB, then 2.76); Analytics Logs Data Retention | 2.76 per GB; 0.12 per GB-month | Section 4 |
| Storage account | General Block Blob v2 Hot LRS: Hot LRS Data Stored; Hot LRS Write Operations; Hot Read Operations; LRS List and Create Container Operations | 0.02 per GB-month; 0.055 per 10K; 0.0044 per 10K; 0.055 per 10K | Section 4 |
| gpt-5.1 | Azure OpenAI GPT5: GPT 5.1 inp Gl 1M Tokens; GPT 5.1 opt Gl 1M Tokens; GPT 5.1 cd inp Gl 1M Tokens (canadaeast row) | 1.25; 10.00; 0.125 per 1M tokens | Section 4 |
| text-embedding-3-small | Azure OpenAI: text-embedding-3-small-glbl Tokens (canadaeast row) | 0.00002 per 1K tokens | Section 4 |
| Purview pay-as-you-go | Microsoft Purview Data Security: In Transit Protection Request; Microsoft Purview Data Compliance: Audit Standard Asset | 0.00005 per request; 0.015 per 1K records | Section 4 |

Global Standard model meters have no `canadacentral` row (the open question in `research/research-foundry.md`, question 16). The estimate uses the same Global meters' `canadaeast` row (gpt-5.1 meter IDs `28319d20-7d1d-5dd4-90fe-70cecabb2d80` input, `539eb0c7-2eb4-5b25-a102-5a01587f1450` output, `24b91e3b-3070-5186-926b-025051e7872d` cached input; embedding `ab6ba671-b013-534b-a51b-55434cb3b21b`). The prices are identical in all 25 regions that list gpt-5.1 Global and all 18 that list the embedding Global meter. Purview meter IDs (`canadacentral`): `df22926a-805e-5782-9f71-07a9491a3802` (In Transit Protection Request) and `bc8f8f6f-9a7a-59c3-9876-27f2f9438ae4` (Audit Standard Asset).

Licenses (not in the Retail Prices API; published list prices per user per month, paid yearly): Microsoft 365 E5 with Teams 60.00 USD from July 1, 2026 (`research/research-purview-identity.md` section 13, `research/research-pricing.md` section 14); Power Apps Premium 20.00 USD (`research/research-dataverse.md` section 15). Two users each per seat; Microsoft Entra ID Free at 0.

## 4. Consumption rows: arithmetic per environment

Rows billed by the hour use the workbook formula: duration rows cost/730 x 58, uptime rows cost/720 x 8. For example API Management 48.03/730 x 58 = 3.82, Azure AI Search 73.73/730 x 58 = 5.86, the OS disk 19.71/730 x 58 = 1.57, the lab VM 145.27/720 x 8 = 1.61. The rows below are consumption, entered as a fixed cost per seat.

**gpt-5.1, expected use: 3.70 USD.**

- User turns: 37 agent messages in the guide (Exercise 1: 7, Exercise 2: 8, Exercise 3: 4, Exercise 4: 8, Exercise 5: 4, Exercise 6: 4, Exercise 7: 2; Exercises 3 to 6 counted from the October text that is being rewritten) x 1.6 for retries, follow-up questions and own experiments = about 60 turns, the Tier 1 Technician's turns included.
- Model calls: about 3 per turn (one before the tool calls, one or two after the tool results).
- Input per call, about 11,000 tokens: a fixed prefix of about 4,000 (agent instructions of about 3,200 characters, the definitions of the 23 tools on the agent's two MCP connections, measured at 11,341 characters from the MCP server's tool list, and the knowledge tool), about 4,000 of chat history (most tasks start a new chat), the user message (about 150) and on average about 2,500 of tool results (search results average 261 tokens per document, see below; ticket, customer and note payloads are larger).
- Input: 60 x 3 x 11,000 = 1.98M, so 2.0M tokens x 1.25 USD per 1M = 2.50 USD.
- Output: about 2,000 tokens per turn (reasoning at effort `low`, billed as output, about 300 per call; tool-call arguments; answers of 400 to 1,000 tokens, the business case longer): 60 x 2,000 = 0.12M x 10.00 USD per 1M = 1.20 USD.
- Not assumed: prompt caching. The fixed prefix repeats in every call; if half the input tokens were cached (0.125 USD per 1M), input would cost 1.0 x 1.25 + 1.0 x 0.125 = 1.38 USD instead of 2.50.
- Spares make no lab-window calls unless they are swapped in; they are priced as full seats.

**Overage, model use up to the allowance: 5.30 USD.** (4.0M less 2.0M) x 1.25 + (0.4M less 0.12M) x 10.00 = 2.50 + 2.80 = 5.30, so model use is at most 9.00 USD per environment per workshop: 243.00 USD per workshop and 972.00 USD for 108 environments. Azure does not stop a deployment at a token total; the 100K TPM deployment limits only the rate.

**text-embedding-3-small: 0.01 USD.** Token counts are measured from the seed fixtures (`agentic-msp-mcp-server/fixtures/seed/*.json`), rebuilding each document's `content` the way `Export-SearchContent.ps1` does (choice labels and lookups at typical lengths), at **4 characters per token**:

| Document type | Documents | Average characters | Average tokens | Tokens |
|---|---|---|---|---|
| Knowledge article | 120 | 974 | 244 | 29,232 |
| Customer document | 36 | 3,106 | 776 | 27,951 |
| Runbook | 12 | 520 | 130 | 1,559 |
| Ticket (500 historical + 60 open) | 560 | 868 | 217 | 121,461 |
| Customer profile | 24 | 2,039 | 510 | 12,233 |
| SLA snapshot | 1 | 16,745 | 4,186 | 4,186 |
| Total | 753 | 1,044 | 261 | 196,623 |

One embedding at provisioning and one when the participant builds the index: 2 x 196,623 = 393,246 tokens, plus about 6,000 query-vector tokens (about 200 searches x 30), about 0.4M tokens x 0.02 USD per 1M = 0.008 USD. A rerun of `New-KnowledgeIndex.ps1` adds 0.004 USD.

**Microsoft Purview pay-as-you-go: 0.05 USD.** The MCP server sends text to `processContent` only for `get_ticket`, `get_ticket_notes` and `get_customer_document` calls made by a signed-in user, one request per call plus one per note when a note is blocked (Exercise 6); calls through the diagnostics API carry no user and are redacted by the server instead. Allowance: 600 requests x 0.00005 = 0.03 USD, plus about 1,200 audit records x 0.015 per 1K = 0.02 USD. Protection scope lookups are cached per user for 60 minutes and are not counted.

**Log Analytics and Application Insights: 0.83 USD.** About 0.3 GB per environment (API Management gateway and MCP logs, MCP server console and system logs, Key Vault audit events, agent traces with captured content) x 2.76 USD per GB = 0.83. The 5 GB free tier is assumed used by the shared billing account; retention stays inside the included 31 days.

**Container Apps: 1.57 USD.** Idle: (0.5 x 0.000004 + 1 x 0.000004) x 3,600 x 730 = 15.77 USD per month, x 58/730 = 1.25. Active hours: 6 (provisioning and the lab window) x (0.0756 less 0.0216) = 0.32. All 58 hours at active rates would be 0.0756 x 58 = 4.39. The monthly free grant per subscription (180,000 vCPU-seconds, 360,000 GiB-seconds) covers 58 hours (104,400 vCPU-seconds, 208,800 GiB-seconds), so the row is 0 when the subscription has no other Container Apps use that month; not assumed. If the Environment Management Hour bills for a Consumption-only environment: 58 x 0.10 = 5.80 USD (overage row).

**Container Registry: 0.58 USD.** Registry 5.07/730 x 58 = 0.40, plus ACR Tasks: 5 builds (3.0.0 at provisioning; 3.0.1, 3.0.2 and 3.0.3; one retry) x 180 seconds x 2 vCPU = 1,800 vCPU-seconds x 0.0001 = 0.18. The images stay well inside the 10 GiB included.

**Key Vault: 0.01 USD.** Under 1,000 operations (secret reads at each MCP revision start, API Management named-value refreshes, readiness checks, metadata views) x 0.03 per 10K = 0.003.

**Storage account: 0.01 USD.** About 770 writes x 0.055 per 10K = 0.0042, about 1,520 reads (two indexer passes) x 0.0044 per 10K = 0.0007, about 0.002 GB stored: negligible.

**Semantic ranker: 0.** The search service uses the free plan (1,000 requests per month, then an error instead of a charge); about 150 knowledge-tool queries per environment.

**Overage, reviewer use of the lab VM: 1.02 USD.** (145.27 + 37.89)/720 x 4 hours = 1.02 for the VM and the browser RDP container, if reviewers open the VM during the review window.

## 5. Five biggest cost drivers (per seat, base)

| Rank | Row | Per seat (USD) |
|---|---|---|
| 1 | Microsoft 365 E5, 2 users x 60.00/30 x 4 days | 16.00 (120.00 if held by the month) |
| 2 | Azure AI Search Basic, 58 hours | 5.86 |
| 3 | Power Apps Premium, 2 users x 20.00/30 x 4 days | 5.33 (40.00 if held by the month) |
| 4 | API Management Developer, 58 hours | 3.82 |
| 5 | gpt-5.1, expected use | 3.70 (up to 9.00) |

Next: the lab VM (1.61), Container Apps (1.57) and the OS disk (1.57).

## 6. Assumptions to confirm in the pilot

1. License basis and price: per day for 4 days (21.33 USD per seat) or by the month (160.00 USD per seat), the offer IDs for Microsoft 365 E5 and Power Apps Premium, and the price CloudLabs actually pays (list prices are paid yearly).
2. Model use per participant: about 60 turns, 3 model calls per turn, about 11,000 input tokens per call and 2,000 output tokens per turn at reasoning effort `low`. Read the real totals from the deployment's metrics after the pilot.
3. Whether Foundry sends the MCP output schemas to the model. The two connections' output schemas add about 126,700 characters (about 31,700 tokens per model call); if they are sent, input would exceed the 4M allowance.
4. Whether the Foundry playground runs evaluators by default (`research/research-foundry.md`, question 26), which would add tokens.
5. The prompt cache hit rate (cached input bills 0.125 USD per 1M), a possible saving that is not counted.
6. Container Apps: idle billing outside the lab window, whether the Environment Management Hour bills for a Consumption-only environment, and whether the per-subscription free grant applies to CloudLabs subscriptions.
7. ACR Tasks: about 180 seconds per build of the Python image, 2 vCPU per quick build, and whether the 6,000-second zero tier applies.
8. Log Analytics: about 0.3 GB per environment, and whether the 5 GB free tier is counted per subscription or per billing account in the CloudLabs setup.
9. Purview: about 600 `processContent` requests and 1,200 audit records per environment, and which meter `processContent` calls of an Entra-registered app bill under (no page ties them to a named meter, `research/research-purview-identity.md` section 8).
10. Semantic ranker queries stay under the free plan's 1,000 per month per search service.
11. Durations: about 2 hours of provisioning, the 24-hour wait for labels, the 24-hour review window, deletion right after it, and up to 4 hours of reviewer VM use.
12. Spares: priced as full seats; an unused spare costs less (no lab-window tokens).
13. The managed developer environment's capacity is covered by the licenses, and it is removed with the tenant at teardown (it is not in the resource group).
14. The Spektra jump VM image carries no marketplace software charge.
15. Every participant subscription is paid (ACR Tasks runs are paused on free credits) and at quota Tier 1 or above for gpt-5.1.

## 7. Prices not taken live for Canada Central

- gpt-5.1 and text-embedding-3-small Global Standard: no `canadacentral` row in the Retail Prices API; the `canadaeast` row of the same Global meter is used, at the price every listed region shows.
- Microsoft 365 E5 and Power Apps Premium: not in the API; published list prices from the research notes.
- Spektra jump VM image software charge: not in the API; assumed 0.

Every other price was retrieved live for `canadacentral` on 2026-11-10.

## 8. Effort estimate scope

The effort workbook covers the v3 rebuild in 12 phases: the redesign for a dedicated tenant per participant, the Bicep template, per-tenant provisioning with the setup app, the MCP server v3.0.0, the data rebuild, the 7 rewritten exercises (104 steps), 9 animated diagrams, 14 validation scripts and the acceptance test suite, these estimates, the pilot with screenshots and 27 task GIFs, platform onboarding, and the 4 workshop deliveries with support. Total 402 to 610 hours, 457 expected (60.9 working days at 7.5 hours): 69.4 expected hours done, 228.0 in progress, 159.6 not started. Like the October estimate, it gives hours only, with no roles or rates.
