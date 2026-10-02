# CloudLabs lab cost research: Azure and licence list prices

- Retrieval date: 2026-10-01 (API calls between 13:03 and 13:28 UTC; per-file timestamps are inside each raw JSON file).
- Prepared for: CloudLabs hands-on lab cost estimate (Spektra Systems).
- Regions priced: East US 2 (`eastus2`) and East US (`eastus`).
- Currency: USD retail list price (pay-as-you-go). Excludes tax, EA/MCA/CSP discounts, savings plans, reservations and Azure Hybrid Benefit.

## Method and conventions

1. Primary source: Azure Retail Prices API (public, no auth):
   `https://prices.azure.com/api/retail/prices?api-version=2023-01-01-preview&currencyCode='USD'&$filter=<filter>`.
   `NextPageLink` was followed until empty. Filters include `priceType eq 'Consumption'` unless noted (every row returned has `type = Consumption`). Helper script: `azprice.ps1` (this folder).
2. Cross-check: the JSON feeds that drive the official azure.microsoft.com pricing pages and the pricing calculator,
   `https://azure.microsoft.com/api/{v2|v3}/pricing/<service>/calculator/?culture=en-us&discount=mosp`, saved as `pricing-raw-calc-<service>.json` (helper `calc.ps1`). The pricing pages render prices client side (a plain fetch shows `$-` placeholders), so qualitative facts (free grants, footnotes, what is billed) were read from the page text and from Microsoft Learn.
3. Derived monthly cost = hourly price x 730. Daily meters x 30.4167 (730 / 24). Monthly meters are shown as listed.
4. Raw files: each `pricing-raw-<item>.json` holds the exact filter, retrieval timestamp, page count and the merged `Items` array of all pages returned. `pricing-raw-calc-virtual-machines.json` is a trimmed extract (the full feed is 62 MB); the source URL is inside it.
5. Result of the cross-check: every API price used below matches the calculator feed for us-east-2 and us-east, except text-embedding-3-small Global (the calculator only carries the regional/Data Zone rate; see item 11).
6. East US 2 and East US list prices are identical for every item except Log Analytics (East US 2 is 20 percent higher) and blob storage (East US 2 is cheaper).

---

## 1. Virtual Machines: Standard_D2s_v3 and Standard_D4s_v3, Windows, pay-as-you-go

Filter: `serviceName eq 'Virtual Machines' and (armRegionName eq 'eastus2' or armRegionName eq 'eastus') and (armSkuName eq 'Standard_D2s_v3' or armSkuName eq 'Standard_D4s_v3') and priceType eq 'Consumption'` (28 rows; Spot and Low Priority rows excluded below). Raw: `pricing-raw-vm.json`.

| Region | serviceName | productName | skuName | meterName | unitOfMeasure | retailPrice (USD) | Monthly (x730) |
|---|---|---|---|---|---|---|---|
| eastus2 | Virtual Machines | Virtual Machines DSv3 Series Windows | D2s v3 | D2s v3 | 1 Hour | 0.188 | 137.24 |
| eastus2 | Virtual Machines | Virtual Machines DSv3 Series Windows | D4s v3 | D4s v3 | 1 Hour | 0.376 | 274.48 |
| eastus | Virtual Machines | Virtual Machines DSv3 Series Windows | D2s v3 | D2s v3 | 1 Hour | 0.188 | 137.24 |
| eastus | Virtual Machines | Virtual Machines DSv3 Series Windows | D4s v3 | D4s v3 | 1 Hour | 0.376 | 274.48 |

Notes:
- The Windows product price includes the Windows Server licence. Linux reference (product `Virtual Machines DSv3 Series`): D2s v3 $0.096/hr ($70.08/month), D4s v3 $0.192/hr ($140.16/month), same in both regions.
- Cross-check: calculator `windows-d2sv3-standard` 0.188/hr and `windows-d4sv3-standard` 0.376/hr in us-east-2 and us-east.
- Compute is billed only while the VM is allocated (running); a stopped (deallocated) VM stops compute charges, but its disks and static public IP keep billing.

## 2. Managed disks: Standard SSD E10 LRS and Standard HDD S10 LRS

Filter: `serviceName eq 'Storage' and (armRegionName eq 'eastus2' or armRegionName eq 'eastus') and (skuName eq 'E10 LRS' or skuName eq 'S10 LRS') and priceType eq 'Consumption'`. Raw: `pricing-raw-disks.json`.

| Region | serviceName | productName | skuName | meterName | unitOfMeasure | retailPrice (USD) | Monthly |
|---|---|---|---|---|---|---|---|
| eastus2 | Storage | Standard SSD Managed Disks | E10 LRS | E10 LRS Disk | 1/Month | 9.60 | 9.60 per disk |
| eastus2 | Storage | Standard SSD Managed Disks | E10 LRS | E10 LRS Disk Operations | 10K | 0.002 | usage |
| eastus2 | Storage | Standard SSD Managed Disks | E10 LRS | E10 LRS Disk Mount | 1/Month | 0.91 | shared disks only |
| eastus2 | Storage | Standard HDD Managed Disks | S10 LRS | S10 LRS Disk | 1/Month | 5.888 | 5.89 per disk |
| eastus2 | Storage | Standard HDD Managed Disks | S10 LRS | S10 LRS Disk Operations | 10K | 0.0005 | usage |
| eastus | Storage | Standard SSD Managed Disks | E10 LRS | E10 LRS Disk | 1/Month | 9.60 | 9.60 per disk |
| eastus | Storage | Standard SSD Managed Disks | E10 LRS | E10 LRS Disk Operations | 10K | 0.002 | usage |
| eastus | Storage | Standard SSD Managed Disks | E10 LRS | E10 LRS Disk Mount | 1/Month | 0.91 | shared disks only |
| eastus | Storage | Standard HDD Managed Disks | S10 LRS | S10 LRS Disk | 1/Month | 5.888 | 5.89 per disk |
| eastus | Storage | Standard HDD Managed Disks | S10 LRS | S10 LRS Disk Operations | 10K | 0.0005 | usage |

Notes:
- E10 and S10 are both 128 GiB; the default 127 GiB Windows OS disk maps to E10/S10. Billing is prorated hourly from the monthly price (E10 about $0.01315/hour, S10 about $0.00807/hour) and continues while the VM is deallocated.
- Transactions: Standard SSD counts each I/O up to 256 KiB as one operation, Standard HDD up to 16 KiB; both have an hourly cap on billable transactions (Microsoft Learn, "Understand Azure Disk Storage billing", learn.microsoft.com/azure/virtual-machines/disks-understand-billing).
- Disk Mount is charged only when a Standard SSD is shared across VMs (same Learn page).
- Cross-check: calculator `standardssd-e10-lrs` 9.6, `standardhdd-s10` 5.888, `transactions-ssd` 0.002, `transactions-hdd` 0.0005.

## 3. Public IP: Standard static IPv4

Filter: `productName eq 'IP Addresses' and (armRegionName eq 'eastus2' or armRegionName eq 'eastus') and priceType eq 'Consumption'`. Raw: `pricing-raw-publicip.json`.

| Region | serviceName | productName | skuName | meterName | unitOfMeasure | retailPrice (USD) | Monthly (x730) |
|---|---|---|---|---|---|---|---|
| eastus2 | Virtual Network | IP Addresses | Standard | Standard IPv4 Static Public IP | 1 Hour | 0.005 | 3.65 |
| eastus | Virtual Network | IP Addresses | Standard | Standard IPv4 Static Public IP | 1 Hour | 0.005 | 3.65 |

Notes:
- Basic SKU public IPs were retired on 30 September 2025 (Learn, learn.microsoft.com/azure/virtual-network/ip-services/public-ip-upgrade). The API still lists Basic meters ($0.0036 static, $0.004 dynamic per hour); do not use them for new labs.
- Cross-check: calculator `standard-static-arm` 0.005/hr in both regions.

## 4. Azure Container Instances (Linux): 1 vCPU, 1.5 GB browser RDP container

Filter: `serviceName eq 'Container Instances' and (armRegionName eq 'eastus2' or armRegionName eq 'eastus') and priceType eq 'Consumption'`. Raw: `pricing-raw-aci.json`.

| Region | serviceName | productName | skuName | meterName | unitOfMeasure | retailPrice (USD) | Monthly (x730) |
|---|---|---|---|---|---|---|---|
| eastus2 | Container Instances | Container Instances | Standard | Standard vCPU Duration | 1 Hour | 0.0405 | 29.57 per vCPU |
| eastus2 | Container Instances | Container Instances | Standard | Standard Memory Duration | 1 GB Hour | 0.00445 | 3.25 per GB |
| eastus | Container Instances | Container Instances | Standard | Standard vCPU Duration | 1 Hour | 0.0405 | 29.57 per vCPU |
| eastus | Container Instances | Container Instances | Standard | Standard Memory Duration | 1 GB Hour | 0.00445 | 3.25 per GB |

Derived for 1 vCPU + 1.5 GB (Linux): 0.0405 + 1.5 x 0.00445 = **$0.047175 per hour = $34.44 per 730-hour month** (both regions).

Notes:
- Per second: $0.00001125 per vCPU-second and $0.0000012361 per GB-second. Cross-check: calculator `core-duration` 1.125E-05 per core-second, `memory-duration` 1.2361E-06 per GB-second.
- Duration is measured from the start of the first image pull until the container group stops (Learn, ACI FAQ "When does the meter start running?").
- Windows containers add `Standard Windows Software Duration` at $0.000012 per second (not needed for Linux). Spot ACI is cheaper ($0.01215 per vCPU-hour, $0.001335 per GB-hour) but can be evicted and does not support a public IP, so it does not suit interactive RDP.

## 5. Azure AI Search: Basic and Standard S1, semantic ranker

Filter: `serviceName eq 'Azure Cognitive Search' and (armRegionName eq 'eastus2' or armRegionName eq 'eastus') and priceType eq 'Consumption'` (the serviceName `Azure AI Search` returns 0 rows; the productName is `Azure AI Search`). Raw: `pricing-raw-aisearch.json`, plus `pricing-raw-aisearch-global.json`.

| Region | serviceName | productName | skuName | meterName | unitOfMeasure | retailPrice (USD) | Monthly (x730) |
|---|---|---|---|---|---|---|---|
| eastus2 | Azure Cognitive Search | Azure AI Search | Basic | Basic Unit | 1 Hour | 0.101 | 73.73 per SU |
| eastus2 | Azure Cognitive Search | Azure AI Search | Standard S1 | Standard S1 Unit | 1 Hour | 0.336 | 245.28 per SU |
| eastus2 | Azure Cognitive Search | Azure AI Search | Semantic Ranker | Semantic Ranker queries | 1K | 1.00 | usage |
| eastus2 | Azure Cognitive Search | Azure AI Search | Agentic Retrieval Minimum Reasoning | Agentic Retrieval Minimum Reasoning Tokens | 1K | 0.000022 | usage ($0.022 per 1M tokens) |
| eastus2 | Azure Cognitive Search | Azure AI Search | Agentic Retrieval Low Reasoning | Agentic Retrieval Low Reasoning Tokens | 1K | 0.000022 | usage ($0.022 per 1M tokens) |
| eastus2 | Azure Cognitive Search | Azure AI Search | Agentic Retrieval Medium Reasoning | Agentic Retrieval Medium Reasoning Tokens | 1K | 0.0001 | usage ($0.10 per 1M tokens) |
| eastus | Azure Cognitive Search | Azure AI Search | Basic | Basic Unit | 1 Hour | 0.101 | 73.73 per SU |
| eastus | Azure Cognitive Search | Azure AI Search | Standard S1 | Standard S1 Unit | 1 Hour | 0.336 | 245.28 per SU |
| eastus | Azure Cognitive Search | Azure AI Search | Semantic Ranker | Semantic Ranker queries | 1K | 1.00 | usage |
| eastus | Azure Cognitive Search | Azure AI Search | Agentic Retrieval Minimum Reasoning | Agentic Retrieval Minimum Reasoning Tokens | 1K | 0.000022 | usage |
| eastus | Azure Cognitive Search | Azure AI Search | Agentic Retrieval Low Reasoning | Agentic Retrieval Low Reasoning Tokens | 1K | 0.000022 | usage |
| eastus | Azure Cognitive Search | Azure AI Search | Agentic Retrieval Medium Reasoning | Agentic Retrieval Medium Reasoning Tokens | 1K | 0.0001 | usage |

Notes:
- Billed per search unit (SU = replicas x partitions; minimum 1) for every hour the service exists; there is no pause.
- Semantic ranker: the pricing page states the first 1,000 requests per month are free, then the $1 per 1,000 meter applies. Agentic retrieval: the page states the first 50M tokens per month are free.
- The API also lists `Semantic Ranker Unit` ($16.12 per day) and `Semantic Ranker Overage Queries` ($2 per 1K). These older unit-based meters are not in the calculator feed, which carries only the $1 per 1K rate; use $1 per 1K.
- Optional confidential compute SKUs: `Basic CC Unit` $0.1111/hr ($81.10/month) and `Standard S1 CC Unit` $0.3696/hr ($269.81/month). A `Free Unit` ($0) is also listed.
- Serverless tier (preview) meters exist only in East US (`Serverless Compute Unit` $0.24/hr, `Serverless Storage Data Stored` $0.20 per GB-month, effective 2026-09-01). None were found for East US 2 with the same filter.
- Cross-check: calculator `basic` 0.101, `standard-s1` 0.336, `semantic-ranker` 1, agentic min 2.2E-05 and medium 0.0001 in both regions.

## 6. API Management: Developer, Basic v2, Standard v2

Filter: `serviceName eq 'API Management' and (armRegionName eq 'eastus2' or armRegionName eq 'eastus') and priceType eq 'Consumption'`. Raw: `pricing-raw-apim.json`. Prices are identical in both regions; East US 2 rows shown, East US is the same.

| Region | serviceName | productName | skuName | meterName | unitOfMeasure | retailPrice (USD) | Monthly (x730) |
|---|---|---|---|---|---|---|---|
| eastus2 and eastus | API Management | API Management | Developer | Developer Unit | 1 Hour | 0.0658 | 48.03 |
| eastus2 and eastus | API Management | API Management | Basic v2 | Basic v2 Unit | 1 Hour | 0.20548 | 150.00 |
| eastus2 and eastus | API Management | API Management | Basic v2 | Basic v2 Calls (tier from 0) | 10K | 0 | included |
| eastus2 and eastus | API Management | API Management | Basic v2 | Basic v2 Calls (tier from 1,000 x 10K = 10M calls) | 10K | 0.03 | $3.00 per extra 1M |
| eastus2 and eastus | API Management | API Management | Standard v2 | Standard v2 Unit | 1 Hour | 0.9589 | 700.00 |
| eastus2 and eastus | API Management | API Management | Standard v2 | Standard v2 Calls (tier from 0) | 10K | 0 | included |
| eastus2 and eastus | API Management | API Management | Standard v2 | Standard v2 Calls (tier from 5,000 x 10K = 50M calls) | 10K | 0.025 | $2.50 per extra 1M |

Notes:
- Per-call meters for v2: Basic v2 includes 10M requests per month and Standard v2 includes 50M (pricing page text); beyond that $0.03 and $0.025 per 10K requests respectively (API tiers above).
- Developer is a classic tier with no SLA (pricing page); fine for labs, not for production.
- East US 2 only: a new `AI Gateway` product meter `10k AI Gateway Requests` at $0 (effective 2026-09-01). The pricing page says AI Gateway pricing is coming soon and is free up to 100,000 requests when created as an AI Gateway in Foundry.
- Cross-check: calculator `developer` 0.0658, `basic-v2-unit` 0.20548, `standard-v2-unit` 0.9589, `basic-v2-calls` 0.03, `standard-v2-calls` 0.025.

## 7. Azure Container Apps: consumption plan

Filter: `serviceName eq 'Azure Container Apps' and (armRegionName eq 'eastus2' or armRegionName eq 'eastus') and priceType eq 'Consumption'`. Raw: `pricing-raw-aca.json`. Identical in both regions.

| Region | serviceName | productName | skuName | meterName | unitOfMeasure | retailPrice (USD) | Per hour equivalent |
|---|---|---|---|---|---|---|---|
| eastus2 and eastus | Azure Container Apps | Azure Container Apps | Standard | Standard vCPU Active Usage | 1 Second | 0.000024 | 0.0864 per vCPU-hour |
| eastus2 and eastus | Azure Container Apps | Azure Container Apps | Standard | Standard vCPU Idle Usage | 1 Second | 0.000003 | 0.0108 per vCPU-hour |
| eastus2 and eastus | Azure Container Apps | Azure Container Apps | Standard | Standard Memory Active Usage | 1 GiB Second | 0.000003 | 0.0108 per GiB-hour |
| eastus2 and eastus | Azure Container Apps | Azure Container Apps | Standard | Standard Memory Idle Usage | 1 GiB Second | 0.000003 | 0.0108 per GiB-hour |
| eastus2 and eastus | Azure Container Apps | Azure Container Apps | Standard | Standard Requests | 1M | 0.40 | per 1M requests |
| eastus2 and eastus | Azure Container Apps | Azure Container Apps | Environment | Environment Management Hour | 1 Hour | 0.10 | 73.00 per month if triggered |
| eastus2 and eastus | Azure Container Apps | Azure Container Apps | Environment | Environment Planned Maintenance Hour | 1 Hour | 0.10 | 73.00 per month if triggered |
| eastus2 and eastus | Azure Container Apps | Azure Container Apps | Environment | Environment Private Endpoint | 1 Hour | 0.10 | 73.00 per month if triggered |
| eastus2 and eastus | Azure Container Apps | Azure Container Apps | Dedicated | Dedicated Plan Management | 1 Hour | 0.10 | 73.00 per month if triggered |

Free grants (pricing page, Learn "Billing in Azure Container Apps", and calculator `standard-included-*` maxQuantity): first **180,000 vCPU-seconds, 360,000 GiB-seconds and 2 million HTTP requests per subscription per calendar month** are free.

Worked examples (730-hour month, 1 replica always active):
- 0.5 vCPU / 1 GiB: $34.02 after free grants ($39.42 without grants).
- 1 vCPU / 2 GiB: $73.44 after free grants.
- Scaled to zero: $0 compute; only requests above the free 2M are billed.

Notes:
- Idle rates apply only when a revision runs at its minimum replica count (greater than zero) and the replica is idle (Learn billing page).
- The $0.10/hour management meters apply only if the environment uses a Dedicated workload profile, private endpoints or planned maintenance (Learn billing page; pricing page footnote on the Management meter). A consumption-only environment without those features has no management charge. The three `Environment` meters are new (effective 2026-09-01).
- The free grant is per subscription, so it only helps if each lab gets its own subscription.
- Cross-check: calculator `standard-active-vcpu` 2.4E-05, `standard-idle-vcpu` 3E-06, `standard-active-memory` and `standard-idle-memory` 3E-06, `standard-requests` 0.4, `dedicated-plan-management` 0.1.

## 8. Azure Container Registry: Basic, Standard, ACR Tasks

Filter: `serviceName eq 'Container Registry' and (armRegionName eq 'eastus2' or armRegionName eq 'eastus') and priceType eq 'Consumption'`. Raw: `pricing-raw-acr.json`. Identical in both regions.

| Region | serviceName | productName | skuName | meterName | unitOfMeasure | retailPrice (USD) | Monthly (x30.4167 days) |
|---|---|---|---|---|---|---|---|
| eastus2 and eastus | Container Registry | Container Registry | Basic | Basic Registry Unit | 1/Day | 0.1666 | 5.07 |
| eastus2 and eastus | Container Registry | Container Registry | Standard | Standard Registry Unit | 1/Day | 0.6666 | 20.28 |
| eastus2 and eastus | Container Registry | Container Registry | Basic / Standard | Data Stored | 1 GB/Month | 0.10 | above included storage |
| eastus2 and eastus | Container Registry | Container Registry | Basic / Standard | Task vCPU Duration (tier from 0) | 1 Second | 0 | first 6,000 s |
| eastus2 and eastus | Container Registry | Container Registry | Basic / Standard | Task vCPU Duration (tier from 6,000 s) | 1 Second | 0.0001 | usage |

Notes:
- On a 30-day month Basic is $5.00 and Standard is $20.00.
- Included storage: Basic 10 GB, Standard 100 GB, Premium 500 GB (pricing page); extra storage $0.10 per GB-month.
- ACR Tasks: $0.0001 per second of task run (Learn, ACR continuous patching page, which quotes the default ACR Task price). The API tiering shows the first 6,000 seconds at $0; the pricing page text does not state a free allowance, so treat it as unconfirmed. Example: a 3-minute build = 180 s = $0.018.
- Microsoft Learn (ACR Tasks overview, as quoted on Microsoft Q&A) notes that ACR task runs are paused for subscriptions funded by Azure free credits; check this if lab subscriptions are credit funded.
- Cross-check: calculator `basic` 0.1666/day, `standard` 0.6666/day, `storage` 0.1 (the feed has no Tasks entry).

## 9. Key Vault: Standard operations

Filter: `serviceName eq 'Key Vault' and (armRegionName eq 'eastus2' or armRegionName eq 'eastus') and priceType eq 'Consumption'`. Raw: `pricing-raw-keyvault.json`. Identical in both regions.

| Region | serviceName | productName | skuName | meterName | unitOfMeasure | retailPrice (USD) | Monthly |
|---|---|---|---|---|---|---|---|
| eastus2 and eastus | Key Vault | Key Vault | Standard | Operations | 10K | 0.03 | usage |
| eastus2 and eastus | Key Vault | Key Vault | Standard | Advanced Key Operations | 10K | 0.15 | usage (RSA 3072/4096, ECC) |
| eastus2 and eastus | Key Vault | Key Vault | Standard | Certificate Renewal Request | 1 | 3.00 | per renewal |
| eastus2 and eastus | Key Vault | Key Vault | Standard | Automated Key Rotation | 1 Rotation | 1.00 | per rotation |

Notes: no per-vault fee on Standard; 10,000 secret reads cost $0.03, so a lab vault is pennies. Cross-check: calculator `secretssoftwareprotectedkeys-standard` 0.03.

## 10. Log Analytics and Application Insights

Filters: `serviceName eq 'Log Analytics' and (armRegionName eq 'eastus2' or armRegionName eq 'eastus') and priceType eq 'Consumption'` (raw `pricing-raw-loganalytics.json`); `serviceName eq 'Azure Monitor' ...` (raw `pricing-raw-azuremonitor.json`); `serviceName eq 'Application Insights' ...` (raw `pricing-raw-appinsights.json`).

| Region | serviceName | productName | skuName | meterName | unitOfMeasure | retailPrice (USD) | Monthly |
|---|---|---|---|---|---|---|---|
| eastus2 | Log Analytics | Log Analytics | Analytics Logs | Analytics Logs Data Ingestion (tier from 0 GB) | 1 GB | 0 | first 5 GB |
| eastus2 | Log Analytics | Log Analytics | Analytics Logs | Analytics Logs Data Ingestion (tier from 5 GB) | 1 GB | **2.76** | per GB |
| eastus2 | Log Analytics | Log Analytics | Analytics Logs | Analytics Logs Data Retention | 1 GB/Month | 0.12 | beyond included retention |
| eastus | Log Analytics | Log Analytics | Analytics Logs | Analytics Logs Data Ingestion (tier from 0 GB) | 1 GB | 0 | first 5 GB |
| eastus | Log Analytics | Log Analytics | Analytics Logs | Analytics Logs Data Ingestion (tier from 5 GB) | 1 GB | **2.30** | per GB |
| eastus | Log Analytics | Log Analytics | Analytics Logs | Analytics Logs Data Retention | 1 GB/Month | 0.10 | beyond included retention |
| eastus2 and eastus | Azure Monitor | Azure Monitor | Basic Logs | Basic Logs Data Ingestion | 1 GB | 0.50 | per GB |
| eastus2 and eastus | Azure Monitor | Azure Monitor | Auxiliary Logs | Auxiliary Logs Data Ingestion | 1 GB | 0.05 | per GB |

Notes:
- Free allowance: the first 5 GB per month per billing account of Analytics Logs pay-as-you-go ingestion is free (Azure Monitor pricing page; Learn, Application Insights FAQ). It is shared across every workspace in the billing account, so in a shared CloudLabs billing account assume it is already consumed.
- Included retention: 31 days for Analytics Logs, 90 days for Application Insights tables and Sentinel workspaces (Learn, Azure Monitor cost best practices).
- Application Insights (confirmed): workspace-based Application Insights ingestion and retention are billed through the Log Analytics workspace at Log Analytics prices, including commitment tiers (Learn, "Azure Monitor Logs cost calculations and options", section Application Insights billing). Classic Application Insights is retired. The `Application Insights` serviceName meters (Enterprise Node, Enterprise Overage Data $2.30/GB, Multi-step Web Test) are legacy.
- East US 2 is 20 percent above East US for ingestion ($2.76 vs $2.30) and retention ($0.12 vs $0.10).
- Cross-check: calculator graduatedOffers `log-analytics-data-ingestion` us-east-2 = $0 up to 5 GB then $2.76; us-east = $0 up to 5 GB then $2.30; `log-analytics-data-retention` us-east-2 0.12, us-east 0.10; `basic-log-data-ingestion` 0.5; `auxiliary-log-data-ingestion` 0.05.

## 11. Azure OpenAI in Foundry Models: Global Standard token prices

Filter: `serviceName eq 'Foundry Models' and (armRegionName eq 'eastus2' or armRegionName eq 'eastus') and startswith(productName, 'Azure OpenAI')` (2,559 rows). Raw: `pricing-raw-foundry-models-aoai-all.json` (full) and `pricing-raw-aoai-selected.json` (78-row subset used here). serviceName `Cognitive Services`, `Azure OpenAI`, `Azure OpenAI Service` all return 0 rows; the service is `Foundry Models`. All models requested were found in the API; prices are identical in eastus2 and eastus.

Global Standard meters (eastus2 shown; eastus identical):

| Model | serviceName | productName | skuName | meterName | unitOfMeasure | retailPrice (USD) | Per 1M tokens |
|---|---|---|---|---|---|---|---|
| gpt-5-mini input | Foundry Models | Azure OpenAI GPT5 | GPT 5 Mini Inpt Glbl | GPT 5 Mini Inpt Glbl 1M Tokens | 1M | 0.25 | 0.25 |
| gpt-5-mini cached input | Foundry Models | Azure OpenAI GPT5 | GPT 5 Mini cchd Inpt Glbl | GPT 5 Mini cchd Inpt Glbl 1M Tokens | 1M | 0.025 | 0.025 |
| gpt-5-mini output | Foundry Models | Azure OpenAI GPT5 | GPT 5 Mini outpt Glbl | GPT 5 Mini outpt Glbl 1M Tokens | 1M | 2.00 | 2.00 |
| gpt-5.1 input | Foundry Models | Azure OpenAI GPT5 | GPT 5.1 inp Gl | GPT 5.1 inp Gl 1M Tokens | 1M | 1.25 | 1.25 |
| gpt-5.1 cached input | Foundry Models | Azure OpenAI GPT5 | GPT 5.1 cd inp Gl | GPT 5.1 cd inp Gl 1M Tokens | 1M | 0.125 | 0.125 |
| gpt-5.1 output | Foundry Models | Azure OpenAI GPT5 | GPT 5.1 opt Gl | GPT 5.1 opt Gl 1M Tokens | 1M | 10.00 | 10.00 |
| gpt-5 input | Foundry Models | Azure OpenAI GPT5 | GPT 5 Inpt Glbl | GPT 5 Inpt Glbl 1M Tokens | 1M | 1.25 | 1.25 |
| gpt-5 cached input | Foundry Models | Azure OpenAI GPT5 | GPT 5 cchd Inpt Glbl | GPT 5 cchd Inpt Glbl 1M Tokens | 1M | 0.125 | 0.125 |
| gpt-5 output | Foundry Models | Azure OpenAI GPT5 | GPT 5 outpt Glbl | GPT 5 outpt Glbl 1M Tokens | 1M | 10.00 | 10.00 |
| gpt-4.1 input | Foundry Models | Azure OpenAI | gpt 4.1 Inp glbl | gpt 4.1 Inp glbl Tokens | 1K | 0.002 | 2.00 |
| gpt-4.1 cached input | Foundry Models | Azure OpenAI | gpt 4.1 cached Inp glbl | gpt 4.1 cached Inp glbl Tokens | 1K | 0.0005 | 0.50 |
| gpt-4.1 output | Foundry Models | Azure OpenAI | gpt 4.1 Outp glbl | gpt 4.1 Outp glbl Tokens | 1K | 0.008 | 8.00 |
| gpt-4.1-mini input | Foundry Models | Azure OpenAI | gpt 4.1 mini Inp glbl | gpt 4.1 mini Inp glbl Tokens | 1K | 0.0004 | 0.40 |
| gpt-4.1-mini cached input | Foundry Models | Azure OpenAI | gpt 4.1 mini cached Inp glbl | gpt 4.1 mini cached Inp glbl Tokens | 1K | 0.0001 | 0.10 |
| gpt-4.1-mini output | Foundry Models | Azure OpenAI | gpt 4.1 mini Outp glbl | gpt 4.1 mini Outp glbl Tokens | 1K | 0.0016 | 1.60 |
| text-embedding-3-small | Foundry Models | Azure OpenAI | text-embedding-3-small-glbl | text-embedding-3-small-glbl Tokens | 1K | 0.00002 | 0.02 |

Per 1M tokens by deployment type (input / cached input / output; same in both regions):

| Model | Global Standard | Data Zone Standard | Regional Standard |
|---|---|---|---|
| gpt-5-mini | 0.25 / 0.025 / 2.00 | 0.275 / 0.0275 / 2.20 | not listed |
| gpt-5.1 | 1.25 / 0.125 / 10.00 | 1.375 / 0.1375 / 11.00 | not listed |
| gpt-5 | 1.25 / 0.125 / 10.00 | 1.375 / 0.1375 / 11.00 | not listed |
| gpt-4.1 | 2.00 / 0.50 / 8.00 | 2.20 / 0.55 / 8.80 | 2.20 / 0.55 / 8.80 |
| gpt-4.1-mini | 0.40 / 0.10 / 1.60 | 0.44 / 0.11 / 1.76 | 0.44 / 0.11 / 1.76 |
| text-embedding-3-small | 0.020 | 0.022 | 0.022 |

Notes:
- Global meters are published under each resource region (armRegionName eastus2 / eastus); the Foundry resource region decides which regional meter is billed.
- Cross-check against the official Azure OpenAI pricing page feed (`pricing-raw-calc-openai-service.json`): `language-models-gpt-5-mini-global-*` 0.25 / 0.025 / 2; `language-models-gpt-5-1-global-*` 1.25 / 0.125 / 10; `language-models-gpt-5-2025-08-07-global-*` 1.25 / 0.125 / 10; `language-models-gpt-4-1-2025-04-14-global-*` 0.002 / 0.0005 / 0.008 per 1K; `language-models-gpt-4-1-mini-2025-04-14-global-*` 0.0004 / 0.0001 / 0.0016 per 1K. All match.
- text-embedding-3-small: the calculator feed lists only $0.000022 per 1K ($0.022 per 1M, regional and Data Zone). The $0.00002 per 1K Global meter exists in the API only. Budgeting at $0.022 per 1M is the safe choice; the difference is negligible.
- Batch and Priority processing meters also exist (for example gpt-5 Global Batch $0.625 / $5.00, Priority $2.50 / $20.00). Newer models (gpt-5.2 to gpt-5.6, GPT-6) are listed but out of scope.
- Example: one learner using 200K input + 50K output tokens on gpt-5-mini Global = 0.2 x 0.25 + 0.05 x 2.00 = $0.15.

## 12. Azure Storage: Standard GPv2 Hot LRS block blob

Filter: `serviceName eq 'Storage' and (armRegionName eq 'eastus2' or armRegionName eq 'eastus') and productName eq 'General Block Blob v2' and skuName eq 'Hot LRS' and priceType eq 'Consumption'`. Raw: `pricing-raw-storage-blob-hot-lrs.json`.

| Region | serviceName | productName | skuName | meterName | unitOfMeasure | retailPrice (USD) | Monthly |
|---|---|---|---|---|---|---|---|
| eastus2 | Storage | General Block Blob v2 | Hot LRS | Hot LRS Data Stored (first 50 TB) | 1 GB/Month | 0.0184 | per GB |
| eastus2 | Storage | General Block Blob v2 | Hot LRS | Hot LRS Write Operations | 10K | 0.05 | usage |
| eastus2 | Storage | General Block Blob v2 | Hot LRS | Hot Read Operations | 10K | 0.004 | usage |
| eastus2 | Storage | General Block Blob v2 | Hot LRS | All Other Operations | 10K | 0.004 | usage |
| eastus | Storage | General Block Blob v2 | Hot LRS | Hot LRS Data Stored (first 50 TB) | 1 GB/Month | 0.0208 | per GB |
| eastus | Storage | General Block Blob v2 | Hot LRS | Hot LRS Write Operations | 10K | 0.05 | usage |
| eastus | Storage | General Block Blob v2 | Hot LRS | Hot Read Operations | 10K | 0.004 | usage |
| eastus | Storage | General Block Blob v2 | Hot LRS | All Other Operations | 10K | 0.004 | usage |

Notes: a 10 GB lab account costs about $0.18/month in East US 2 ($0.21 in East US) plus cents of operations. Cross-check: calculator graduated `general-purpose-v2-block-blob-flat-hot-lrs` us-east-2 0.0184 (then 0.017664 above 50 TB, 0.016928 above 500 TB), us-east 0.0208.

## 13. Microsoft Foundry Agent Service: any separate charge for agents, MCP tool or AI Search tool?

Answer: **No separate charge for prompt agents themselves (creating agents, conversations, runs) and no agent-layer meter for the MCP tool or the Azure AI Search tool.**

- Foundry Agent Service pricing page (azure.microsoft.com/pricing/details/foundry-agent-service/) states there is "no additional charge for creating or running Foundry-native agents" built with prompts and workflows. It lists as billable: model tokens (through Foundry Models), File Search storage per GB-day (1 GB free), Code Interpreter per session, Web Search and Custom Search per 1,000 transactions, and hosted agents (container compute per vCPU-hour and GiB-hour). It also says tools and knowledge connections carry their own separate charges, naming Logic Apps connectors, Fabric data agent, SharePoint, Grounding with Bing Search and Foundry IQ (Azure AI Search).
- Microsoft Learn, Foundry Agent Service FAQ (learn.microsoft.com/azure/foundry/agents/faq): you pay base-model inference, Code Interpreter sessions and File Search vector storage; there is no additional pricing for using the Agent Service itself.
- Microsoft Learn, "Pricing for voice-based agents" (learn.microsoft.com/azure/foundry/agents/concepts/voice-agent-pricing): tool calls add model turns, and server-side tools such as toolboxes and MCP servers bill through their own resources.
- Therefore: MCP tool = $0 at the agent layer; cost is the MCP server host (for example Container Apps, item 7) plus the extra tokens of tool-call turns. AI Search tool = $0 at the agent layer; cost is the AI Search service (item 5: SU-hours, plus semantic ranker or agentic retrieval tokens if used).

Agent-related meters found in the API (filters `contains(productName, 'Agent') and (armRegionName eq 'eastus2' or armRegionName eq 'eastus' or armRegionName eq 'Global' or armRegionName eq '')` and the same with `meterName`; raw `pricing-raw-agent-meters.json`, `pricing-raw-agent-meters-by-metername.json`, `pricing-raw-agent-tools-selected.json`, `pricing-raw-foundry-tools-eastus2.json`):

| Region | serviceName | productName | skuName | meterName | unitOfMeasure | retailPrice (USD) | When it applies |
|---|---|---|---|---|---|---|---|
| eastus2 and eastus | Foundry Models | Azure OpenAI | Code-Interpreter-global | Code-Interpreter-global Session | 1 | 0.03 | only if Code Interpreter is enabled |
| eastus2 and eastus | Foundry Models | Azure OpenAI | Assistants-File Search-glbl | Assistants-File Search-glbl GB | 1/Day | 0.10 | only if File Search vector storage is used |
| eastus2 and eastus | Foundry Models | Azure OpenAI | file-search-tool-calls-glbl | file-search-tool-calls-glbl Calls | 1K | 2.50 | only if the File Search tool is called |
| eastus2 and eastus | Foundry Tools | Foundry Agents | Hosted | Hosted vCPU Usage | 1 Hour | 0.0994 | hosted (container) agents only |
| eastus2 and eastus | Foundry Tools | Foundry Agents | Hosted | Hosted Memory Usage | 1 Hour | 0.0118 | hosted (container) agents only, per GiB-hour |
| eastus2 and eastus | Foundry Tools | Foundry Agents | Skills Execution | Skills Execution Container | 1 Hour | 0.033 | only if that feature is used |
| eastus2 | Foundry Tools | Foundry Agents | Short Term Memory | Short Term Memory Events Stored | 1K | 0.25 | memory (preview) only |
| eastus2 | Foundry Tools | Foundry Agents | Long Term Memory | Long Term Memory Memories | 1K/Month | 0.25 | memory (preview) only |
| eastus2 | Foundry Tools | Foundry Agents | Memory Retrieval | Memory Retrievals | 1K | 0.50 | memory (preview) only |

Notes:
- Memory is in public preview; Learn ("Memory in Microsoft Foundry Agent Service") says you are billed for the underlying chat and embedding models and that pricing can change during preview. The API already lists the three memory meters for East US 2 (effective 2026-05-01) and none for East US.
- No meter specific to MCP, OpenAPI, function calling or the Azure AI Search tool was found.
- Not found: a Web Search or Bing grounding meter within the Foundry Models data pulled for this item (searched meterName for "web search" and "bing" in eastus2). Out of scope here; the agent pricing page lists Web Search per 1,000 transactions.

## 14. Non-Azure licences (published list prices)

| Product | List price (USD) | Terms | Source |
|---|---|---|---|
| Power Apps Developer Plan | 0 (free) | Development and test only, not production; work or school (Entra ID) account required; 750 flow runs per month and 2 GB Dataverse; up to 3 developer environments; tenant must allow viral/internal sign-ups; inactive environments are disabled after 30 days | Microsoft Learn, "Power Apps Developer Plan" (learn.microsoft.com/power-platform/developer/plan, updated 2026-06-22) |
| Microsoft Entra ID P1 | 7.00 per user per month | Paid yearly (annual commitment) | microsoft.com/en-us/security/business/microsoft-entra-pricing |
| Microsoft Entra ID P2 | 10.00 per user per month | Paid yearly (annual commitment) | same page |
| Microsoft 365 E5 (with Teams) | 60.00 per user per month | List price effective 1 July 2026 (was 57.00) | microsoft.com/en-us/licensing/news/2026-m365-packaging-pricing-updates |
| Microsoft 365 E5 (no Teams) | 51.45 per user per month | Effective 1 July 2026 (was 48.45) | same page |

Notes:
- Entra P1 and P2 were $6.00 and $9.00 before 1 July 2026 (same licensing news page). Entra Suite is listed at $12.00 per user per month.
- The Microsoft 365 E5 product page (microsoft.com/en-us/microsoft-365/enterprise/e5) timed out on three fetch attempts, so the E5 figures come from the official Microsoft licensing news page above. Microsoft 365 E3 for reference: $39.00 (was $36.00).

---

## Recommended rows for the cost workbook

Billing basis: **uptime** = billed every hour the resource exists, used or not; **duration** = billed only while running (stop, deallocate or delete to stop it); **consumption** = billed per unit used. Monthly = 730 hours, East US 2 list price, USD.

| # | Item | Type and size | Monthly cost East US 2 (USD) | Billing basis | Meter name |
|---|---|---|---|---|---|
| 1 | Lab VM | Standard_D2s_v3 Windows, pay-as-you-go | 137.24 (0.188/hr) | duration | D2s v3 (Virtual Machines DSv3 Series Windows) |
| 2 | Lab VM, larger | Standard_D4s_v3 Windows, pay-as-you-go | 274.48 (0.376/hr) | duration | D4s v3 (Virtual Machines DSv3 Series Windows) |
| 3 | VM OS disk | Standard SSD E10 LRS, 128 GiB | 9.60 per disk (0.0132/hr) plus 0.002 per 10K ops | uptime | E10 LRS Disk; E10 LRS Disk Operations |
| 4 | VM disk, budget | Standard HDD S10 LRS, 128 GiB | 5.89 per disk plus 0.0005 per 10K ops | uptime | S10 LRS Disk; S10 LRS Disk Operations |
| 5 | Public IP | Standard static IPv4 | 3.65 (0.005/hr) | uptime | Standard IPv4 Static Public IP |
| 6 | Browser RDP container | ACI Linux, 1 vCPU, 1.5 GB | 34.44 (0.047175/hr) | duration | Standard vCPU Duration; Standard Memory Duration |
| 7 | Search | Azure AI Search Basic, 1 SU | 73.73 (0.101/hr) | uptime | Basic Unit |
| 8 | Search, alternative | Azure AI Search Standard S1, 1 SU | 245.28 (0.336/hr) | uptime | Standard S1 Unit |
| 9 | Semantic ranker | Per 1,000 requests | 1.00 per 1K after 1K free per month | consumption | Semantic Ranker queries |
| 10 | API gateway | APIM Developer, 1 unit | 48.03 (0.0658/hr) | uptime | Developer Unit |
| 11 | API gateway, alternative | APIM Basic v2, 1 unit, 10M calls included | 150.00 (0.20548/hr) plus 3.00 per extra 1M calls | uptime | Basic v2 Unit; Basic v2 Calls |
| 12 | API gateway, alternative | APIM Standard v2, 1 unit, 50M calls included | 700.00 (0.9589/hr) plus 2.50 per extra 1M calls | uptime | Standard v2 Unit; Standard v2 Calls |
| 13 | App or MCP server hosting | Container Apps consumption, 0.5 vCPU / 1 GiB, 1 replica 24x7 | 34.02 after free grants (39.42 without); 0 when scaled to zero | consumption | Standard vCPU Active Usage; Standard Memory Active Usage; Standard Requests (0.40 per 1M) |
| 14 | Container registry | ACR Basic | 5.07 (0.1666/day) | uptime | Basic Registry Unit |
| 15 | Container registry, alternative | ACR Standard | 20.28 (0.6666/day) | uptime | Standard Registry Unit |
| 16 | Image builds | ACR Tasks | 0.0001 per second of task run | consumption | Task vCPU Duration |
| 17 | Secrets | Key Vault Standard | 0.03 per 10K operations (pennies per lab) | consumption | Operations |
| 18 | Logs and Application Insights | Log Analytics Analytics Logs, pay-as-you-go | 2.76 per GB ingested (5 GB per month free per billing account) | consumption | Analytics Logs Data Ingestion |
| 19 | LLM | gpt-5-mini, Global Standard | 0.25 input / 0.025 cached / 2.00 output per 1M tokens | consumption | GPT 5 Mini Inpt Glbl / cchd Inpt Glbl / outpt Glbl 1M Tokens |
| 20 | LLM | gpt-5.1, Global Standard | 1.25 / 0.125 / 10.00 per 1M tokens | consumption | GPT 5.1 inp Gl / cd inp Gl / opt Gl 1M Tokens |
| 21 | LLM | gpt-4.1, Global Standard | 2.00 / 0.50 / 8.00 per 1M tokens | consumption | gpt 4.1 Inp glbl / cached Inp glbl / Outp glbl Tokens |
| 22 | LLM | gpt-4.1-mini, Global Standard | 0.40 / 0.10 / 1.60 per 1M tokens | consumption | gpt 4.1 mini Inp glbl / cached Inp glbl / Outp glbl Tokens |
| 23 | Embeddings | text-embedding-3-small, Global Standard | 0.02 per 1M tokens (0.022 regional / Data Zone) | consumption | text-embedding-3-small-glbl Tokens |
| 24 | Storage | GPv2 Hot LRS block blob | 0.0184 per GB-month (10 GB = 0.18) plus operations | consumption | Hot LRS Data Stored |
| 25 | Agent runtime | Foundry Agent Service prompt agent with MCP and AI Search tools | 0 (no agent or tool meter; pay tokens, AI Search and the MCP host) | consumption | none |
| 26 | Licence | Power Apps Developer Plan | 0 per user | licence (per user per month) | none |
| 27 | Licence | Microsoft Entra ID P1 | 7.00 per user | licence (per user per month, annual) | none |
| 28 | Licence | Microsoft Entra ID P2 | 10.00 per user | licence (per user per month, annual) | none |
| 29 | Licence | Microsoft 365 E5 (with Teams) | 60.00 per user (51.45 no Teams) | licence (per user per month) | none |

Workbook cautions:
- Region choice: East US is cheaper than East US 2 only for Log Analytics ($2.30 vs $2.76 per GB ingested); blob storage is cheaper in East US 2 ($0.0184 vs $0.0208 per GB-month); every other row has the same price in both regions.
- Free allowances (Container Apps grants per subscription; Log Analytics 5 GB per billing account; semantic ranker 1K requests and agentic retrieval 50M tokens per month per service) should be set to zero in the workbook unless each lab gets its own subscription or billing account.
- For short labs, use the hourly figures in brackets times lab hours for duration and uptime rows; uptime resources (disks, IP, AI Search, APIM, ACR) bill for as long as they exist, so the lab teardown time matters.

## Files in this folder

- `research-pricing.md` (this report)
- `azprice.ps1`, `calc.ps1` (query helpers)
- Retail API raw data: `pricing-raw-vm.json`, `pricing-raw-disks.json`, `pricing-raw-publicip.json`, `pricing-raw-aci.json`, `pricing-raw-aisearch.json`, `pricing-raw-aisearch-global.json`, `pricing-raw-apim.json`, `pricing-raw-aca.json`, `pricing-raw-acr.json`, `pricing-raw-keyvault.json`, `pricing-raw-loganalytics.json`, `pricing-raw-azuremonitor.json`, `pricing-raw-appinsights.json`, `pricing-raw-foundry-models-aoai-all.json`, `pricing-raw-aoai-selected.json`, `pricing-raw-storage-blob-hot-lrs.json`, `pricing-raw-agent-meters.json`, `pricing-raw-agent-meters-by-metername.json`, `pricing-raw-agent-tools-selected.json`, `pricing-raw-foundry-tools-eastus2.json`
- Pricing page / calculator feeds (cross-check): `pricing-raw-calc-virtual-machines.json` (trimmed), `pricing-raw-calc-managed-disks.json`, `pricing-raw-calc-ip-addresses.json`, `pricing-raw-calc-container-instances.json`, `pricing-raw-calc-search.json`, `pricing-raw-calc-api-management.json`, `pricing-raw-calc-container-apps.json`, `pricing-raw-calc-container-registry.json`, `pricing-raw-calc-key-vault.json`, `pricing-raw-calc-monitor.json`, `pricing-raw-calc-openai-service.json`, `pricing-raw-calc-storage.json`

---

## Addendum: Sweden Central prices used in the cost workbook (retrieved 2026-10-01)

The lab design moved to Sweden Central, `Standard_D4s_v5` and `gpt-5.4-mini` after the East US research above. These rows were re-queried from the Azure Retail Prices API for `armRegionName eq 'swedencentral'` (raw files in `pricing-raw-swedencentral/`) and are the ones used in `estimates/Cost-Estimation-Agentic-MSP-Support-Agent.xlsx`.

| Item | Meter | Unit price (USD) | Monthly (x730 or as listed) |
|---|---|---|---|
| Lab VM, Windows | Virtual Machines Dsv5 Series Windows, D4s v5 | 0.388 per hour | 283.24 |
| OS disk | Standard SSD Managed Disks, E10 LRS Disk | 9.60 per month | 9.60 |
| Public IP | IP Addresses, Standard IPv4 Static Public IP | 0.005 per hour | 3.65 |
| Browser RDP container | Container Instances, Standard vCPU Duration 0.0466 per hour + Standard Memory Duration 0.00511 per GB-hour (1 vCPU, 1.5 GB) | 0.054265 per hour | 39.61 |
| Azure AI Search | Azure AI Search, Basic Unit | 0.101 per hour | 73.73 |
| Semantic ranker | Semantic Ranker queries | 1.00 per 1K | usage |
| API Management | API Management, Basic v2 Unit | 0.27 per hour | 197.10 |
| API Management calls | Basic v2 Calls | 0.04 per 10K | usage |
| Container Apps | Standard vCPU Active Usage 0.000024 per second; Standard Memory Active Usage 0.000003 per GiB-second (0.5 vCPU, 1 GiB) | 0.054 per hour | 39.42 (active rates) |
| Container Apps environment | Environment Management Hour (dedicated, private endpoint or planned maintenance only) | 0.13 per hour | not charged for consumption-only |
| Container Registry | Container Registry, Basic Registry Unit | 0.1666 per day | 5.07 |
| ACR Tasks | Task vCPU Duration, 0 for the first 6,000 seconds, then 0.0001 per second | usage | usage |
| Key Vault | Key Vault Standard, Operations | 0.03 per 10K | usage |
| Log Analytics | Analytics Logs Data Ingestion, 0 for the first 5 GB then 2.99 per GB; retention 0.13 per GB-month | usage | usage |
| gpt-5.4-mini, Global Standard | Azure OpenAI GPT5, 5.4 mini Inp Gl / cd Inp Gl / Opt Gl | 0.75 / 0.075 / 4.50 per 1M tokens | usage |
| text-embedding-3-small, Global Standard | text-embedding-3-small-glbl Tokens | 0.00002 per 1K (0.02 per 1M) | usage |

Sweden Central differs from East US 2 for API Management Basic v2 (0.27 vs 0.20548 per hour), Container Instances (0.0466 vs 0.0405 per vCPU-hour), the Container Apps environment management meter (0.13 vs 0.10), Log Analytics ingestion (2.99 vs 2.76 per GB) and the D4s v5 VM (0.388 per hour; D4s v3 in East US 2 was 0.376).
