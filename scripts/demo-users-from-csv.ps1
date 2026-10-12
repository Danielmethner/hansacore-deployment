<#
.SYNOPSIS
  Rebuilds the Forty2 users in a demo-data YAML from an Entra user export (CSV).

.DESCRIPTION
  The CSV needs the columns userPrincipalName, givenName and surname (Entra admin
  centre: Users > Download users). Every person becomes a demo user with their real
  sign-in address, so they are recognised when they sign in with Microsoft. The home
  tenant follows the address' country domain (forty2.ch -> FORTY2_CH, ...).
  Users of other organisations in the YAML (Knowledge Pulse) are kept unchanged.

  Both demo files must stay identical: hansacore-api/demo-data-local.yml (DEV) and
  the git-ignored k8s/components/demo-data/demo-data.yml on the SIT server.

.EXAMPLE
  ./demo-users-from-csv.ps1 -Csv ..\..\Data\UsersDEV.csv -Yaml ..\..\hansacore-api\demo-data-local.yml
#>
param(
  [Parameter(Mandatory = $true)] [string] $Csv,
  [Parameter(Mandatory = $true)] [string] $Yaml
)

$ErrorActionPreference = 'Stop'

# Shared mailboxes are not people and get no demo user.
$excluded = @('career@forty2.lu', 'connect.agent@forty2.ch', 'events@forty2.ch', 'webdesign@forty2.ch')

# Extra rights per person (lines appended to the user's YAML entry).
$extras = @{
  'milad.gharib@forty2.ch'    = @('master-grant: true', 'detail-view: true')
  'rodrigue.kwanga@forty2.ch' = @('master-grant: true', 'detail-view: true')
  'nikka.sambajon@forty2.ph'  = @('groups:', '  - APAC')
}

$tenantByCountry = @{
  ch = 'FORTY2_CH'; lu = 'FORTY2_LU'; es = 'FORTY2_ES'; pt = 'FORTY2_PT'
  ph = 'FORTY2_PH'; sg = 'FORTY2_SG'; pl = 'FORTY2_PL'; de = 'FORTY2_DE'
}

function Quote([string] $value) {
  if ($value -match "^[\p{L}\p{M}][\p{L}\p{M} .\-]*$") { return $value }
  "'" + $value.Replace("'", "''") + "'"
}

$yamlPath = (Resolve-Path $Yaml).Path
$text = [IO.File]::ReadAllText($yamlPath) -replace "`r`n", "`n"
$marker = "`n    users:`n"
$split = $text.IndexOf($marker)
if ($split -lt 0) { throw "No 'users:' section found in $Yaml" }
$head = $text.Substring(0, $split + $marker.Length)
$userSection = $text.Substring($split + $marker.Length)

# Keep entries of other organisations as they are.
$kept = [regex]::Split($userSection, "(?m)^(?=      - )") |
  Where-Object { $_.Trim() -and $_ -notmatch 'home-tenant: FORTY2' }

$lines = New-Object System.Collections.Generic.List[string]
$people = Import-Csv -Path $Csv -Encoding UTF8
foreach ($person in $people) {
  $email = $person.userPrincipalName.Trim().ToLowerInvariant()
  if ($excluded -contains $email) { continue }
  $country = $email.Substring($email.LastIndexOf('.') + 1)
  $tenant = $tenantByCountry[$country]
  if (-not $tenant) { throw "No Forty2 tenant for '$email' (country '$country')" }
  $lines.Add("      - first-name: $(Quote $person.givenName.Trim())")
  $lines.Add("        last-name: $(Quote $person.surname.Trim())")
  $lines.Add("        email: $email")
  $lines.Add("        home-tenant: $tenant")
  $lines.Add("        iso: $country")
  if ($extras.ContainsKey($email)) {
    foreach ($extra in $extras[$email]) { $lines.Add("        $extra") }
  }
}

$forty2 = ($lines -join "`n") + "`n"
$others = ($kept | ForEach-Object { $_.TrimEnd("`n") + "`n" }) -join ''
[IO.File]::WriteAllText($yamlPath, $head + $forty2 + $others, (New-Object Text.UTF8Encoding $false))
Write-Host "Wrote $($people.Count - ($people | Where-Object { $excluded -contains $_.userPrincipalName.ToLowerInvariant() }).Count) Forty2 users and kept $(@($kept).Count) other users in $Yaml"
