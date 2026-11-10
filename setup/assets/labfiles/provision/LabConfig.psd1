# ====
# Lab constants shared by provisioning, the readiness check and the lab tools. One place to change a
# name: every value here is also in setup/README.md (Names and settings) and, where the guide shows
# it, in the BUILD-SPEC. No secrets, ever.
# ====
@{
    LabTitle                  = 'Agentic MSP Support Agent Guided Lab'
    GoldenEnvironmentVersion  = 'v1.0'
    ProjectFolder             = 'agentic-msp-support-agent'

    # ==== MCP server release shipped in the lab files (provision\mcp-server, from setup/Build-LabFilesZip.ps1)
    McpRelease                = '3.0.0'
    McpImageRepository        = 'mcp-server'
    McpRepositoryUrl          = 'https://github.com/CloudLabsAI-Azure/agentic-msp-mcp-server.git'
    McpBaselineRevisionPrefix = 'baseline'
    McpToolsFromRelease       = @('Deploy-McpServer.ps1', 'Invoke-McpTool.ps1', 'Show-McpServerLog.ps1')

    # ==== Foundry
    AgentName                 = 'msp-support-agent'
    ChatDeployment            = 'gpt-5.1'
    EmbeddingDeployment       = 'text-embedding-3-small'
    ReasoningEffort           = 'low'
    SearchConnection          = 'search'
    AppInsightsConnection     = 'appinsights'
    ReadConnection            = 'servicedesk-read'
    WriteConnection           = 'servicedesk-write'
    ConnectionApiVersions     = @('2026-09-01', '2026-09-15-preview')
    McpConnectionMetadataType = 'generic_mcp'
    # The baseline read catalog (SOW Exhibit C) plus the read tools the exercises use. The agent's
    # servicedesk-read tool lists exactly these tools (allowed_tools, no approval); the
    # servicedesk-write tool lists none, so every write tool, and any tool a participant adds to the
    # write endpoint, needs approval. Build-LabFilesZip.ps1 checks both lists against the MCP server
    # release, and the readiness check compares them with the running server's tools/list.
    ReadTools                 = @(
        'get_customer', 'search_customers', 'get_customer_contacts', 'get_customer_document',
        'search_customer_documents', 'search_tickets', 'get_ticket', 'get_open_tickets',
        'get_ticket_history', 'get_ticket_notes', 'search_kb_articles', 'get_kb_article',
        'get_sla_status', 'get_assignment', 'list_technicians', 'get_similar_tickets'
    )
    WriteTools                = @(
        'update_ticket_status', 'update_ticket_priority', 'update_ticket_category', 'link_kb_article',
        'assign_ticket', 'add_internal_note', 'add_public_reply'
    )

    # ==== API Management
    ReadApi                   = 'servicedesk-read'
    WriteApi                  = 'servicedesk-write'
    DiagApi                   = 'servicedesk-diag'
    DiagSubscription          = 'lab-diagnostics'
    GatewayScope              = 'ServiceDesk.Access'
    ApimApiVersion            = '2024-05-01'

    # ==== Search export (BUILD-SPEC 3.7)
    SearchIndex               = 'servicedesk-knowledge'
    ExportContainer           = 'servicedesk-export'
    ExportMetaContainer       = 'servicedesk-export-meta'

    # ==== App registrations created inside the tenant
    SetupAppName              = 'Relecloud Lab Setup'
    GatewayAppName            = 'Relecloud Service Desk MCP Gateway'
    PurviewAppName            = 'Relecloud Service Desk Purview Integration'
    SecretLifetimeDays        = 14
    SetupCertificateDays      = 7
    SetupAppGraphRoles        = @('Application.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All', 'DelegatedPermissionGrant.ReadWrite.All',
                                  'RoleManagement.ReadWrite.Directory', 'User.Read.All', 'Organization.Read.All')
    SetupAppDirectoryRoles    = @('Global Administrator')
    # Read-only Graph permissions of id-prov, kept after provisioning for the readiness check: users and
    # licenses, directory roles, app registrations, consent grants, published sensitivity labels.
    ProvisioningGraphRoles    = @('User.Read.All', 'RoleManagement.Read.Directory', 'Application.Read.All',
                                  'DelegatedPermissionGrant.Read.All', 'InformationProtectionPolicy.Read.All')
    PurviewAppGraphRoles      = @('Content.Process.User', 'ProtectionScopes.Compute.User')
    PurviewAppOptionalRoles   = @('ContentActivity.Write')

    # ==== Microsoft Purview (Security & Compliance PowerShell, app-only)
    Purview = @{
        ModuleVersion        = '3.9.2'
        LabelName            = 'Relecloud-Confidential'
        LabelDisplayName     = 'Relecloud Confidential'
        LabelTooltip         = 'Relecloud customer configuration data. Do not share outside Relecloud Managed Services.'
        LabelPolicyName      = 'Relecloud Service Desk label policy'
        DlpPolicyName        = 'Relecloud Service Desk card numbers'
        DlpRuleName          = 'Block card numbers sent to the agent'
        CollectionPolicyName = 'Relecloud Service Desk AI interactions'
        SeniorRoleGroups     = @('Information Protection Analysts', 'Data Security AI Viewers')
    }

    # ==== Power Platform and Dataverse
    Dataverse = @{
        DisplayNamePrefix  = 'Relecloud Service Desk'
        Currency           = 'USD'
        LanguageCode       = 1033
        AppUniqueName      = 'spk_ServiceDesk'
        AuditRetentionDays = 30
        WaitMinutes        = 60
    }

    # ==== Users created by CloudLabs (setup/scripts/user-creation.json)
    UserWaitMinutes           = 30
    Tier1DisplayName          = 'Tier 1 Technician'
}
