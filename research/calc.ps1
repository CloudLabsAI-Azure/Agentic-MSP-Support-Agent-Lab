# Cross-check helper: the JSON feed behind the official azure.microsoft.com pricing pages / calculator.
# Raw responses are saved next to the research notes, where the cost estimate cites them.
$Global:AzPriceDir = Join-Path $PSScriptRoot 'pricing-raw-swedencentral'

function Get-AzCalc {
    param([Parameter(Mandatory)] [string] $Slug, [string] $OutName)
    foreach ($v in 'v3', 'v2') {
        $u = "https://azure.microsoft.com/api/$v/pricing/$Slug/calculator/?culture=en-us&discount=mosp"
        try {
            $resp = Invoke-WebRequest -Uri $u -Method Get -TimeoutSec 90
            if ($resp.StatusCode -eq 200) {
                if ($OutName) {
                    $path = Join-Path $Global:AzPriceDir ("pricing-raw-calc-$OutName.json")
                    $resp.Content | Set-Content -Path $path -Encoding utf8
                }
                $obj = $resp.Content | ConvertFrom-Json -AsHashtable
                $obj['__url'] = $u
                return $obj
            }
        } catch { }
    }
    throw "No calculator feed found for slug $Slug"
}

# Print offers whose key matches a regex, with prices for the given region slugs
function Show-AzCalc {
    param([Parameter(Mandatory)] $Calc, [string] $KeyRegex = '.', [string[]] $Regions = @('us-east-2', 'us-east', 'global'))
    "source: $($Calc['__url'])"
    foreach ($k in ($Calc['offers'].Keys | Sort-Object)) {
        if ($k -notmatch $KeyRegex) { continue }
        $o = $Calc['offers'][$k]
        if (-not $o.ContainsKey('prices')) { continue }
        foreach ($pk in $o['prices'].Keys) {
            $p = $o['prices'][$pk]
            $vals = @()
            foreach ($r in $Regions) {
                if ($p -is [System.Collections.IDictionary] -and $p.ContainsKey($r)) { $vals += "$r=$($p[$r]['value'])" }
            }
            if ($p -is [System.Collections.IDictionary] -and $p.ContainsKey('value') -and ($Regions -contains $pk)) { $vals += "value=$($p['value'])" }
            if ($vals.Count -gt 0) { "  $k | $pk | $($vals -join ' ; ')" }
        }
    }
}
