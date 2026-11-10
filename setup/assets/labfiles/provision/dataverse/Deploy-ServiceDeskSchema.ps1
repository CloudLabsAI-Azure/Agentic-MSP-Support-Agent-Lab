#Requires -Version 7.0
<#
.SYNOPSIS
    Builds the Relecloud Service Desk schema and model-driven app in a Dataverse environment
    from schema.json, through the Dataverse Web API metadata endpoints.

.DESCRIPTION
    Idempotent: every component is looked up first and created only if missing, so the script
    can be re-run after a partial failure. Order: publisher, solution, global choices, tables,
    columns, lookups, alternate keys (waits until Active), views, main forms, sitemap and app,
    then publish.

    A re-run also brings existing components in line with schema.json: global choices gain,
    relabel and lose options (lab version 3 merged the seven technician teams into four),
    existing views get the current columns and filters, and the sections listed under
    "extendForms" are added to, or refreshed in, an existing main form without replacing the
    rest of it (the account form keeps its timeline, where the labeled document lives).

    Two uses:
      1. Build once in a reference developer environment, check the app, then export the
         unmanaged solution 'RelecloudServiceDesk' to assets/solutions/ so team deployments can
         import it (faster and fully deterministic).
      2. Fallback per team when no exported solution is present (Provision-ServiceDesk.ps1).

    Requires an Azure CLI session ('az login') as a System Administrator of the environment.

.EXAMPLE
    .\Deploy-ServiceDeskSchema.ps1 -OrgUrl https://mspdesk123456.crm4.dynamics.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OrgUrl,
    [string]$SchemaPath = (Join-Path $PSScriptRoot 'schema.json')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'MspLab.Common.psm1') -Force

$schema = Get-Content $SchemaPath -Raw | ConvertFrom-Json -AsHashtable
$solution = $schema.solution.uniquename
$OrgUrl = $OrgUrl.TrimEnd('/')

function DV {
    param([string]$Method, [string]$Path, $Body = $null, [hashtable]$Headers = @{}, [switch]$InSolution, [switch]$AllowNotFound)
    $sol = if ($InSolution) { $solution } else { '' }
    return Invoke-Dataverse -OrgUrl $OrgUrl -Method $Method -Path $Path -Body $Body -Headers $Headers -Solution $sol -AllowNotFound:$AllowNotFound
}

function Required([bool]$isRequired) {
    return @{ Value = $(if ($isRequired) { 'ApplicationRequired' } else { 'None' }); CanBeChanged = $true
              ManagedPropertyLogicalName = 'canmodifyrequirementlevelsettings' }
}

function AuditFlag([bool]$on) {
    return @{ Value = $on; CanBeChanged = $true; ManagedPropertyLogicalName = 'canmodifyauditsettings' }
}

# ================================================================== publisher and solution
Write-Step 'Publisher and solution'
$pub = $schema.publisher
$found = (DV GET "publishers?`$select=publisherid&`$filter=uniquename eq '$($pub.uniquename)'").Body.value
if ($found) { $publisherId = $found[0].publisherid }
else {
    $r = DV POST 'publishers' @{ uniquename = $pub.uniquename; friendlyname = $pub.friendlyname
        customizationprefix = $pub.customizationprefix; customizationoptionvalueprefix = $pub.customizationoptionvalueprefix
        description = 'Publisher for the Agentic MSP Support Agent lab' }
    $publisherId = Get-EntityIdFromHeader $r.Headers
}
$found = (DV GET "solutions?`$select=solutionid&`$filter=uniquename eq '$solution'").Body.value
if (-not $found) {
    DV POST 'solutions' @{ uniquename = $solution; friendlyname = $schema.solution.friendlyname; version = $schema.solution.version
        'publisherid@odata.bind' = "/publishers($publisherId)" } | Out-Null
}

# ================================================================== global choices
Write-Step 'Global choices'
$choiceIds = @{}
foreach ($choice in $schema.globalChoices) {
    $existing = DV GET "GlobalOptionSetDefinitions(Name='$($choice.name)')" -AllowNotFound
    if (-not $existing) {
        DV POST 'GlobalOptionSetDefinitions' @{
            '@odata.type' = 'Microsoft.Dynamics.CRM.OptionSetMetadata'
            Name = $choice.name; DisplayName = (New-DvLabel $choice.displayName); OptionSetType = 'Picklist'; IsGlobal = $true
            Options = @($choice.options | ForEach-Object { @{ Value = $_.value; Label = (New-DvLabel $_.label) } })
        } -InSolution | Out-Null
        $existing = DV GET "GlobalOptionSetDefinitions(Name='$($choice.name)')"
    }
    else {
        # Bring an existing choice in line with schema.json: add missing options, fix labels and
        # remove options schema.json no longer lists.
        $metadataId = $existing.Body.MetadataId
        $current = @{}
        foreach ($o in @((DV GET "GlobalOptionSetDefinitions($metadataId)/Microsoft.Dynamics.CRM.OptionSetMetadata").Body.Options)) {
            if ($o) { $current[[int]$o.Value] = "$($o.Label.UserLocalizedLabel.Label)" }
        }
        $wanted = @{}
        $wantedOrder = @()
        foreach ($o in $choice.options) { $wanted[[int]$o.value] = $o.label; $wantedOrder += [int]$o.value }
        foreach ($value in $wantedOrder) {
            if (-not $current.ContainsKey($value)) {
                DV POST 'InsertOptionValue' @{ OptionSetName = $choice.name; Value = $value; Label = (New-DvLabel $wanted[$value])
                    SolutionUniqueName = $solution } | Out-Null
                Write-Step "  $($choice.name): added $value $($wanted[$value])"
            }
            elseif ($current[$value] -ne $wanted[$value]) {
                DV POST 'UpdateOptionValue' @{ OptionSetName = $choice.name; Value = $value; Label = (New-DvLabel $wanted[$value])
                    MergeLabels = $true; SolutionUniqueName = $solution } | Out-Null
                Write-Step "  $($choice.name): relabeled $value as $($wanted[$value])"
            }
        }
        foreach ($value in @($current.Keys | Where-Object { -not $wanted.ContainsKey($_) })) {
            DV POST 'DeleteOptionValue' @{ OptionSetName = $choice.name; Value = $value; SolutionUniqueName = $solution } | Out-Null
            Write-Step "  $($choice.name): removed $value $($current[$value])"
        }
    }
    $choiceIds[$choice.name] = $existing.Body.MetadataId
    Write-Step "  $($choice.name)"
}

# ================================================================== columns
function New-ColumnBody([hashtable]$col) {
    $common = @{ SchemaName = $col.schemaName; DisplayName = (New-DvLabel $col.displayName)
                 RequiredLevel = (Required ([bool]$col.required)); IsAuditEnabled = (AuditFlag $true) }
    switch ($col.type) {
        'String' {
            $fmt = if ($col.format) { $col.format } else { 'Text' }
            return $common + @{ '@odata.type' = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'; AttributeType = 'String'
                AttributeTypeName = @{ Value = 'StringType' }; MaxLength = $col.maxLength; FormatName = @{ Value = $fmt } }
        }
        'Memo' {
            return $common + @{ '@odata.type' = 'Microsoft.Dynamics.CRM.MemoAttributeMetadata'; AttributeType = 'Memo'
                AttributeTypeName = @{ Value = 'MemoType' }; Format = 'TextArea'; MaxLength = $col.maxLength }
        }
        'Integer' {
            return $common + @{ '@odata.type' = 'Microsoft.Dynamics.CRM.IntegerAttributeMetadata'; AttributeType = 'Integer'
                AttributeTypeName = @{ Value = 'IntegerType' }; Format = 'None'; MinValue = $col.min; MaxValue = $col.max }
        }
        'Decimal' {
            return $common + @{ '@odata.type' = 'Microsoft.Dynamics.CRM.DecimalAttributeMetadata'; AttributeType = 'Decimal'
                AttributeTypeName = @{ Value = 'DecimalType' }; Precision = $col.precision; MinValue = $col.min; MaxValue = $col.max }
        }
        'DateTime' {
            return $common + @{ '@odata.type' = 'Microsoft.Dynamics.CRM.DateTimeAttributeMetadata'; AttributeType = 'DateTime'
                AttributeTypeName = @{ Value = 'DateTimeType' }; Format = $col.format; DateTimeBehavior = @{ Value = $col.behavior } }
        }
        'Boolean' {
            return $common + @{ '@odata.type' = 'Microsoft.Dynamics.CRM.BooleanAttributeMetadata'; AttributeType = 'Boolean'
                AttributeTypeName = @{ Value = 'BooleanType' }; DefaultValue = [bool]$col.default
                OptionSet = @{ OptionSetType = 'Boolean'
                    TrueOption = @{ Value = 1; Label = (New-DvLabel $col.trueLabel) }
                    FalseOption = @{ Value = 0; Label = (New-DvLabel $col.falseLabel) } } }
        }
        'Picklist' {
            return $common + @{ '@odata.type' = 'Microsoft.Dynamics.CRM.PicklistAttributeMetadata'; AttributeType = 'Picklist'
                AttributeTypeName = @{ Value = 'PicklistType' }
                'GlobalOptionSet@odata.bind' = "/GlobalOptionSetDefinitions($($choiceIds[$col.globalChoice]))" }
        }
        default { throw "Unsupported column type $($col.type)" }
    }
}

function Add-Columns([string]$table, $columns) {
    foreach ($col in $columns) {
        $logical = $col.schemaName.ToLower()
        $exists = DV GET "EntityDefinitions(LogicalName='$table')/Attributes(LogicalName='$logical')?`$select=MetadataId" -AllowNotFound
        if ($exists) { continue }
        Invoke-WithRetry -What "column $table.$logical" -DelaySeconds 10 -Action {
            DV POST "EntityDefinitions(LogicalName='$table')/Attributes" (New-ColumnBody $col) -InSolution | Out-Null
        }
        Write-Step "  $table.$logical"
    }
}

# ================================================================== tables
Write-Step 'Tables'
foreach ($t in $schema.tables) {
    $existing = DV GET "EntityDefinitions(LogicalName='$($t.logicalName)')?`$select=MetadataId" -AllowNotFound
    if (-not $existing) {
        $primary = $t.primaryName
        Invoke-WithRetry -What "table $($t.logicalName)" -DelaySeconds 20 -Action {
            DV POST 'EntityDefinitions' @{
                '@odata.type' = 'Microsoft.Dynamics.CRM.EntityMetadata'
                SchemaName = $t.schemaName; DisplayName = (New-DvLabel $t.displayName)
                DisplayCollectionName = (New-DvLabel $t.pluralName); Description = (New-DvLabel $t.description)
                OwnershipType = $t.ownership; IsActivity = $false; HasActivities = $false; HasNotes = $false
                IsAuditEnabled = (AuditFlag ([bool]$t.audit))
                Attributes = @(@{
                    '@odata.type' = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'; AttributeType = 'String'
                    AttributeTypeName = @{ Value = 'StringType' }; SchemaName = $primary.schemaName; IsPrimaryName = $true
                    MaxLength = $primary.maxLength; FormatName = @{ Value = 'Text' }; RequiredLevel = (Required $true)
                    DisplayName = (New-DvLabel $primary.displayName) })
            } -InSolution | Out-Null
        }
        Write-Step "  created $($t.logicalName)"
    }
    Add-Columns $t.logicalName $t.columns
}
foreach ($t in $schema.extendTables) { Add-Columns $t.logicalName $t.columns }

# ================================================================== lookups (one-to-many relationships)
Write-Step 'Lookups'
foreach ($t in $schema.tables) {
    foreach ($lk in @($t.lookups)) {
        if (-not $lk) { continue }
        $logical = $lk.schemaName.ToLower()
        $exists = DV GET "EntityDefinitions(LogicalName='$($t.logicalName)')/Attributes(LogicalName='$logical')?`$select=MetadataId" -AllowNotFound
        if ($exists) { continue }
        $parental = $lk.cascadeDelete -eq 'Cascade'
        $cascade = if ($parental) {
            @{ Assign = 'Cascade'; Delete = 'Cascade'; Merge = 'Cascade'; Reparent = 'Cascade'; Share = 'Cascade'; Unshare = 'Cascade' }
        } else {
            @{ Assign = 'NoCascade'; Delete = 'RemoveLink'; Merge = 'NoCascade'; Reparent = 'NoCascade'; Share = 'NoCascade'; Unshare = 'NoCascade' }
        }
        $target = $lk.target
        Invoke-WithRetry -What "lookup $($t.logicalName).$logical" -DelaySeconds 15 -Action {
            DV POST 'RelationshipDefinitions' @{
                '@odata.type' = 'Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata'
                SchemaName = $lk.relationshipSchemaName
                ReferencedEntity = $target; ReferencedAttribute = "$($target)id"; ReferencingEntity = $t.logicalName
                ReferencingEntityNavigationPropertyName = $lk.schemaName
                ReferencedEntityNavigationPropertyName = $lk.relationshipSchemaName
                CascadeConfiguration = $cascade
                Lookup = @{ '@odata.type' = 'Microsoft.Dynamics.CRM.LookupAttributeMetadata'; AttributeType = 'Lookup'
                    AttributeTypeName = @{ Value = 'LookupType' }; SchemaName = $lk.schemaName
                    DisplayName = (New-DvLabel $lk.displayName); RequiredLevel = (Required $false) }
            } -InSolution | Out-Null
        }
        Write-Step "  $($t.logicalName).$logical -> $target"
    }
}

# ================================================================== alternate keys
Write-Step 'Alternate keys'
$allTables = @($schema.tables) + @($schema.extendTables)
foreach ($t in $allTables) {
    foreach ($key in @($t.keys)) {
        if (-not $key) { continue }   # a table without keys (spk_agentaction) gives @($null)
        $keys = (DV GET "EntityDefinitions(LogicalName='$($t.logicalName)')/Keys?`$select=SchemaName,EntityKeyIndexStatus").Body.value
        if (-not ($keys | Where-Object { $_.SchemaName -eq $key.schemaName })) {
            Invoke-WithRetry -What "key $($key.schemaName)" -DelaySeconds 15 -Action {
                DV POST "EntityDefinitions(LogicalName='$($t.logicalName)')/Keys" @{
                    SchemaName = $key.schemaName; DisplayName = (New-DvLabel $key.displayName); KeyAttributes = @($key.columns)
                } -InSolution | Out-Null
            }
            Write-Step "  $($t.logicalName): $($key.schemaName)"
        }
    }
}
$deadline = (Get-Date).AddMinutes(20)
do {
    $pending = @()
    foreach ($t in $allTables) {
        $keys = (DV GET "EntityDefinitions(LogicalName='$($t.logicalName)')/Keys?`$select=SchemaName,EntityKeyIndexStatus").Body.value
        $pending += @($keys | Where-Object { $_.EntityKeyIndexStatus -ne 'Active' } | ForEach-Object { "$($_.SchemaName)=$($_.EntityKeyIndexStatus)" })
    }
    if ($pending.Count) { Write-Step "  waiting for key indexes: $($pending -join ', ')"; Start-Sleep -Seconds 20 }
} while ($pending.Count -and (Get-Date) -lt $deadline)
if ($pending.Count) { throw "Alternate key indexes did not become Active: $($pending -join ', ')" }

# ================================================================== helpers for forms and views
$labels = @{}
foreach ($t in $allTables) {
    if ($t.primaryName) { $labels["$($t.logicalName).$($t.primaryName.schemaName.ToLower())"] = $t.primaryName.displayName }
    foreach ($c in @($t.columns)) { if ($c) { $labels["$($t.logicalName).$($c.schemaName.ToLower())"] = $c.displayName } }
    foreach ($l in @($t.lookups)) { if ($l) { $labels["$($t.logicalName).$($l.schemaName.ToLower())"] = $l.displayName } }
}
$classIds = @{
    String = '{4273EDBD-AC1D-40D3-9FB2-095C621B552D}'; Memo = '{E0DECE4B-6FC8-4A8F-A065-082708572369}'
    Lookup = '{270BD3DB-D9AF-4782-9025-509E298DEC0A}'; Picklist = '{3EF39988-22BB-4F0B-BBBE-64B5A3748AEE}'
    DateTime = '{5B773807-9FB2-42DB-97C3-7A91EFF8ADFF}'; Boolean = '{67FAC785-CD58-4F9F-ABB3-4B7DDC6ED5ED}'
    Decimal = '{C3EFE0C3-0EC6-42BE-8349-CBD9079DFD8E}'; Integer = '{C6D124CA-7EDA-4A60-AEA9-7FB8D318B68F}'
}
function Get-AttributeType([string]$table, [string]$column) {
    $a = (DV GET "EntityDefinitions(LogicalName='$table')/Attributes(LogicalName='$column')?`$select=AttributeType").Body
    return $a.AttributeType
}
function Esc([string]$s) { return [System.Security.SecurityElement]::Escape($s) }
function New-FormSection([string]$table, $section, [string]$name, [string[]]$skip = @()) {
    # One form section with a labeled control per column.
    $rows = foreach ($c in $section.columns) {
        if ($skip -contains $c) { continue }
        $type = Get-AttributeType $table $c
        $classId = $classIds[$type]
        if (-not $classId) { $classId = $classIds.String }
        $label = Esc ($labels["$table.$c"] ?? $c)
        "<row><cell id=`"{$([guid]::NewGuid())}`" showlabel=`"true`"><labels><label description=`"$label`" languagecode=`"1033`" /></labels><control id=`"$c`" classid=`"$classId`" datafieldname=`"$c`" disabled=`"false`" /></cell></row>"
    }
    return "<section name=`"$name`" showlabel=`"true`" showbar=`"false`" id=`"{$([guid]::NewGuid())}`" IsUserDefined=`"0`" columns=`"1`"><labels><label description=`"$(Esc $section.section)`" languagecode=`"1033`" /></labels><rows>$($rows -join '')</rows></section>"
}

# ================================================================== views
Write-Step 'Views'
$viewIds = @()
foreach ($entry in $schema.views.GetEnumerator()) {
    $table = $entry.Key
    $meta = (DV GET "EntityDefinitions(LogicalName='$table')?`$select=ObjectTypeCode,PrimaryIdAttribute,PrimaryNameAttribute").Body
    foreach ($v in $entry.Value) {
        $attributes = ($v.columns | ForEach-Object { "<attribute name=`"$_`" />" }) -join ''
        $order = "<order attribute=`"$($v.order.attribute)`" descending=`"$($v.order.descending.ToString().ToLower())`" />"
        $filter = if ($v.filter) { "<filter type=`"and`">$($v.filter)</filter>" } else { '' }
        $fetch = "<fetch version=`"1.0`" mapping=`"logical`"><entity name=`"$table`"><attribute name=`"$($meta.PrimaryIdAttribute)`" />$attributes$order$filter</entity></fetch>"
        $cells = ($v.columns | ForEach-Object { "<cell name=`"$_`" width=`"150`" />" }) -join ''
        $layout = "<grid name=`"resultset`" object=`"$($meta.ObjectTypeCode)`" jump=`"$($meta.PrimaryNameAttribute)`" select=`"1`" icon=`"1`" preview=`"1`"><row name=`"result`" id=`"$($meta.PrimaryIdAttribute)`">$cells</row></grid>"
        $existing = (DV GET "savedqueries?`$select=savedqueryid&`$filter=returnedtypecode eq '$table' and name eq '$($v.name)'").Body.value
        if ($existing) {
            # Refresh an existing view so a re-run applies new columns and filters.
            $viewIds += $existing[0].savedqueryid
            try { DV PATCH "savedqueries($($existing[0].savedqueryid))" @{ fetchxml = $fetch; layoutxml = $layout } | Out-Null }
            catch { Write-Step "  could not refresh '$($v.name)': $($_.Exception.Message)" }
            continue
        }
        $r = DV POST 'savedqueries' @{ name = $v.name; returnedtypecode = $table; fetchxml = $fetch; layoutxml = $layout; querytype = 0
            description = "Relecloud Service Desk: $($v.name)" } -InSolution
        $id = Get-EntityIdFromHeader $r.Headers
        $viewIds += $id
        if ($v.default) {
            try { DV PATCH "savedqueries($id)" @{ isdefault = $true } | Out-Null } catch { Write-Step "  could not make '$($v.name)' the default view: $($_.Exception.Message)" }
        }
        Write-Step "  $table : $($v.name)"
    }
}

# ================================================================== main forms
Write-Step 'Main forms'
$formIds = @()
foreach ($entry in $schema.forms.GetEnumerator()) {
    $table = $entry.Key
    $form = (DV GET "systemforms?`$select=formid,name&`$filter=objecttypecode eq '$table' and type eq 2").Body.value | Select-Object -First 1
    if (-not $form) { throw "No main form was found for $table." }
    $formIds += $form.formid
    $sections = foreach ($s in $entry.Value) { New-FormSection $table $s (($s.section -replace '\W', '').ToLower()) }
    $formXml = "<form><tabs><tab name=`"general`" id=`"{$([guid]::NewGuid())}`" IsUserDefined=`"0`" showlabel=`"true`" expanded=`"true`"><labels><label description=`"General`" languagecode=`"1033`" /></labels><columns><column width=`"100%`"><sections>$($sections -join '')</sections></column></columns></tab></tabs></form>"
    # The exercises read these columns on the forms, so a form that cannot be updated stops the step.
    try { DV PATCH "systemforms($($form.formid))" @{ formxml = $formXml } | Out-Null }
    catch { throw "Could not update the $table main form: $($_.Exception.Message)" }
    Write-Step "  $table main form updated"
}

# ================================================================== sections added to existing main forms
# Platform tables keep their own forms. Each section listed under extendForms is added to the
# first tab of every main form of the table, or replaced there on a re-run. Columns that the
# form already shows elsewhere are skipped, because a form can't hold the same column twice.
Write-Step 'Extended main forms'
if ($schema.extendForms) {
    foreach ($entry in $schema.extendForms.GetEnumerator()) {
        if ($entry.Key -like '$*') { continue }
        $table = $entry.Key
        $forms = @((DV GET "systemforms?`$select=formid,name,formxml&`$filter=objecttypecode eq '$table' and type eq 2").Body.value)
        if (-not $forms) { throw "No main form was found for $table." }
        foreach ($form in $forms) {
            [xml]$xml = $form.formxml
            foreach ($s in $entry.Value) {
                $name = 'spk_' + (($s.section -replace '\W', '').ToLower())
                foreach ($old in @($xml.SelectNodes("//section[@name='$name']"))) { [void]$old.ParentNode.RemoveChild($old) }
                $present = @($s.columns | Where-Object { $xml.SelectSingleNode("//control[@id='$_']") })
                $target = $xml.SelectSingleNode('/form/tabs/tab[1]/columns/column[1]/sections')
                if (-not $target) { throw "The $table form '$($form.name)' has no section list to extend." }
                $fragment = $xml.CreateDocumentFragment()
                $fragment.InnerXml = New-FormSection $table $s $name $present
                [void]$target.AppendChild($fragment)
            }
            try {
                DV PATCH "systemforms($($form.formid))" @{ formxml = $xml.OuterXml } | Out-Null
                Write-Step "  $table form '$($form.name)' extended"
            }
            catch { Write-Step "  could not extend the $table form '$($form.name)': $($_.Exception.Message)" }
        }
    }
}

# ================================================================== sitemap and app
Write-Step 'Sitemap and model-driven app'
$appUnique = $schema.app.uniqueName
$areas = foreach ($area in $schema.app.sitemap) {
    $groups = foreach ($g in $area.groups) {
        $subs = foreach ($table in $g.subareas) {
            $plural = ($allTables | Where-Object { $_.logicalName -eq $table } | ForEach-Object { $_.pluralName }) | Select-Object -First 1
            if (-not $plural) { $plural = @{ account = 'Accounts'; contact = 'Contacts' }[$table] }
            "<SubArea Id=`"sub_$table`" Entity=`"$table`"><Titles><Title LCID=`"1033`" Title=`"$(Esc $plural)`" /></Titles></SubArea>"
        }
        "<Group Id=`"grp_$(($g.group -replace '\W', '').ToLower())`" IsProfile=`"false`"><Titles><Title LCID=`"1033`" Title=`"$(Esc $g.group)`" /></Titles>$($subs -join '')</Group>"
    }
    "<Area Id=`"area_$(($area.area -replace '\W', '').ToLower())`" ShowGroups=`"true`"><Titles><Title LCID=`"1033`" Title=`"$(Esc $area.area)`" /></Titles>$($groups -join '')</Area>"
}
$siteMapXml = "<SiteMap IntroducedVersion=`"7.0.0.0`">$($areas -join '')</SiteMap>"

$sitemap = (DV GET "sitemaps?`$select=sitemapid&`$filter=sitemapnameunique eq '$appUnique'").Body.value | Select-Object -First 1
if ($sitemap) { $siteMapId = $sitemap.sitemapid; DV PATCH "sitemaps($siteMapId)" @{ sitemapxml = $siteMapXml } | Out-Null }
else {
    $r = DV POST 'sitemaps' @{ sitemapname = $schema.app.displayName; sitemapnameunique = $appUnique; sitemapxml = $siteMapXml
        isappaware = $true; showhome = $true; showpinned = $true; showrecents = $true } -InSolution
    $siteMapId = Get-EntityIdFromHeader $r.Headers
}

$app = (DV GET "appmodules/Microsoft.Dynamics.CRM.RetrieveUnpublishedMultiple()?`$select=appmoduleid,uniquename&`$filter=uniquename eq '$appUnique'").Body.value | Select-Object -First 1
if (-not $app) { $app = (DV GET "appmodules?`$select=appmoduleid,uniquename&`$filter=uniquename eq '$appUnique'").Body.value | Select-Object -First 1 }
if ($app) { $appId = $app.appmoduleid }
else {
    $shortUnique = $appUnique -replace '^spk_', ''
    $r = DV POST 'appmodules' @{ name = $schema.app.displayName; uniquename = $shortUnique; description = $schema.app.description
        webresourceid = '953b9fac-1e5e-e611-80d6-00155ded156f' } -InSolution
    $appId = Get-EntityIdFromHeader $r.Headers
}

$components = @(@{ '@odata.type' = 'Microsoft.Dynamics.CRM.sitemap'; sitemapid = $siteMapId })
# The app designer adds sitemap tables to an app by itself; the API does not. A table that is
# not an app component breaks lookups, Related tabs and quick create inside the app.
$appTables = @($schema.app.sitemap | ForEach-Object { $_.groups } | ForEach-Object { $_.subareas }) | Select-Object -Unique
foreach ($table in $appTables) {
    $entity = (DV GET "entities?`$select=entityid&`$filter=logicalname eq '$table'").Body.value | Select-Object -First 1
    if (-not $entity) { throw "Table $table was not found, so it cannot be added to the app." }
    $components += @{ '@odata.type' = 'Microsoft.Dynamics.CRM.entity'; entityid = $entity.entityid }
}
$components += $viewIds | ForEach-Object { @{ '@odata.type' = 'Microsoft.Dynamics.CRM.savedquery'; savedqueryid = $_ } }
$components += $formIds | ForEach-Object { @{ '@odata.type' = 'Microsoft.Dynamics.CRM.systemform'; formid = $_ } }
try { DV POST 'AddAppComponents' @{ AppId = $appId; Components = $components } | Out-Null }
catch { Write-Step "  AddAppComponents reported: $($_.Exception.Message) (components may already be in the app)" }

# Warnings (for example a table with no form or view selected) are fine; errors are not.
$validation = (DV GET "ValidateApp(AppModuleId=$appId)").Body.AppValidationResponse
$issues = @($validation.ValidationIssueList | Where-Object { $_ })
foreach ($issue in $issues) { Write-Step "  app validation: $($issue.ErrorType) $($issue.Message)" }
$appErrors = @($issues | Where-Object { $_.ErrorType -eq 'Error' })
if ($appErrors) { throw "The Service Desk app failed validation: $(($appErrors | ForEach-Object { $_.Message }) -join '; ')" }

Write-Step 'Publishing'
DV POST 'PublishXml' @{ ParameterXml = "<importexportxml><appmodules><appmodule>$appId</appmodule></appmodules><sitemaps><sitemap>$siteMapId</sitemap></sitemaps></importexportxml>" } | Out-Null
DV POST 'PublishAllXml' @{} | Out-Null
Write-Step "Schema deployed. App id $appId"
[pscustomobject]@{ AppModuleId = $appId; SiteMapId = $siteMapId; Views = $viewIds.Count; Forms = $formIds.Count }
