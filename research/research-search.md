# Research: Azure AI Search grounding (Blob indexer, integrated vectorization, Foundry knowledge)

Research notes for the lab "Agentic MSP Support Agent Guided Lab" (Relecloud Managed Services scenario), covering TOC task 1.2 and the binding grounding flow: seeded content is exported to Blob storage, indexed in Azure AI Search and retrieved by the agent [R1]. Researched on 2026-11-06 from Microsoft Learn (Learn MCP search and fetch), the official Azure pricing page and the Azure Retail Prices API only. No blogs, lab repos or third-party sites were used. The previous build's search scripts were read only to list what had to be re-verified; no fact in this note comes from them.

Conventions:

- **Bold** text is a UI label (node, tab, filter, column, button, pane section) exactly as written in the cited page. Where pages disagree on a label, both spellings are given and the conflict is listed under OPEN QUESTIONS, the last section.
- [Sxx] is a source ID from section 0. Every statement carries at least one source ID. [Rx] is a design input (the binding requirements and the research brief); it is used only for lab facts such as data set sizes, never for product behavior.
- "Lab design, derived from [Sxx]" marks a recommendation that follows from sourced facts. It is not a product fact and must be proven in the pilot.
- Status: **GA** means the page carries no preview label. **Preview** means the page labels it preview. **Retiring** means the page announces a retirement date.
- Page text is paraphrased. No direct quotes are used; bold labels and code identifiers are copied verbatim.

## 0. Sources

| ID | URL | Page title | Read on |
| - | - | - | - |
| S01 | https://learn.microsoft.com/azure/search/search-import-data-portal | Import data wizard in the Azure portal | 2026-11-06 |
| S02 | https://learn.microsoft.com/azure/search/search-how-to-index-azure-blob-json | Index JSON blobs and files in Azure AI Search | 2026-11-06 |
| S03 | https://learn.microsoft.com/azure/search/search-how-to-index-azure-blob-one-to-many | Indexing blobs and files to produce multiple search documents | 2026-11-06 |
| S04 | https://learn.microsoft.com/azure/search/search-how-to-index-azure-blob-storage | Index data from Azure Blob Storage | 2026-11-06 |
| S05 | https://learn.microsoft.com/azure/search/search-howto-managed-identities-storage | Connect to Azure Storage using a managed identity (Azure AI Search) | 2026-11-06 |
| S06 | https://learn.microsoft.com/azure/search/search-indexer-field-mappings | Field mappings and transformations using Azure AI Search indexers | 2026-11-06 |
| S07 | https://learn.microsoft.com/rest/api/searchservice/naming-rules | Naming rules (Azure AI Search) | 2026-11-06 |
| S08 | https://learn.microsoft.com/azure/search/search-get-started-portal-import-vectors | Quickstart: Vector search in the Azure portal | 2026-11-06 |
| S09 | https://learn.microsoft.com/azure/search/search-get-started-portal | Quickstart: Full-text search in the Azure portal | 2026-11-06 |
| S10 | https://learn.microsoft.com/azure/search/search-how-to-create-search-index | Create an index in Azure AI Search | 2026-11-06 |
| S11 | https://learn.microsoft.com/azure/search/search-how-to-create-indexers | Create an indexer in Azure AI Search | 2026-11-06 |
| S12 | https://learn.microsoft.com/azure/search/cognitive-search-skill-azure-openai-embedding | Azure OpenAI Embedding skill | 2026-11-06 |
| S13 | https://learn.microsoft.com/azure/search/vector-search-integrated-vectorization | Integrated vector embedding in Azure AI Search | 2026-11-06 |
| S14 | https://learn.microsoft.com/azure/search/vector-search-vectorizer-azure-open-ai | Azure OpenAI vectorizer | 2026-11-06 |
| S15 | https://learn.microsoft.com/azure/search/vector-search-how-to-configure-vectorizer | Configure a vectorizer in a search index | 2026-11-06 |
| S16 | https://learn.microsoft.com/azure/search/vector-search-how-to-chunk-documents | Chunk large documents for RAG and vector search in Azure AI Search | 2026-11-06 |
| S17 | https://learn.microsoft.com/azure/foundry/agents/how-to/tools/ai-search | Connect an Azure AI Search index to Foundry agents | 2026-11-06 |
| S18 | https://learn.microsoft.com/azure/foundry/agents/how-to/tools/toolbox | Create and manage a toolbox in Foundry | 2026-11-06 |
| S19 | https://learn.microsoft.com/azure/foundry/agents/how-to/configure-voice-agent (foundry-portal pivot) | Configure a voice agent | 2026-11-06 |
| S20 | https://learn.microsoft.com/azure/foundry/agents/concepts/what-is-foundry-iq | What is Foundry IQ? | 2026-11-06 |
| S21 | https://learn.microsoft.com/azure/foundry/agents/how-to/foundry-iq-connect | Connect a Foundry IQ knowledge base to Foundry Agent Service | 2026-11-06 |
| S22 | https://learn.microsoft.com/azure/search/agentic-knowledge-source-how-to-search-index (rest pivot) | Create a search index knowledge source | 2026-11-06 |
| S23 | https://learn.microsoft.com/azure/search/search-security-rbac | Connect to Azure AI Search using roles | 2026-11-06 |
| S24 | https://learn.microsoft.com/azure/search/search-how-to-managed-identities | Configure a search service to connect using a managed identity | 2026-11-06 |
| S25 | https://learn.microsoft.com/azure/search/search-monitor-indexers | Monitor indexer status and results in Azure AI Search | 2026-11-06 |
| S26 | https://learn.microsoft.com/rest/api/searchservice/documents/count | Documents - Count (REST API 2026-04-01) | 2026-11-06 |
| S27 | https://learn.microsoft.com/azure/search/search-limits-quotas-capacity | Service limits in Azure AI Search | 2026-11-06 |
| S28 | https://learn.microsoft.com/azure/search/semantic-how-to-enable-disable | Enable or disable semantic ranker billing | 2026-11-06 |
| S29 | https://prices.azure.com/api/retail/prices | Azure Retail Prices API (queries and results in section 11) | 2026-11-06 |
| S30 | https://azure.microsoft.com/en-us/pricing/details/search/ | Foundry IQ pricing (Azure AI Search pricing page) | 2026-11-06 |
| S31 | https://learn.microsoft.com/azure/foundry/openai/quotas-limits | Azure OpenAI in Microsoft Foundry Models quotas and limits | 2026-11-06 |
| S32 | https://learn.microsoft.com/azure/search/search-region-support | Supported regions for Azure AI Search | 2026-11-06 |
| S33 | https://learn.microsoft.com/azure/search/semantic-how-to-configure | Configure semantic ranker and return captions in search results | 2026-11-06 |
| S34 | https://learn.microsoft.com/azure/search/search-security-enable-roles | Enable or disable role-based access control in Azure AI Search | 2026-11-06 |
| S35 | https://learn.microsoft.com/azure/search/search-howto-run-reset-indexers | Run or reset indexers, skills, or documents | 2026-11-06 |
| S36 | https://learn.microsoft.com/azure/search/search-explorer | Quickstart: Use Search explorer to run queries in the Azure portal | 2026-11-06 |
| S37 | https://learn.microsoft.com/azure/search/search-how-to-manage-index | Manage an index in Azure AI Search | 2026-11-06 |
| S38 | https://learn.microsoft.com/azure/foundry/agents/concepts/agent-identity | Agent identity concepts in Microsoft Foundry | 2026-11-06 |
| S39 | https://learn.microsoft.com/azure/foundry/how-to/connections-add | Add a new connection to your project | 2026-11-06 |
| S40 | https://learn.microsoft.com/entra/identity/managed-identities-azure-resources/managed-identity-best-practice-recommendations | Managed identity best practice recommendations | 2026-11-06 |
| S41 | https://learn.microsoft.com/azure/templates/microsoft.search/searchservices | Microsoft.Search searchServices (template reference, latest 2026-11-01) | 2026-11-06 |
| S42 | https://learn.microsoft.com/azure/role-based-access-control/built-in-roles | Azure built-in roles | 2026-11-06 |
| S43 | https://learn.microsoft.com/azure/storage/blobs/authorize-data-operations-portal | Choose how to authorize access to blob data in the Azure portal | 2026-11-06 |
| S44 | https://learn.microsoft.com/azure/search/search-api-versions | API versions in Azure AI Search | 2026-11-06 |
| S45 | https://learn.microsoft.com/rest/api/searchservice/search-service-api-versions | Data plane REST API versions (Azure AI Search) | 2026-11-06 |
| S46 | https://learn.microsoft.com/azure/search/cognitive-search-output-field-mapping | Map enriched output to fields in a search index (output field mappings) | 2026-11-06 |
| S47 | https://learn.microsoft.com/azure/search/cognitive-search-working-with-skillsets | Skillset concepts in Azure AI Search | 2026-11-06 |
| S48 | https://learn.microsoft.com/azure/foundry/agents/concepts/toolbox-overview | What is Toolbox in Foundry? | 2026-11-06 |
| S49 | https://learn.microsoft.com/azure/search/get-started-portal-agentic-retrieval | Quickstart: Agentic retrieval in the Azure portal | 2026-11-06 |
| S50 | https://learn.microsoft.com/azure/foundry/concepts/concept-playgrounds | Microsoft Foundry Playgrounds | 2026-11-06 |
| S51 | https://learn.microsoft.com/azure/search/whats-new | What's new in Azure AI Search | 2026-11-06 |
| S52 | https://learn.microsoft.com/azure/search/cognitive-search-common-errors-warnings | Troubleshooting common indexer errors and warnings in Azure AI Search | 2026-11-06 |
| S53 | https://learn.microsoft.com/azure/search/search-indexer-troubleshooting | Indexer troubleshooting guidance for Azure AI Search | 2026-11-06 |
| S54 | https://learn.microsoft.com/azure/search/vector-search-how-to-generate-embeddings | Generate embeddings for search queries and documents | 2026-11-06 |
| S55 | https://learn.microsoft.com/azure/search/semantic-search-overview | Semantic ranking in Azure AI Search | 2026-11-06 |
| S56 | https://learn.microsoft.com/azure/search/search-indexer-overview | Indexers in Azure AI Search | 2026-11-06 |
| S57 | https://learn.microsoft.com/azure/foundry/how-to/develop/create-prompt-agent-visual-studio-code | Create a prompt agent with Microsoft Foundry Toolkit for Visual Studio Code | 2026-11-06 |

Design inputs (requirements, not product facts):

| ID | Document | Used for |
| - | - | - |
| R1 | Binding requirements, SOW revision of 2026-11-06 (sanitized), `SOW-v3-requirements.md` in the session scratchpad | Data set minimums, binding data flow, isolation per tenant, no tenant admin role for participants, model token allowance, acceptance criteria 4 and 5 |
| R2 | Research brief for this note | Planned environment (Basic search, Foundry project with text-embedding-3-small Global Standard and a GPT-5.1 prompt agent, Storage export of about 700 JSON documents), task 1.2 steps, 15-minute budget |

Coverage note: S17, S18 and S19 are long multi-pivot pages. All prose, the REST pivot, the C# prompt-agent sample, Limitations, Setup and Troubleshooting of S17 were read; other language samples were skimmed. S18 was read for prerequisites, feature support, tool configuration and troubleshooting; per-language samples were skimmed. S19 was read for the Foundry portal pivot. S42 was read for the role rows cited. All other pages were read in full.

## 1. Status at a glance

| Feature | Status | Date or condition | Source |
| - | - | - | - |
| Azure AI Search, Dedicated Basic tier | GA | Basic or higher is required for managed identity; services created after April 3, 2024 allow 3 replicas and 3 partitions | S24, S27 |
| Blob indexer with JSON parsing modes `json`, `jsonArray`, `jsonLines` | GA | No preview label | S02, S04 |
| System-assigned managed identity on indexer data sources | GA | User-assigned identity on data sources is GA from Search Service REST 2026-04-01 | S24, S51 |
| Integrated vectorization (Azure OpenAI Embedding skill plus Azure OpenAI vectorizer) | GA | GA as long as a GA skill and vectorizer pair is used | S13, S15 |
| Text Split skill (chunking) | GA | Token-based chunking needs the latest preview API | S16 |
| **Import data** wizard (one wizard: **Keyword search**, **RAG**, **Multimodal RAG**) | GA | **Import data** and **Import data (new)** were unified in March 2026 | S01, S51 |
| Semantic ranker | GA | Free plan is the default; first 1,000 requests per month are free; query rewrite is preview | S28, S30, S55 |
| Search Service (data plane) REST API | GA `2026-04-01` (latest stable); preview `2026-08-01-preview` | Checked 2026-11-06 | S45 |
| `Microsoft.Search/searchServices` template API | `2026-11-01` listed as latest | Checked 2026-11-06 | S41 |
| Foundry Azure AI Search tool | GA | Basic and standard agent setup; one index per tool; search service and agent in the same tenant | S17 |
| Foundry toolbox | GA for the toolbox (no preview label on the overview); toolbox integration in prompt agents through the VS Code toolkit is preview; skills are preview | Attaching a toolbox replaces an agent's individual tools | S48, S57 |
| Foundry IQ knowledge bases connected to an agent | Preview | Portals give preview-only access to agentic retrieval; the agent connection uses a `RemoteTool` connection (preview) and the `2026-08-01-preview` MCP endpoint | S20, S21 |
| Knowledge bases and search index knowledge sources (REST) | GA | Extractive retrieval in REST `2026-04-01` since April 2026 | S51 |
| Agentic retrieval in the Azure portal | Preview | Portal uses `2026-08-01-preview` | S49 |
| Citation URLs for indexed knowledge sources | Preview | August 2026 | S51 |
| Document-level sensitivity label indexing | Preview | Announced November 2025 | S51 |
| Serverless Developer tier | Preview | Billed from 2026-09-13; not used in this lab | S27 |
| text-embedding-3-small Global Standard quota | Volatile | Tier 1 and Free tier (Tier 0): 1,000,000 TPM (1000 requests per 10 s); subscription-level quota pools started after May 7, 2026, beginning with some models and extending to all | S31 |
| AI Search region capacity | Volatile | On 2026-11-06 East US 2, Sweden Central, North Europe, West Europe, Germany West Central and UAE North carry the high-demand footnote (no new search services); East US does not | S32 |

## 2. Navigation and exact click paths

Portals: Azure portal and Microsoft Foundry portal (**New Foundry** toggle on, Foundry (new) experience) [S20, S39].

| Page or task | Click path | What the page shows | Source |
| - | - | - | - |
| Start the import wizard | Search service > **Overview** > **Import data** > data source **Azure Blob Storage** > scenario **Keyword search**, **RAG** or **Multimodal RAG** | Full-window wizard; the scenario decides data sources, skills, schema and indexer configuration | S01, S08, S09 |
| Keyword search scenario | **Connect to your data** (subscription, storage account, container, parsing mode **JSON array**, **Authenticate using managed identity**, identity type **System-assigned**) > **Next** > skip AI enrichment with **Next** > per field **Configure field** (**Key**, **Retrievable**, **Filterable**, **Sortable**, **Searchable**, **Facetable**) > **Next** > advanced settings (semantic ranking, schedule) > **Next** > object name prefix > **Create** | Creates and runs data source, index and indexer | S09 |
| RAG scenario | **Connect to your data** (optional **Enable deletion tracking**, **Authenticate using managed identity**, **System-assigned**) > **Next** > **Vectorize your text** (kind **Azure OpenAI** or **Microsoft Foundry**, model, authentication **System assigned identity**, billing checkbox) > **Next** > **Vectorize and enrich your images** (skip) > **Advanced settings** (semantic ranking; **Index fields** > **Preview and edit** > **Add field**, **Reset**; **Schedule indexing** **Once**) > **Next** > **Review and create** prefix > **Create** | Creates data source, index with vectorizer, skillset (Text Split, embedding skill, index projections) and indexer | S08 |
| Indexer status | **Search management** > **Indexers** > select indexer > **Execution History** or **Execution details** > select a status | Status **In Progress**, **Success**, **Failed** or **Reset**; **Docs Succeeded**; **Refresh**; errors and warnings pane | S09, S25, S52 |
| Reset and run an indexer | **Overview** > **Indexers** tab > select indexer > **Reset** > **Yes** > **Run** | Full reprocess after reset | S35 |
| Index list and statistics | **Search management** > **Indexes** > select index | Columns **Name**, **Document count**, **Vector index quota usage**, **Total storage size**; index page statistics; **Edit JSON**; **Fields** tab; **Search explorer** tab; **Delete** | S09, S36, S37 |
| Count check in Search explorer | **Overview** > **Search explorer** (or the index **Search explorer** tab) > **View** > **JSON view** > `{"search": "*", "count": true}` > **Search**; **Query options** > **Hide vector values in search results** | Total documents in the index on an empty search | S08, S36 |
| Semantic configuration | **Indexes** > select index > **Semantic configurations** > **Add semantic configuration** > **New semantic configuration** > **Save** > **Save** | Title, content and keyword fields in priority order | S33 |
| Build objects one by one | **Overview** > **Add index** (embedded editor); **Data sources** tab > **Add data source**; **Add indexer** (visual editor) | Index designer, data source and indexer editors | S10, S11, S56 |
| Search service identity | **Settings** > **Identity** > **System assigned** tab > **Status** **On** > **Save** | Object ID of the system-assigned identity | S24 |
| Data plane authentication | **Settings** > **Keys** > **API Key**, **Role-based access control** or **Both** | API key is the default | S34 |
| Semantic ranker plan | **Settings** > **Premium features** > **Semantic ranker** > **Select plan** on the **Standard** or **Free** card | Billing plan for the service | S28 |
| Role assignment | Resource > **Access control (IAM)** > **+ Add** > **Add role assignment** > role > **Members** > **Review + assign** | Portal can't assign roles at index scope | S23 |
| Review exported blobs | Storage account > **Data storage** > **Containers** (or **Overview** > **Properties** > **Blobs** tile) | Authentication method shown as **Access Key** or **Microsoft Entra user Account**; **Switch to Microsoft Entra user account** link | S43 |
| Foundry project connection | Foundry portal > **Manage** > **Project details** > **Connected resources** tab > **Add connection** > **Azure AI Search** > browse service > **Authentication** > **Add connection** | Connection listed under connected resources | S17, S39 |
| Add Azure AI Search through a toolbox (documented for voice-based prompt agents) | Agent playground > **Tools** > **Add a toolbox** > **Create a toolbox** > **Basic info** (**Name**, description) > **Included** > **Add** > **Add tool** > **Azure AI Search** > **Description** > **Azure AI Search connection** (or **Connect to new resource**) > select index > **Add** > optional **Tool search** > **Publish** > main **Save** | Toolbox appears in **Tools**; starts with **Simple** query type and 5 results, configurable from 1 to 50 | S19 |
| Add a tool to a saved prompt agent in VS Code | Foundry Toolkit Agent Builder > **Playground** tab > **Tool** > **+** > **Add tools** > **Select a tool** (**Configured** or **Catalog**) > **Add Tool** > **Save to Foundry** | Individual tool on a new agent version | S57 |
| Agent page tabs (voice agent page) | Agent > **Playground**, **Details**, **Traces**, **Monitor**, **Evaluation**, **Channels** | **Traces** shows tool-call spans, arguments, result, status, duration | S19 |
| Playground evaluations | Agents playground > metrics in the upper right > unselect all evaluators | Turns off billed playground evaluations | S50 |
| Foundry IQ (preview) | **Build** > **Knowledge** tab (connect search service, create knowledge base) > **Agents** tab (connect the agent to the knowledge base) | Knowledge base linked to an agent | S20 |
| Agentic retrieval in the Azure portal (preview) | **Agentic retrieval** > **Knowledge sources** > **Add knowledge source** > **Add knowledge source** > **Azure blob (Indexed)**; **Agentic retrieval** > **Knowledge bases** > **Add knowledge base** > **Add knowledge base** | Generated data source, skillset, index and indexer under **Search management** | S49 |

Older or alternate names still found in the documentation: the **Import and vectorize data** wizard was renamed **Import data (new)** in September 2025, and in March 2026 **Import data** and **Import data (new)** were unified into one **Import data** wizard [S51]. Treat **Import data** as current, because the wizard pages and quickstarts fetched today use only that label [S01, S08, S09]. Other drift: the indexer list is reached through **Search management** > **Indexers** in S09, S25 and S52 but through the **Overview** > **Indexers** tab in S35; the Keys page step text says **Role-based control** while its option table says **Role-based access control** [S34]; S01 has the scenario chosen right after **Import data**, while S08 and S09 choose the data source first. These are listed in OPEN QUESTIONS.

## 3. How grounding works in this lab (object model)

- An indexer pulls from one data source and writes to one index, and drives skillset execution in four stages: document cracking, field mappings, skillset execution and output field mappings [S56].
- The blob indexer reads the blobs of one container, optionally limited to a virtual folder through the data source `query` [S04].
- Indexers have no identity of their own: outbound calls to storage and to embedding models use the search service's system- or user-assigned managed identity plus a role on the target resource [S11, S35].
- Integrated vectorization adds vector encoding during indexing (an embedding skill in a skillset) and during queries (a vectorizer defined in the index and assigned to the vector field) [S13]. The vectorizer must use the same embedding model as the skill [S13, S15].
- The Foundry Azure AI Search tool queries one index through a project connection and the model answers with inline citations rendered as `[message_idx:search_idx†source]`; streamed responses carry `url_citation` annotations [S17].
- The Azure AI Search tool authenticates with the connection (API key or Microsoft Entra ID through a managed identity) [S17]. It is not in the list of tools that use the agent's Entra Agent ID [S38]. Lab design, derived from S17 and S38: step (2) of Figure B1 (grounding on AI Search) [R1] is authorized by the project connection's identity, not by the Agent ID; record this in the design pack.
- Lab design flow, derived from S04, S12, S17 and R1: provisioning exports one JSON blob per document to a container > data source (`azureblob`, managed identity) > skillset (Azure OpenAI Embedding skill on `content`) > index (citation fields, vector field with vectorizer, semantic configuration) > indexer (parsing mode `json`) > Foundry project connection (`CognitiveSearch`, Microsoft Entra ID) > Azure AI Search tool on the agent.

## 4. Blob data source, managed identity and JSON parsing

### 4.1 Data source and connection

- A blob data source has `type` `azureblob`, a `credentials.connectionString`, and `container.name` with an optional `container.query` virtual folder [S04].
- Managed identity connection string: `ResourceId=/subscriptions/<subscription>/resourceGroups/<resource-group>/providers/Microsoft.Storage/storageAccounts/<account>;` with no key [S04, S05, S24]; the S04 and S05 examples end the resource ID with `/;`, the S24 example with `;`. System-assigned identity connections use GA API versions [S24].
- User-assigned identity adds an `identity` object with `@odata.type` `#Microsoft.Azure.Search.DataUserAssignedIdentity` and `userAssignedIdentity`; it needs REST `2026-04-01` or later and only one user-assigned identity per data source [S05, S24].
- Prerequisites: Basic tier or higher with a managed identity [S05]; the identity needs **Storage Blob Data Reader** on the storage account [S04, S05], role ID `2a2b9908-6ea1-4ae2-8e65-a410df84e7d1` [S42]. The portal **Members** step filters system-assigned or user-assigned identities; a newly enabled identity can take a few minutes to appear [S05].
- Connection details and permissions are validated only when the indexer runs [S05]; until then data sources, indexes and skillsets are passive [S56].
- Storage must be Standard general-purpose v2; indexers read hot, cool and cold tiers [S04]. Storage with shared key access turned off works when the data source uses managed identity [S52].
- Network: for same-region network-protected storage, only a system-assigned identity with the trusted service exception or a resource instance rule works [S05, S24]. On Basic, indexers with a skillset can't use private endpoints and private connections to a Foundry resource are unsupported [S27]. Lab design, derived from S27 and R1: keep storage, search and Foundry on public endpoints protected by Microsoft Entra authentication.

### 4.2 Parsing modes and file layout

| `parsingMode` | Documents per blob | Behavior | Source |
| - | - | - | - |
| `json` | One | Parses each JSON blob as one search document and promotes its properties to index fields; identically named and typed fields map implicitly | S02 |
| `jsonArray` | Many | Each element of a JSON array becomes a document; `documentRoot` selects a nested array | S02 |
| `jsonLines` | Many | Each newline-separated JSON entity becomes a document | S02 |

- All blobs in one data source use the same parser; use file extension filters if other files share the container [S02].
- One-to-many modes generate an `AzureSearch_DocumentKey` (Base64 encoded) for the key field unless the JSON carries a field named like the index key, in which case that value is the key and duplicates across blobs merge [S03]. Deleting a line from a file that was parsed into many documents doesn't remove that line's document from the index [S03]. One file mapped to many documents is a listed cause of count discrepancies [S53].
- With a JSON parsing mode the enrichment tree exposes properties as `/document/{key}` nodes, which skills can use as inputs [S47].
- If a JSON property is null, the indexer keeps the existing index value; pass an empty string to clear a field [S02]. A field mapping whose source property doesn't exist is skipped without error [S02].
- Lab design, derived from S02, S03, S04 and S53: export one JSON blob per document and use `parsingMode` `json`. The container blob count, the indexer item count and the index document count then line up one to one, which is what the count check needs. Use one virtual folder per content type (for example `kb/`, `docs/`, `tickets/`, `customers/`, `sla/`) and `indexedFileNameExtensions` `.json`. Keep the export manifest out of the indexed container (or give it another extension), because by default the indexer processes every blob in the container [S04].

### 4.3 Document key and field mappings

- Exactly one top-level `Edm.String` field is the key; values are at most 1,024 characters, case-sensitive, and the key field must be retrievable [S10].
- Allowed key characters: letters, numbers, dashes, underscores and equal signs; the first character can't be an underscore [S07]. The indexer error for an invalid key lists the same set [S52].
- Blob default: if no explicit key mapping exists, the blob indexer maps `metadata_storage_path` to the key and encodes it automatically [S03, S04, S06]. Adding an explicit field mapping overrides the default mapping for that source and target [S06].
- `base64Encode` performs URL-safe Base64 encoding; without parameters it defaults to `useHttpServerUtilityUrlTokenEncode: true`, and its warning says keys need that value set to true [S06]. The same page's key example sets it to false (conflict in OPEN QUESTIONS).
- Field mappings resolve names case-insensitively, target only top-level fields, and can lift nested JSON properties with JSON Pointer paths such as `/article/text` [S02, S06]. Field names must start with a letter and can't begin with `azureSearch` [S07].
- Lab design, derived from S06, S07 and S10: give every exported document an `id` built only from allowed characters (for example `kb-KB0058`, `ticket-TCK-10489`), and add the explicit mapping `{ "sourceFieldName": "id", "targetFieldName": "id" }` so the key is readable in citations and lookups with no encoding.

### 4.4 Indexer run, status and limits

- An indexer runs as soon as it's created unless `disabled` is true [S04, S11]. Blob indexing uses a default `batchSize` of 10 [S04]; `dataToExtract` defaults to `contentAndMetadata` [S04].
- By default the blob indexer stops at a blob with an unsupported content type; `maxFailedItems`, `maxFailedItemsPerBatch`, `failOnUnsupportedContentType` and `failOnUnprocessableDocument` control tolerance [S04].
- Maximum running time per run on Basic is 2 hours in the multitenant environment (24 hours only in a private environment); minimum schedule is 5 minutes [S27, S35].
- One indexer job runs per search unit; a running indexer can't be paused or stopped, and a second invocation while one is running returns an error [S35].
- Indexers have no dedicated processing resources: status can show idle before running and run times aren't predictable [S56]. In the multitenant environment, delays happen while processors are added or freed [S35].
- Azure Storage change detection uses LastModified; a run with no changes reports 0/0 documents [S35]. Reset clears the high-water mark, must be followed by Run, and doesn't remove orphaned documents [S35].
- Don't invoke indexers repeatedly in quick succession; pace on-demand runs five minutes or more apart, because overlapping buffers can process a document more than once [S53].
- Status: `GET /indexers/{name}/status?api-version=2026-04-01` returns the indexer status, `lastResult` (`status`, `errorMessage`, `startTime`, `endTime`, `errors`, `itemsProcessed`, `itemsFailed`) and up to 50 runs in `executionHistory`, newest first [S04, S25]. A top-level status of `running` means the indexer is available, not that it's executing; each run has its own status (`running`, `success`, `transientFailure`, `persistentFailure`) [S25].
- Portal pages refresh every few minutes; **Refresh** forces an update; **Docs Succeeded** grows during **In Progress** [S25].

### 4.5 Checking the document count

- REST: `GET {endpoint}/indexes('{indexName}')/docs/$count?api-version=2026-04-01` returns an integer; Microsoft Entra scope `https://search.azure.com/.default` [S26].
- REST: `GET /indexes/{index}/stats` returns document count, storage size and vector index size [S37].
- Portal: **Search management** > **Indexes** shows **Document count**; the index page shows the number of documents, storage and vector storage [S37]. Search explorer with `"search": "*"` and `"count": true` returns the total number of documents [S36].
- The index count can lag, especially in the portal [S53]; processed counts can exceed the source count when documents are processed more than once [S53].
- Lab design, derived from S26, S36 and S53: compare the index count (not the indexer processed count) with the export manifest, and per content type with a filter on a filterable `docType` field in Search explorer JSON view (`"filter": "docType eq 'Knowledge article'"`, `"count": true`).

## 5. Integrated vectorization with text-embedding-3-small

### 5.1 Azure OpenAI Embedding skill

- `@odata.type` `#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill`; required `resourceUri`, `deploymentId`, `modelName` (`text-embedding-ada-002`, `text-embedding-3-large`, `text-embedding-3-small`); optional `apiKey`, `authIdentity`, `dimensions`; input `text`; output `embedding` [S12].
- `resourceUri` accepts `openai.azure.com`, `services.ai.azure.com` and `cognitiveservices.azure.com` domains (and API Management `azure-api.net` endpoints); a Foundry project's parent resource exposes all three endpoints [S12].
- text-embedding-3-small supports 1 to 1,536 dimensions; the default is the maximum; if `dimensions` is set, the vector field must use the same value [S12].
- Maximum text input is 8,000 tokens; larger input is an error and empty text is a warning [S12]. The chunking page gives 8,191 tokens as the model's input limit (conflict in OPEN QUESTIONS) [S16].
- The skill is charged at the Azure OpenAI Standard price [S12], and its data is processed in the Geo of the model deployment [S12].
- Output lives in memory and needs an `outputFieldMapping` to a vector field [S12, S46]. Outputs are added as children of the skill's `context` node; `targetName` renames an output [S47]. The skill page's example maps `/document/embedding/*`, while the output field mapping page maps `/document/content/text_vector` for a skill with context `/document/content` (conflict in OPEN QUESTIONS) [S12, S46].
- Best practices: separate embedding deployments for indexing and for the query vectorizer, same or nearby region, and API Management load balancing for 429 errors [S12, S14].

### 5.2 Vectorizer and vector field

- Vectorizer `kind` `azureOpenAI` with `azureOpenAIParameters` (`resourceUri`, `deploymentId`, `modelName`, optional `apiKey`, `authIdentity`); it supports only `text` vector queries [S14, S15].
- A vector profile links an algorithm (for example `hnsw` with `metric` `cosine`, `m` 4, `efConstruction` 400, `efSearch` 500) and a vectorizer to vector fields through `vectorSearchProfile` [S15].
- Vector field: `Collection(Edm.Single)`, `searchable` true, `dimensions` equal to the model output, `vectorSearchProfile` set [S15]. `retrievable` defaults to false through REST and true through the wizard [S10].
- Query test: `"vectorQueries": [ { "kind": "text", "text": "...", "fields": "contentVector", "k": 3 } ]`; the engine reads vectorizer settings from the field's profile [S15].
- Common errors: 401 or 403 when the search identity lacks **Cognitive Services OpenAI User**, dimension mismatch, 429 rate limiting, vectorizer name not found [S15].

### 5.3 Chunking or not

- Chunking isn't a hard requirement; it's needed only when documents exceed model input limits or are poorly represented by one vector [S13, S16].
- Recommended defaults when chunking by characters are `pages`, 2,000 characters, 500 overlap [S16]. The wizard's RAG scenario applies fixed, nonconfigurable chunking (`pages`, 2,000, 500, characters) [S08].
- Lab design, derived from S12 and S16: do not chunk. Each knowledge article, ticket, customer profile and the SLA snapshot is one short document, so one vector per document keeps one search result per source record and one citation per record. Check at export that the longest `content` stays well under 8,000 tokens (customer profiles and the SLA snapshot are the longest candidates [R2]).

### 5.4 Identity and roles for embedding calls

- With `apiKey` and `authIdentity` empty, the search service's system-assigned identity is used for the skill and the vectorizer [S12, S14, S24].
- That identity needs **Cognitive Services OpenAI User** on the target resource [S12, S14, S24], role ID `5e0bd9bd-7b93-4f28-af87-19fc36ad61bd` [S42]. It is the only role the skill and vectorizer need [S12, S14].
- The search service sends a token for audience `https://cognitiveservices.azure.com` to the configured `resourceUri`; anyone who can edit skillsets or index definitions controls that endpoint, so those permissions should go to trusted people only [S12, S14]. Lab design, derived from S12 and R1: in a per-participant tenant the search identity holds the role only on the participant's own Foundry resource, so the exposure stays inside that environment.

### 5.5 Volume, time and cost for about 700 documents

- Expected document count from the minimums [R1, R2]: 120 knowledge articles + 36 customer documents + 500 historical tickets + 12 customer profiles + 1 SLA snapshot = 669 (729 if the 60 open tickets are exported too). The export manifest, not this arithmetic, is the source of truth for the count check.
- Quota: text-embedding-3-small Global Standard gets 1,000,000 TPM at Tier 1 and at the Free tier (Tier 0) [S31]. Quota is never enforced at tenant level; the subscription is the highest scope [S31]. Subscription-level quota management started after May 7, 2026 with some models first and is extending to all models; under it, Global Standard deployments of the same model and version share one pool across all regions of a subscription [S31].
- Integrated vectorization has built-in, nonconfigurable batching and retry for throttling; if quota is exhausted, retries fail, and a schedule is recommended to pick up throttled documents [S13].
- Price: $0.00002 per 1,000 tokens for `text-embedding-3-small-glbl` (that is $0.02 per million tokens) in East US, East US 2 and Sweden Central [S29]. Lab design arithmetic, derived from S29: 700 documents at an assumed average of 1,000 tokens is 0.7 million tokens, about $0.014 per full indexing run; query-time vectorization adds only the tokens of each question.
- Token allowance: if embedding tokens count toward the per-environment allowance of 4 million input tokens [R1], one full load at that assumed size uses about 18 percent of it; measure the real average at export (OPEN QUESTIONS).
- Time: no page documents indexing time for this volume; indexer run times aren't predictable [S56] (OPEN QUESTIONS, pilot measurement).

## 6. Portal wizard versus REST path

### 6.1 The current Import data wizard

- One **Import data** wizard creates a data source, an index, an indexer, an optional skillset and an optional knowledge store, and loads data [S01]. Scenarios are **Keyword search**, **RAG** and **Multimodal RAG** [S01].
- Embedding skills (Azure OpenAI embedding, AML, Azure Vision multimodal) are available only in RAG and multimodal RAG [S01]. Semantic ranking is available in every scenario and adds a semantic configuration [S01].
- The schema is inferred from a random sample and can be edited inline; sampling can miss fields [S01]. Attributes chosen in the wizard usually can't be changed later without dropping and rebuilding the index [S01, S10].
- For keys whose values include spaces or dashes, the wizard says to set **Base-64 Encode Key** in the **Create an indexer** step under **Advanced options** [S01] (conflicts with S07, see OPEN QUESTIONS).
- The wizard is a one-way pipeline: it can't edit or reuse objects; field mappings and output field mappings are set internally [S01]. All resources need public access or the wizard fails [S08, S09].
- RAG scenario: generated fields `chunk_id` (key), `parent_id`, `chunk`, `title`, `text_vector` can't be modified, but fields can be added under **Index fields** > **Preview and edit** [S08]. One search document is created per chunk [S08]. The created index conforms to the latest preview REST API [S08].
- RAG embedding providers: the **Azure OpenAI** kind needs an Azure OpenAI resource with a custom subdomain and doesn't support Azure OpenAI resources created in the Foundry portal [S08]; the **Microsoft Foundry** kind calls the AML skill and needs **Foundry Project Manager** on the project's parent resource for the search identity [S08], a role that can also assign Foundry User [S42].
- Keyword search scenario: parsing mode **JSON array** is documented on the **Connect to your data** page, and attributes are set per field with **Configure field** [S09]. The JSON blob page also points to the import wizard for one-JSON-per-blob data sets [S02].

### 6.2 Keyword search versus RAG for this lab

| Need for task 1.2 | Keyword search | RAG | Source |
| - | - | - | - |
| Blob source with managed identity | Yes | Yes | S08, S09 |
| JSON parsing (one file per document or array) | **JSON array** documented; single JSON implied | Not documented | S02, S08, S09 |
| Participant chooses which fields are retrievable, searchable, filterable (the citation lesson) | Yes, **Configure field** | No; generated fields are fixed, extra fields can be added | S08, S09 |
| Vector field and vectorizer with text-embedding-3-small | No embedding skill in this scenario | Yes | S01, S08 |
| Index count equals seeded record count | Yes with one document per record | No; one document per chunk | S08 |
| `url` field for citations | Yes, from the JSON | Only if added as an extra field | S08, S09 |
| Least-privilege embedding identity | Not applicable | **Foundry** kind needs **Foundry Project Manager** for the search identity | S08 |

Lab design, derived from the table [S01, S08, S09]: neither wizard scenario meets all task 1.2 needs. Keyword search teaches the citation fields and gives a clean count but drops the embedding model from grounding; RAG uses the embedding model but hides the field design behind fixed generated fields and counts chunks.

### 6.3 REST path (the reliable alternative)

- API version `2026-04-01` (latest stable; versions are listed in the REST reference) [S44, S45]; Microsoft Entra token with `az account get-access-token --scope https://search.azure.com/.default` [S23].
- Calls: create or update the index (`PUT /indexes/{name}`) [S15]; create the data source (`POST /datasources`) [S05]; create the skillset (`/skillsets/{name}`) [S35, S46]; create the indexer (`POST /indexers`, or `PUT /indexers/{name}`) [S04, S06]; run, reset and status (`POST /indexers/{name}/run`, `POST /indexers/{name}/reset`, `GET /indexers/{name}/status`) [S35]; count (`GET /indexes('{name}')/docs/$count`) [S26]; statistics (`GET /indexes/{name}/stats`) [S37]; query (`POST /indexes/{name}/docs/search`) [S23].
- Object names: index 2 to 128 lowercase letters, numbers, dashes, underscores; data source, indexer and skillset 1 to 128 lowercase letters, numbers, dashes; first and last character a letter or number [S07].
- Roles: **Search Service Contributor** creates indexes, indexers, data sources and skillsets and can run and reset indexers, but can't load documents or query; querying and counting need **Search Index Data Reader** [S23]. Indexers write to any index with the service's own permissions, so the participant needs no data-write role [S23, S35].

Reference definitions (lab design, assembled from documented properties; untested until the pilot; sources under each block):

```json
{
  "name": "servicedesk-blob",
  "type": "azureblob",
  "credentials": { "connectionString": "ResourceId=/subscriptions/<subscription>/resourceGroups/<resource-group>/providers/Microsoft.Storage/storageAccounts/<account>;" },
  "container": { "name": "servicedesk-export" }
}
```

Sources: S04, S05.

```json
{
  "name": "servicedesk-embedding",
  "skills": [
    {
      "@odata.type": "#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill",
      "name": "#1",
      "context": "/document",
      "resourceUri": "https://<foundry-resource>.openai.azure.com",
      "deploymentId": "<embedding-deployment-name>",
      "modelName": "text-embedding-3-small",
      "dimensions": 1536,
      "inputs": [ { "name": "text", "source": "/document/content" } ],
      "outputs": [ { "name": "embedding", "targetName": "contentVector" } ]
    }
  ]
}
```

Sources: S12, S46, S47 (no `apiKey` or `authIdentity`, so the system-assigned identity is used [S24]).

```json
{
  "name": "servicedesk-indexer",
  "dataSourceName": "servicedesk-blob",
  "targetIndexName": "servicedesk-knowledge",
  "skillsetName": "servicedesk-embedding",
  "parameters": {
    "maxFailedItems": 0,
    "configuration": { "parsingMode": "json", "dataToExtract": "contentAndMetadata", "indexedFileNameExtensions": ".json" }
  },
  "fieldMappings": [ { "sourceFieldName": "id", "targetFieldName": "id" } ],
  "outputFieldMappings": [ { "sourceFieldName": "/document/contentVector", "targetFieldName": "contentVector" } ]
}
```

Sources: S02, S04, S06, S11, S46, S47. No `schedule`, so the indexer runs once at creation and then only on demand [S04, S11].

The index definition is in section 7.4.

### 6.4 Recommended participant flow for task 1.2 (about 15 minutes)

Lab design, derived from sections 4 to 8 (sources per row). Script-assisted pipeline, portal verification, citation lesson kept hands-on:

| Step | Participant action | Minutes | Source |
| - | - | - | - |
| 1. Review content | Open one exported blob per content type (storage account > **Data storage** > **Containers**) or the VM copy; identify the text worth retrieving (`content`), the fields needed to cite (`title`, `url`, `sourceId`) and the attributes that separate similar records; note what isn't exported (internal notes, contact details, the two new incidents) | 3 | S43, R1 |
| 2. Create the index | Open the provided index definition; set or confirm the attributes that let the agent cite a source (`title` and `url` retrievable, `content` searchable and retrievable, `id` key); the script validates them and creates the index; confirm in **Indexes** > index > **Fields** | 3 | S10, S17, S37 |
| 3. Load and count | Run the load script: it creates the data source, skillset and indexer (which runs at creation), polls indexer status, then compares `$count` with the export manifest; confirm **Success** in **Indexers** and **Document count** in **Indexes**, or run `{"search": "*", "count": true}` in **Search explorer** | 1 plus wait (pilot to measure) | S04, S25, S26, S36, S37 |
| 4. Add the index to the agent | While the indexer runs: add **Azure AI Search** as an individual tool on the agent, using the pre-created connection and the index; pick the hybrid plus semantic search type if offered; save the agent | 4 | S17, S57 |
| 5. First query | Ask a question only the index can answer; confirm the answer carries a citation whose link opens the source record | 2 | S17 |

- Objects the participant creates: index, data source, skillset, indexer (search side) and one tool on the agent (Foundry side) [S01, S17].
- Fallback for step 2 and 3 when scripts are blocked: the **Import data** wizard **Keyword search** scenario still teaches the field attributes and the count check, but the index has no vector field; set the agent tool's query type to `semantic` or `simple` [S01, S09, S17].
- Fallback for step 4: the Foundry Toolkit Agent Builder path [S57], or a script that saves a new agent version with an `azure_ai_search` tool (tool shape from S17, agent API shape from S21).
- Avoid **Add a toolbox** for this agent: attaching a toolbox replaces an agent's individual tools [S57, S19], and the agent already carries its MCP read and write tool connections [R1].

## 7. Index schema for citations

### 7.1 What the Foundry Azure AI Search tool needs

- Index requirements: one or more searchable and retrievable `Edm.String` fields; one or more searchable `Collection(Edm.Single)` vector fields; at least one retrievable text field with the content to cite; a retrievable field with a source URL, and optionally a title, so citations can link [S17].
- The documented sample index uses fields named `title` and `url` for the citation title and URL [S17]. No page documents a field-mapping option for citation fields (OPEN QUESTIONS).
- Citations appear only if the agent instructions ask for them [S17].
- One index per tool; the search service and the agent must be in the same tenant [S17].

### 7.2 Query types and defaults

- Tool parameters: `project_connection_id` and `index_name` required; `top_k` defaults to 5; `query_type` defaults to `vector_semantic_hybrid` with values `simple`, `vector`, `semantic`, `vector_simple_hybrid`, `vector_semantic_hybrid`; `filter` applies to every query the agent makes [S17].
- In the portal toolbox flow the tool starts with **Simple** and 5 results; another search type and 1 to 50 results can be chosen when the index supports them [S19].
- Text-to-vector conversion at query time needs a vectorizer assigned to the vector field [S13, S15].
- Classic semantic queries need a semantic configuration; queries can name one or use the default configuration [S33, S51].
- Semantic ranking reranks the top 50 results; each document's summary input is up to 2,048 tokens, with the title limited to 128 tokens and keywords to 128 tokens [S55]. Charges occur only when `queryType=semantic` and the search text isn't empty [S55].

### 7.3 Semantic configuration rules

- One title field, any number of content and keyword fields in priority order; all must be `searchable` and `retrievable` strings [S33].
- Up to 100 configurations per index; a default can be set; configurations can be added or changed without rebuilding the index [S10, S27, S33].
- Fixed after creation: index name, key, field names and types, searchable, filterable, facetable and sortable attributes; `retrievable` can still change [S10]. `Edm.String` fields that are filterable, sortable or facetable are limited to 32 KB, so long text fields should set those to false [S10, S52].

### 7.4 Recommended schema (lab design)

Lab design, derived from S07, S10, S15, S17 and S33:

| Field | Type | Attributes | Why | Source |
| - | - | - | - | - |
| `id` | `Edm.String` | key, retrievable, filterable | One key per record, readable values | S07, S10 |
| `docType` | `Edm.String` | filterable, facetable, retrievable; not searchable | Per-type count check and tool filters | S17, S36 |
| `title` | `Edm.String` | searchable, retrievable | Citation title; semantic title field | S17, S33 |
| `url` | `Edm.String` | retrievable; not searchable, filterable, sortable or facetable | Citation link to the source record in the Service Desk app | S17 |
| `sourceId` | `Edm.String` | searchable, filterable, retrievable | Article number, ticket number, customer code; semantic keyword field | S33 |
| `content` | `Edm.String` | searchable, retrievable; not filterable, sortable or facetable | The text the agent reads; embedding input; semantic content field | S10, S12, S33 |
| `customerCode`, `slaTier`, `contractType` | `Edm.String` | filterable, facetable, retrievable | Separate similar records by customer context | S10 |
| `product`, `productVersion`, `category` | `Edm.String` | searchable, filterable, retrievable | Version and category matching | S10 |
| `articleStatus` | `Edm.String` | filterable, retrievable | Retired articles | S10 |
| `contentVector` | `Collection(Edm.Single)` | searchable, retrievable false, dimensions 1536, profile with vectorizer | Vector and hybrid queries | S10, S15 |

```json
{
  "name": "servicedesk-knowledge",
  "fields": [
    { "name": "id", "type": "Edm.String", "key": true, "filterable": true, "retrievable": true },
    { "name": "docType", "type": "Edm.String", "searchable": false, "filterable": true, "facetable": true, "retrievable": true },
    { "name": "title", "type": "Edm.String", "searchable": true, "filterable": false, "sortable": false, "facetable": false, "retrievable": true },
    { "name": "url", "type": "Edm.String", "searchable": false, "filterable": false, "sortable": false, "facetable": false, "retrievable": true },
    { "name": "sourceId", "type": "Edm.String", "searchable": true, "filterable": true, "retrievable": true },
    { "name": "content", "type": "Edm.String", "searchable": true, "filterable": false, "sortable": false, "facetable": false, "retrievable": true },
    { "name": "customerCode", "type": "Edm.String", "searchable": false, "filterable": true, "facetable": true, "retrievable": true },
    { "name": "slaTier", "type": "Edm.String", "searchable": false, "filterable": true, "facetable": true, "retrievable": true },
    { "name": "contractType", "type": "Edm.String", "searchable": false, "filterable": true, "facetable": true, "retrievable": true },
    { "name": "product", "type": "Edm.String", "searchable": true, "filterable": true, "facetable": true, "retrievable": true },
    { "name": "productVersion", "type": "Edm.String", "searchable": true, "filterable": true, "retrievable": true },
    { "name": "category", "type": "Edm.String", "searchable": true, "filterable": true, "facetable": true, "retrievable": true },
    { "name": "articleStatus", "type": "Edm.String", "searchable": false, "filterable": true, "retrievable": true },
    { "name": "contentVector", "type": "Collection(Edm.Single)", "searchable": true, "retrievable": false, "dimensions": 1536, "vectorSearchProfile": "servicedesk-vector-profile" }
  ],
  "vectorSearch": {
    "algorithms": [ { "name": "servicedesk-hnsw", "kind": "hnsw", "hnswParameters": { "metric": "cosine", "m": 4, "efConstruction": 400, "efSearch": 500 } } ],
    "profiles": [ { "name": "servicedesk-vector-profile", "algorithm": "servicedesk-hnsw", "vectorizer": "servicedesk-vectorizer" } ],
    "vectorizers": [
      { "name": "servicedesk-vectorizer", "kind": "azureOpenAI",
        "azureOpenAIParameters": { "resourceUri": "https://<foundry-resource>.openai.azure.com", "deploymentId": "<embedding-deployment-name>", "modelName": "text-embedding-3-small" } }
    ]
  },
  "semantic": {
    "defaultConfiguration": "servicedesk-semantic",
    "configurations": [
      { "name": "servicedesk-semantic",
        "prioritizedFields": {
          "titleField": { "fieldName": "title" },
          "prioritizedContentFields": [ { "fieldName": "content" } ],
          "prioritizedKeywordsFields": [ { "fieldName": "sourceId" }, { "fieldName": "category" } ] } }
    ]
  }
}
```

Sources: S10, S15, S33 (properties); S07 (names). The URL format of a Service Desk record belongs to the Dataverse research note.

## 8. Adding the index to the agent; Foundry IQ

### 8.1 Project connection

- Portal path in section 2 [S17, S39]. CLI: `az cognitiveservices account project connection create` with a `connection.json` of `{"properties": {"category": "CognitiveSearch", "target": "https://<search>.search.windows.net", "authType": "AAD"}}` [S17]. ARM REST: `PUT .../accounts/{account}/projects/{project}/connections/{name}?api-version=2025-06-01` with the same body [S17]. Azure Developer CLI: `azd ai connection create <name> --kind cognitive-search --target <endpoint> --auth-type project-managed-identity` [S17]. Bicep: connection templates in the foundry-samples repository [S17, S39].
- REST tool definitions need the connection ID `/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.CognitiveServices/accounts/{account}/projects/{project}/connections/{connection}` [S17].
- The `az ml` CLI and `azure-ai-ml` SDK don't work for new Foundry projects [S17].
- Who can create connections: **Foundry User**, **Foundry Owner** or Azure **Contributor** per S39; **Foundry Project Manager** for MCP-authentication connections per S21 (OPEN QUESTIONS). Lab design, derived from S21 and S39: provisioning pre-creates the connection.

### 8.2 Identity used at query time and roles

- The search service must accept Microsoft Entra tokens: API access control **Both** (recommended by S17) or **Role-based access control**; with the default **API Key** setting, every role-based request is denied [S17, S23, S34].
- Conflicting role guidance for the keyless tool connection (OPEN QUESTIONS):
  - S17 prerequisites and setup: the Foundry account's system-assigned identity gets **Search Index Data Contributor** and **Search Service Contributor** on the search service.
  - S17 troubleshooting: the same two roles on the Foundry project's managed identity.
  - S19: the Foundry project managed identity needs **Search Index Data Reader** to read an index, and **Search Service Contributor** only to create one.
  - S21 (Foundry IQ): the project managed identity gets **Search Index Data Reader** (plus Contributor only to write).
- A private virtual network requires the project managed identity (keyless); key-based connections fail there [S17].
- The tool doesn't use the Agent ID (section 3) [S38].

### 8.3 Adding the tool

- The S17 page recommends adding the tool through a toolbox; the tool is also supported as a direct tool [S17, S48].
- A toolbox needs **Foundry User** on the project for the developer and, for a prompt agent, for the agent identity that calls tools [S18]. A toolbox holds at most one unnamed tool per type; every tool should have a description [S18].
- Attaching a toolbox replaces the agent's individual tools [S57]; for voice-based agents individual tools and a toolbox can't coexist [S19]. Toolbox integration in prompt agents through the VS Code toolkit is preview and off by default [S57].
- Direct tool through the SDK: `AzureAISearchTool` with `AISearchIndexResource(project_connection_id, index_name, query_type)` in a `PromptAgentDefinition` saved with `agents.create_version` [S17].
- Tool JSON shape: `{"type": "azure_ai_search", "azure_ai_search": {"indexes": [{"project_connection_id": "<id>", "index_name": "<index>", "query_type": "semantic", "top_k": 5}]}}` [S17]. Agent REST API: `POST {project_endpoint}/agents?api-version=v1` with a `definition` holding `model`, `instructions`, `tools` and `kind` `prompt` [S21].
- Verify: ask a question answered by one indexed document, confirm `[message_idx:search_idx†source]` citations and `url_citation` annotations with valid URLs, and check the cited content against the index [S17]. Open the conversation in **Traces** to see the tool-call span, arguments, result, status and duration [S19].

### 8.4 Foundry IQ knowledge bases

- A knowledge base references knowledge sources and uses agentic retrieval; Azure AI Search provides the indexing and retrieval [S20].
- Portals give preview-only access to agentic retrieval features [S20]. The agent connection is a `RemoteTool` connection (preview) with `ProjectManagedIdentity`, audience `https://search.azure.com/`, targeting `{search}/knowledgebases/{kb}/mcp?api-version=2026-08-01-preview`; the agent's MCP tool exposes only `knowledge_base_retrieve` [S21].
- Roles: project managed identity **Search Index Data Reader**; **Foundry Project Manager** to create the connection; the search identity needs **Cognitive Services User** on the Foundry resource only if the knowledge base uses an LLM [S21].
- An existing index joins through a search index knowledge source (`kind` `searchIndex`, `searchIndexName`, optional `sourceDataFields`, `searchFields`); `semanticConfigurationName` is optional from `2026-05-01-preview` and required in `2026-04-01`; the index must be on the same search service [S22]. Retrieve requests ignore the index's scoring profiles [S22].
- Citation URLs: blob knowledge sources return the original document URL, while search index knowledge sources fall back to the knowledge base's MCP endpoint [S21].
- The Azure portal knowledge base flow supports only `gpt-4o`, `gpt-4o-mini`, `gpt-5`, `gpt-5-mini`, `gpt-5-nano` for query planning [S49]; the `minimal` reasoning effort bypasses LLM query planning [S27].
- Lab design, derived from S20, S21 and S49: Foundry IQ is not the recommended path for task 1.2, because it is preview on the agent side and its search index citations don't link to the source record, which is the lesson of the task. Keep it as an optional reading or a later extension.

## 9. Keeping the new incidents out of the index and proving it

- The blob indexer only reads the blobs of its container (or virtual folder) [S04]. Lab design, derived from S04 and R1: the two new incidents are loaded into Dataverse after the export, so they never exist in Blob and need no exclusion rule.
- Guards if other files ever share the container: a virtual folder in the data source `query`; `indexedFileNameExtensions` or `excludedFileNameExtensions` (exclusion wins when both list an extension); blob metadata `AzureSearch_Skip` = `true` skips a blob entirely [S04].
- Change detection picks up new or changed blobs on the next run [S35, S56]. Lab design, derived from S35: leave the indexer unscheduled and never write to the export container after provisioning, so a rerun can't add documents.
- Removal: deleting a blob removes its document only with a deletion detection (soft delete) policy [S04]; reset and run don't remove orphans [S35]; a line removed from a file parsed into many documents stays in the index [S03].
- Proof: index `$count` equals the manifest total [S26]; a Search explorer filter on the two incident numbers (`"filter": "sourceId eq '<incident number>'"`, `"count": true`) returns 0 (filters need a filterable field) [S36].
- Labelled content: documents with sensitivity labels might fail to index [S53]; label-aware indexing is preview [S51]. Whether the labelled customer document [R1] is exported is a Purview design decision (OPEN QUESTIONS).

## 10. Roles: view versus manage

| Role | View | Manage (create, change, delete, approve) | Source |
| - | - | - | - |
| Owner, Contributor (Azure) | Service in the portal, properties, metrics, object list | Service settings, keys, network, authentication options; can run **Import data** (the service writes the data); can't create search objects, load or query through roles | S23 |
| Reader (Azure) | Service, metrics, object definitions | None; can't view keys, load or query | S23 |
| Search Service Contributor | Service in the portal, object list, quotas | Create, run and manage indexes, indexers, data sources, skillsets, knowledge bases; read admin keys; can't load documents or query through roles | S23 |
| Search Index Data Contributor | Not the service page on its own | Load documents, query, retrieve from knowledge bases | S23 |
| Search Index Data Reader | Not the service page on its own | Query and retrieve only | S23 |
| Storage Blob Data Reader plus Reader | Blobs in the portal with Microsoft Entra authorization | None | S43 |
| Cognitive Services OpenAI User (search identity) | Not applicable | Embedding calls from the skill and vectorizer | S12, S14 |
| Foundry User | Foundry project | Create and update toolboxes; add connections (per S39) | S18, S19, S39 |
| Foundry Project Manager | Foundry project | Create MCP-authentication project connections (per S21); assign the Foundry User role | S21, S42 |

Page-level exceptions:

| Page or task | Roles that can view | Roles that can manage | Source |
| - | - | - | - |
| Search explorer queries | Search Index Data Reader or Contributor (plus a control-plane role to open the service page) | Not applicable | S23, S36 |
| Index-scoped data roles | Not applicable | Only through CLI, PowerShell or REST; indexers ignore per-index scope | S23 |
| Enable role-based access (API access control) | Not applicable | Owner, User Access Administrator, or a custom role with `Microsoft.Authorization/roleAssignments/write` | S34 |
| Disable API keys | Not applicable | Owner or Contributor | S34 |
| Semantic ranker billing plan | Not applicable | Owner or Contributor | S28 |
| Create the search identity | Not applicable | Owner or User Access Administrator; role assignments need Owner, User Access Administrator, Role Based Access Control Administrator or `roleAssignments/write` | S24 |

- Least-privilege role set to do and verify task 1.2: **Search Service Contributor** plus **Search Index Data Reader** on the search service, **Reader** plus **Storage Blob Data Reader** on the storage account, **Foundry User** on the project [S18, S23, S43].
- **Search Service Contributor** can read admin keys [S23]; with API keys disabled (**Role-based access control** only), the service refuses data requests that carry a key [S34].
- A user with **Search Service Contributor** can create indexers that write to any index on the service [S23]; with one service per participant this stays inside the participant's environment [R1].

## 11. Licensing and pricing

No per-user license is involved; Azure AI Search, embeddings and Blob storage are consumption billing [S29, S30].

| Capability | Default (free plan) | Paid plan | Source |
| - | - | - | - |
| Semantic ranker | First 1,000 requests per month free; after that, requests return a billing error | Standard plan (Basic tier or higher): pay as you go after the free allowance | S28, S30 |
| Agentic retrieval (Foundry IQ only) | First 50 million tokens per month free | Standard plan per million tokens | S30, S51 |
| Embedding skill and vectorizer | Not applicable | Billed at the Azure OpenAI rate of the model provider | S12, S14 |

Azure Retail Prices API results, retrieved 2026-11-06 (USD, retail, `type` Consumption) [S29]:

| Region | serviceName | productName | skuName | meterName | Unit | Price | Effective |
| - | - | - | - | - | - | - | - |
| eastus, eastus2, swedencentral | Azure Cognitive Search | Azure AI Search | Basic | Basic Unit | 1 Hour | 0.101 | 2016-08-01 (east), 2022-04-01 (swedencentral) |
| eastus, eastus2, swedencentral | Azure Cognitive Search | Azure AI Search | Semantic Ranker | Semantic Ranker queries | 1K | 1.00 | 2023-11-15 (east), 2025-02-01 (swedencentral) |
| eastus, eastus2 | Azure Cognitive Search | Azure AI Search | Semantic Ranker | Semantic Ranker Overage Queries | 1K | 2.00 | 2021 and 2022 (legacy meter still listed) |
| eastus, eastus2 | Azure Cognitive Search | Azure AI Search | Semantic Ranker | Semantic Ranker Unit | 1/Day | 16.12 | 2021 and 2022 (legacy meter still listed) |
| eastus, eastus2, swedencentral | Azure Cognitive Search | Azure AI Search | Free | Free queries | 1K | 0.00 | 2026-01-01 |
| swedencentral | Azure Cognitive Search | Azure AI Search | Agentic Retrieval Low, Medium, Minimum Reasoning | Agentic Retrieval ... Reasoning Tokens | 1K | 0.000022 | 2025-07-01 to 2026-11-01 |
| eastus, eastus2, swedencentral | Foundry Models | Azure OpenAI | text-embedding-3-small-glbl | text-embedding-3-small-glbl Tokens | 1K | 0.00002 | 2024-06-01 |
| eastus, eastus2 | Foundry Models | Azure OpenAI | text-embedding-3-small-regional | text-embedding-3-small-regional Tokens | 1K | 0.000022 | 2025-09-01 |
| swedencentral | Foundry Models | Azure OpenAI | text-embedding-3-small-regional | text-embedding-3-small-regional Tokens | 1K | 0.000025 | 2025-09-01 |
| eastus | Storage | General Block Blob v2 | Hot LRS | Hot LRS Data Stored (first tier) | 1 GB/Month | 0.0208 | 2017-02-03 |
| eastus2, swedencentral | Storage | General Block Blob v2 | Hot LRS | Hot LRS Data Stored (first tier) | 1 GB/Month | 0.0184 | 2017-02-03, 2021-06-08 |
| eastus, eastus2, swedencentral | Storage | General Block Blob v2 | Hot LRS | Hot LRS Write Operations | 10K | 0.05 | 2016 to 2021 |
| eastus, eastus2, swedencentral | Storage | General Block Blob v2 | Hot LRS | Hot Read Operations | 10K | 0.004 | 2016 to 2021 |
| eastus, eastus2, swedencentral | Storage | General Block Blob v2 | Hot LRS | LRS List and Create Container Operations | 10K | 0.05 | 2016 to 2021 |

API filters used [S29]: `serviceName eq 'Azure Cognitive Search' and (armRegionName eq 'eastus' or armRegionName eq 'eastus2' or armRegionName eq 'swedencentral') and (skuName eq 'Basic' or skuName eq 'Semantic Ranker' or skuName eq 'Free')`; `contains(serviceName, 'Search') and armRegionName eq 'swedencentral'`; `contains(meterName, 'embedding-3-small') and (armRegionName eq 'eastus' or armRegionName eq 'eastus2' or armRegionName eq 'swedencentral' or armRegionName eq 'Global')`; `serviceName eq 'Storage' and productName eq 'General Block Blob v2' and skuName eq 'Hot LRS' and (armRegionName eq 'eastus' or armRegionName eq 'eastus2' or armRegionName eq 'swedencentral')`.

- Basic, 1 replica and 1 partition (1 search unit): $0.101 per hour, $73.73 for 730 hours; billing is per search unit per hour [S29, S27].
- Embedding cost per full indexing run: about $0.014 at the assumption in section 5.5 [S29].
- Blob storage for about 700 small JSON files is under one cent per month; 700 write operations cost about $0.0035 (Hot LRS write $0.05 per 10,000) [S29].
- Semantic ranker: $1 per 1,000 requests after the first 1,000 free per month [S29, S30].
- Agents playground evaluations are on by default and are billed as consumption [S50].

## 12. LAB FEASIBILITY (25 participants per workshop plus 2 spares, one environment per participant in its own Microsoft Entra tenant)

### 12.1 Constraints that drive the design

- Region: regions with the high-demand footnote can't create new search services; on 2026-11-06 that includes East US 2 and Sweden Central, not East US [S32]. The region must also offer semantic ranker [S32, S33]. Integrated vectorization doesn't require search and the embedding model in the same region, but the same region is recommended [S54].
- Service quota: up to 16 Basic services per subscription per region [S27]; one per participant subscription is well inside [R1].
- Embedding quota is scoped to the subscription, never the tenant; Tier 1 gives 1,000,000 TPM for text-embedding-3-small Global Standard [S31]. Each participant tenant needs its subscription's tier checked [S31, R1].
- Managed identity role changes can take several hours to take effect, because managed identity tokens are cached for about 24 hours [S23, S40]. All identity roles must be in place at provisioning, before the identity first calls storage or the model.
- Data plane role-based access is off by default (API keys only) [S34]; role assignments for users on the data plane can take five to ten minutes after enabling roles [S34].
- Indexer timing isn't predictable and multitenant processing can be delayed [S35, S56]; the 15-minute budget [R2] depends on the indexer finishing within a few minutes (pilot measurement).
- The portal index count can lag [S53]; validation should use `$count` [S26].
- Semantic ranker free plan: 1,000 requests per month, then a billing error [S28, S30]. The tool's default query type is `vector_semantic_hybrid` [S17], and semantic ranker charges apply to `queryType=semantic` requests with non-empty search text [S55]; how many tool calls count as semantic ranker requests is an open question.
- The import wizard needs public network access on every resource it touches [S08, S09].
- The Azure AI Search tool targets one index and needs the same tenant [S17]; each participant's search service, Foundry project and agent are in that participant's tenant [R1].
- Attaching a toolbox replaces the agent's individual tools [S57], and the agent carries MCP read and write tool connections [R1].

### 12.2 Recommended role set

- Participants: **Search Service Contributor** and **Search Index Data Reader** on their search service; **Reader** and **Storage Blob Data Reader** on the export storage account; **Foundry User** on their project. No tenant administrator role and no Azure role that can assign roles [S18, S23, S43, R1].
- The one write role the task needs: **Search Service Contributor**, because it creates and runs the index, data source, skillset and indexer; the indexer then writes documents with the service's permissions [S23, S35].
- Service identities (assigned by provisioning): search identity **Storage Blob Data Reader** on the storage account [S05]; search identity **Cognitive Services OpenAI User** on the Foundry resource [S12, S14]; Foundry project managed identity **Search Index Data Reader** on the search service, plus the account identity and **Search Service Contributor** only if the pilot shows the tool needs them [S17, S19, S21].
- Provisioning identity: Owner or User Access Administrator for role assignments [S23, S24]; **Foundry Project Manager** or **Foundry User** for the project connection [S21, S39].
- Never hand out: Owner or User Access Administrator, because participants could grant identities or themselves broader access [S23, S24]; **Foundry Project Manager** to the search identity (only the wizard's **Microsoft Foundry** kind needs it) [S08, S42].

### 12.3 Task classification

| Task | Mode | Role needed | Why | Source |
| - | - | - | - | - |
| 1.2 step 1: review exported content and choose fields | Hands-on, read-only | Reader plus Storage Blob Data Reader (or a VM copy) | Reads blobs in the participant's own account | S43 |
| 1.2 step 2: create the index with citation fields | Hands-on, write | Search Service Contributor | Object on the participant's own service | S23 |
| 1.2 step 3: create data source, skillset and indexer; confirm count | Hands-on, write | Search Service Contributor plus Search Index Data Reader | Own service; the indexer writes with service permissions | S23, S26 |
| 1.2 step 4: add the index as a tool on the agent | Hands-on, write | Foundry User | Own project and agent | S18, S39 |
| 1.2 step 5: first grounded query | Hands-on, read-only | Foundry User | Own agent | S17 |
| Project connection to the search service | Hands-on, write by provisioning (pre-seeded) | Foundry Project Manager or Foundry User (conflict) | Role guidance conflicts; saves time | S21, S39 |
| Identity role assignments | Hands-on, write by provisioning (pre-seeded) | Owner or User Access Administrator | Participants hold no role-assignment rights | S24, R1 |
| Foundry IQ knowledge base over the same index | Screenshots only (optional reading) | Foundry Project Manager, search roles | Preview on the agent side; citations don't link to the record | S20, S21 |

### 12.4 Pre-seeding checklist

1. Seven or more days before: confirm the region has no high-demand footnote and offers semantic ranker; confirm each participant subscription's quota tier for text-embedding-3-small Global Standard; pin REST `2026-04-01` and template API `2026-11-01` [S31, S32, S41, S45].
1. Template: search service `sku` `basic`, `replicaCount` 1, `partitionCount` 1, `identity` `SystemAssigned`, `disableLocalAuth` true (or `authOptions` `aadOrApiKey`), `semanticSearch` `free` or `standard`, `publicNetworkAccess` `Enabled` [S34, S41]; storage account Standard general-purpose v2, hot tier, container for the export [S04].
1. Role assignments in the same deployment: the four service-identity assignments and the participant roles in section 12.2 [S05, S12, S19, S23, S43].
1. Post-deployment script: export one JSON per document plus a manifest stored outside the indexed container, before the two new incidents are loaded [S04, R1]; create the Foundry project connection (`CognitiveSearch`, `AAD`) [S17].
1. Readiness check (lab design, derived from S05, S12, S35 and S40): run a canary indexer over a one-document folder into a temporary index to prove the search identity can read storage and call the embedding deployment, then delete the canary objects; compare the number of exported blobs with the manifest; verify the project connection exists [S17].
1. Event day: participants build the index, data source, skillset and indexer, verify the count, add the tool and run the first query [R2].

### 12.5 Data latency

| Signal or change | Documented latency | Source |
| - | - | - |
| Enabling data plane roles on the service | Immediate; wait a few seconds before assigning roles | S34 |
| User data plane role assignment | Sometimes five to ten minutes | S34 |
| Managed identity role change | Can take several hours (token cache about 24 hours) | S23, S40 |
| Indexer start after creation | Runs at creation unless disabled; can show idle while queued | S04, S56 |
| Indexer run duration for about 700 documents with an embedding skill | Not documented | none |
| Portal indexer list | Refreshes every few minutes; **Refresh** forces it | S25 |
| Portal index document count | Can lag | S53 |
| Toolbox tools listed after creation | If zero tools, wait 10 seconds and retry | S18 |
| Foundry connection usable after creation | Not documented | none |

### 12.6 Timing and fallbacks

- Start the load script first and add the agent tool while the indexer runs (lab design, derived from S04 and S56).
- Don't rerun the indexer repeatedly; wait at least five minutes between on-demand runs [S53].
- If the indexer is slow or fails: the push API is the documented alternative when strict timing matters [S53]; a fallback loader can read the same exported blobs, embed them and push them, keeping the Blob to AI Search flow (lab design, derived from S53 and R1). The `/embeddings` API accepts up to 2,048 inputs and 300,000 tokens per request [S31].
- If semantic requests hit the free allowance: switch the tool to `vector_simple_hybrid` or move the service to the standard plan [S17, S28].
- If the portal tool path differs: use the VS Code Agent Builder path [S57] or the scripted agent version [S17, S21].
- If scripts can't run: the **Import data** **Keyword search** path, with the tool on `semantic` or `simple` [S09, S17].
- Validation (acceptance criteria 4 and 5 [R1]): `$count` equals the manifest [S26]; scripted questions return `url_citation` annotations whose URLs match the expected records [S17].

## 13. SCREENSHOT SOURCES

All URLs below returned HTTP 200 on 2026-11-06; relative media paths were resolved against each page URL.

- https://learn.microsoft.com/azure/search/media/search-import-data-portal/import-data-button.png : **Import data** on the search service command bar [S01]
- https://learn.microsoft.com/azure/search/media/search-get-started-portal-images/select-data-source.png : data source choice in the wizard [S09]
- https://learn.microsoft.com/azure/search/media/search-get-started-portal/keyword-search-tile.png : **Keyword search** tile [S09]
- https://learn.microsoft.com/azure/search/media/search-get-started-portal/connect-to-your-data.png : **Connect to your data** with parsing mode and managed identity [S09]
- https://learn.microsoft.com/azure/search/media/search-get-started-portal/configure-index.gif : setting field attributes with **Configure field** [S09]
- https://learn.microsoft.com/azure/search/media/search-get-started-portal/review-and-create.png : review page with object prefix [S09]
- https://learn.microsoft.com/azure/search/media/search-get-started-portal/indexers-status.png : indexer list with status and document count [S09]
- https://learn.microsoft.com/azure/search/media/search-get-started-portal/indexes-list.png : index list [S09]
- https://learn.microsoft.com/azure/search/media/search-get-started-portal/index-schema-definition.png : index **Fields** tab [S09]
- https://learn.microsoft.com/azure/search/media/search-get-started-portal-import-vectors/wizard-scenarios-rag.png : **RAG** tile [S08]
- https://learn.microsoft.com/azure/search/media/search-get-started-portal-import-vectors/data-source-blob.png : RAG data source page with deletion tracking and managed identity [S08]
- https://learn.microsoft.com/azure/search/media/search-get-started-portal-import-vectors/vectorize-text-aoai.png : **Vectorize your text** with Azure OpenAI [S08]
- https://learn.microsoft.com/azure/search/media/search-get-started-portal-import-vectors/vectorize-text-foundry.png : **Vectorize your text** with Microsoft Foundry [S08]
- https://learn.microsoft.com/azure/search/media/search-get-started-portal-import-vectors/review-create.png : RAG review and create [S08]
- https://learn.microsoft.com/azure/search/media/search-get-started-portal-import-vectors/query-options.png : Search explorer **Query options** [S08]
- https://learn.microsoft.com/azure/search/media/search-get-started-portal-import-vectors/select-json-view.png : Search explorer **JSON view** [S08]
- https://learn.microsoft.com/azure/search/media/search-monitor-indexers/indexers-list.png : indexer statuses [S25]
- https://learn.microsoft.com/azure/search/media/search-monitor-indexers/indexer-summary.png : indexer summary and execution history [S25]
- https://learn.microsoft.com/azure/search/media/search-monitor-indexers/indexer-execution.png : execution details [S25]
- https://learn.microsoft.com/azure/search/media/search-how-to-manage-index/indexes-page.png : indexes page with **Document count** column [S37]
- https://learn.microsoft.com/azure/search/media/search-how-to-manage-index/index-statistics.png : index statistics [S37]
- https://learn.microsoft.com/azure/search/media/search-how-to-manage-index/edit-json-button.png : **Edit JSON** [S37]
- https://learn.microsoft.com/azure/search/media/search-explorer/search-explorer-cmd.png : **Search explorer** command [S36]
- https://learn.microsoft.com/azure/search/media/search-explorer/search-explorer-example-count.png : count query result [S36]
- https://learn.microsoft.com/azure/search/media/search-managed-identities/turn-on-system-assigned-identity.png : turning on the system-assigned identity [S24]
- https://learn.microsoft.com/azure/search/media/search-security-rbac/search-security-enable-roles.png : Keys page authentication options [S34]
- https://learn.microsoft.com/azure/search/media/search-security-rbac/portal-access-control.png : **Access control (IAM)** on the search service [S23]
- https://learn.microsoft.com/azure/search/media/semantic-search-overview/add-semantic-config.png : **Add semantic configuration** [S33]
- https://learn.microsoft.com/azure/search/media/semantic-search-overview/create-semantic-config.png : **New semantic configuration** [S33]
- https://learn.microsoft.com/azure/search/media/semantic-how-to-enable-disable/semantic-enable.png : **Premium features** semantic ranker plan [S28]
- https://learn.microsoft.com/azure/search/media/search-what-is-an-index/add-index.png : **Add index** and **Import data** options [S10]
- https://learn.microsoft.com/azure/search/media/search-how-to-create-indexers/portal-indexer-client-2.png : **Add indexer** [S11]
- https://learn.microsoft.com/azure/search/media/search-howto-run-reset-indexers/portal-reset.png : indexer **Reset** command [S35]
- https://learn.microsoft.com/azure/foundry/agents/media/tools/ai-search/connection-endpoint.png : search service endpoint on **Overview** [S17]
- https://learn.microsoft.com/azure/foundry/agents/media/tools/ai-search/azure-portal.png : **Keys** page with **Both** [S17]
- https://learn.microsoft.com/azure/storage/blobs/media/authorize-data-operations-portal/blob-access-portal.png : navigating to blobs [S43]
- https://learn.microsoft.com/azure/storage/blobs/media/authorize-data-operations-portal/auth-method-azure-ad.png : container with **Microsoft Entra user Account** authentication [S43]
- https://learn.microsoft.com/azure/foundry/media/observability/agent-playground-evaluation-metrics.png : agents playground evaluation metrics selector [S50]
- https://learn.microsoft.com/azure/search/media/get-started-portal-agentic-retrieval/create-knowledge-source.png : blob knowledge source form (Foundry IQ option) [S49]
- https://learn.microsoft.com/azure/search/media/get-started-portal-agentic-retrieval/create-knowledge-base.png : knowledge base form (Foundry IQ option) [S49]

None of the pages read (S17, S19, S57) shows the Foundry (new) portal adding **Azure AI Search** as an individual tool to a text prompt agent; capture it live in the pilot.

## 14. OPEN QUESTIONS

1. Keyless identity for the Azure AI Search tool: [S17] prerequisites assign **Search Index Data Contributor** and **Search Service Contributor** to the Foundry account's system-assigned identity, while [S17] troubleshooting names the project managed identity, [S19] says the project identity needs only **Search Index Data Reader** to read, and [S21] says the same for Foundry IQ. Pilot: grant **Search Index Data Reader** to the project identity only, test, then add the account identity and **Search Service Contributor** one at a time.
1. Citation fields: [S17] requires a retrievable URL field and optional title but only its sample names them `title` and `url`; no page says whether other names are detected. Name them exactly `title` and `url` and confirm `url_citation` annotations in the pilot.
1. Which index fields the tool returns to the model (all retrievable fields or only content) is not documented; it drives token use per turn. Inspect the tool result in **Traces** [S19].
1. The Foundry (new) portal path to add Azure AI Search as an individual tool to a text prompt agent is not documented; [S19] documents only the toolbox path for voice-based agents and [S57] documents the VS Code path. The previous build used a **Knowledge** > **Add** path that no page fetched today documents for Foundry (new). Capture the labels in the pilot.
1. Whether attaching a toolbox also replaces a text prompt agent's individual tools in the portal: [S57] says it does in the VS Code toolkit and [S19] says so for voice agents. Avoid toolboxes until proven.
1. [S17] lists a vector field as an index prerequisite even though `simple` and `semantic` query types don't use vectors; whether the portal picker rejects an index without a vector field (the Keyword search fallback) is not documented.
1. Import data wizard: parsing modes offered in the **RAG** scenario are not documented, and the **Keyword search** page shows only **JSON array** [S08, S09]. Confirm whether a single-document **JSON** mode is offered [S02].
1. Wizard pickers: roles a participant needs on the storage account and Foundry resource to see them in the wizard are not documented [S01, S08].
1. Key characters: [S01] says keys with spaces or dashes need **Base-64 Encode Key**, while [S07] and [S52] allow dashes in keys. Test a dashed `id` through REST in the pilot.
1. `base64Encode` parameters: [S06] warns that keys need `useHttpServerUtilityUrlTokenEncode` true, but its own key example sets false. Avoid encoding by using allowed characters.
1. Embedding output path: [S12] maps `/document/embedding/*`, while [S46] and [S47] imply `/document/<targetName>` under the skill context. Test `/document/contentVector` with context `/document` in the pilot.
1. Embedding input limit: [S12] says 8,000 tokens per input, [S16] says the model accepts 8,191. Keep every `content` well under 8,000 and measure the longest document at export.
1. Extracted text limit on Basic: [S27] gives 512,000 characters per source file, while [S52] mentions 64,000 for Basic in a warning description. Irrelevant for small JSON files but unresolved.
1. Indexer duration for about 700 documents with one embedding skill on Basic, with 25 or more services indexing at once in one region, is not documented [S56]. Measure median and worst case in the pilot; the 15-minute budget [R2] depends on it.
1. Whether role assignments made at provisioning, before a managed identity's first token, take effect at once is not documented; [S40] covers changes only. The canary indexer in 12.4 is the check.
1. Semantic ranker free allowance: [S30] says the first 1,000 requests per month are free but not whether this is per service or per subscription; the expected tool query count per participant per workshop is unknown. Decide free versus standard plan after the pilot [S28].
1. `semanticSearch` value `disabled`: [S28] says it is no longer valid from management API `2026-03-01-preview`, while the `2026-11-01` template schema still lists it [S41]. Use `free` or `standard`.
1. Connection creation role: [S39] lists **Foundry User**, **Foundry Owner** or **Contributor**; [S21] requires **Foundry Project Manager** for MCP-authentication connections. Pre-create the connection at provisioning.
1. [S30] says Foundry IQ knowledge bases need a standard agentic retrieval plan, while [S51] says every service starts on the free agentic retrieval plan. Matters only if Foundry IQ is used.
1. Customer documents: one is sensitivity-labelled [R1]; labelled documents might not index [S53] and label-aware indexing is preview [S51]. Decide with the Purview research note whether that document is exported and how its label is represented.
1. Expected document count: 669 from the minimums, 729 if open tickets are exported [R1, R2]; the export manifest decides. The average tokens per document, and whether embedding tokens count toward the 4 million input token allowance [R1], are unknown until export.
1. Region: high-demand footnotes change [S32]. Recheck within seven days of each workshop, together with model availability in the Foundry research note.
1. Agents playground evaluations are on by default and billed [S50]; no API to turn them off at provisioning was found. Decide whether the guide tells participants to unselect the evaluators.
1. Label drift: **Search management** > **Indexers** [S09, S25, S52] versus **Overview** > **Indexers** tab [S35]; **Role-based control** versus **Role-based access control** [S34]; scenario-first [S01] versus data-source-first [S08, S09] wizard order. Confirm the live labels when capturing screenshots.
