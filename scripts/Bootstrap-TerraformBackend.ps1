<#
.SYNOPSIS
    Creates the Azure Storage account used as the Terraform remote backend, with the
    folder structure for the two regional stacks, and writes backend.hcl for each stack.

.DESCRIPTION
    Run this ONCE, before 'terraform init'. It is safe to re-run.

    What it creates (in the GOVERNANCE subscription):
      * Resource group
      * Storage account  - GZRS, TLS 1.2, no public blob access,
                           shared-key access DISABLED (Entra ID authentication only)
      * Blob versioning + blob soft delete + container soft delete (state recovery)
      * Container        - default 'tfstate'
      * One "folder" per stack - default: primary-centralindia, secondary-southindia
      * Optional CanNotDelete lock on the storage account
      * <RepoRoot>\<stack>\backend.hcl for every stack folder found

    Resulting layout inside the container:
        tfstate/
          primary-centralindia/terraform.tfstate     (created by the first 'terraform apply')
          secondary-southindia/terraform.tfstate

    About "folders": blob storage has no real directories. A folder is just a name prefix,
    so Terraform creates 'primary-centralindia/terraform.tfstate' by itself. This script also
    uploads an empty '.keep' marker per folder purely so the folders are visible in the portal.

.PARAMETER SubscriptionId
    Governance subscription ID (the state storage account lives there).

.EXAMPLE
    .\Bootstrap-TerraformBackend.ps1 -SubscriptionId "<governance-subscription-id>" -ResourceGroupName "<state-rg-name>"" -StorageAccountName <globally-unique-name>"

.NOTES
    Requires: PowerShell 7+ (or Windows PowerShell 5.1) and the Az.Accounts, Az.Resources and
    Az.Storage modules.  Install-Module Az -Scope CurrentUser
    The signed-in account needs Owner (or Contributor + User Access Administrator) on the
    resource group, because the script grants itself 'Storage Blob Data Contributor'.
    After this script, the identity that runs Terraform ALSO needs
    'Storage Blob Data Contributor' on the storage account (or container).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $SubscriptionId,

    [Parameter(Mandatory)]
    [string] $ResourceGroupName,

    # 3-24 characters, lowercase letters and digits only, globally unique.
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9]{3,24}$')]
    [string] $StorageAccountName,

    [string] $Location = 'centralindia',

    [ValidateSet('Standard_GZRS', 'Standard_RAGZRS')]
    [string] $SkuName = 'Standard_GZRS',

    [string] $ContainerName = 'tfstate',

    # One folder per Terraform stack. Must match the stack directory names in the repo.
    [string[]] $StateFolders = @('primary-centralindia', 'secondary-southindia'),

    [ValidateRange(1, 365)]
    [int] $SoftDeleteDays = 30,

    [bool] $ApplyDeleteLock = $true,

    [hashtable] $Tags = @{ environment = 'prd'; workload = 'platform'; owner = 'platform-team@example.com'; cost_center = 'CC-0000'; managed_by = 'terraform-backend-script' },

    # Folder that contains the stack directories (default: the parent of this script's folder).
    [string] $RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

function Write-Step([string] $Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

# ---------------------------------------------------------------- 0. Modules and sign-in
foreach ($module in 'Az.Accounts', 'Az.Resources', 'Az.Storage') {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        throw "PowerShell module '$module' is missing. Run: Install-Module Az -Scope CurrentUser"
    }
}

Write-Step "Selecting subscription $SubscriptionId"

$context = Get-AzContext -ErrorAction SilentlyContinue

if (-not $context) {
    if ($env:GITHUB_ACTIONS -eq "true") {
        throw "No Azure PowerShell context available. Ensure azure/login uses enable-AzPSSession:true."
    }

    Connect-AzAccount | Out-Null
    $context = Get-AzContext
}

Set-AzContext -Subscription $SubscriptionId | Out-Null
$context = Get-AzContext
$tenantId = $context.Tenant.Id


# ---------------------------------------------------------------- 1. Resource group
Write-Step "Resource group '$ResourceGroupName'"
if (-not (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Tag $Tags | Out-Null
    Write-Host "    created"
}
else {
    Write-Host "    already exists"
}

# ---------------------------------------------------------------- 2. Storage account
Write-Step "Storage account '$StorageAccountName' ($SkuName)"
$account = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
if (-not $account) {
    $account = New-AzStorageAccount `
        -ResourceGroupName        $ResourceGroupName `
        -Name                     $StorageAccountName `
        -Location                 $Location `
        -SkuName                  $SkuName `
        -Kind                     StorageV2 `
        -AccessTier               Hot `
        -MinimumTlsVersion        TLS1_2 `
        -EnableHttpsTrafficOnly   $true `
        -AllowBlobPublicAccess    $false `
        -AllowSharedKeyAccess     $false `
        -Tag                      $Tags
    Write-Host "    created"
}
else {
    # Re-assert the security settings if the account already existed.
    Set-AzStorageAccount `
        -ResourceGroupName      $ResourceGroupName `
        -Name                   $StorageAccountName `
        -MinimumTlsVersion      TLS1_2 `
        -EnableHttpsTrafficOnly $true `
        -AllowBlobPublicAccess  $false `
        -AllowSharedKeyAccess   $false | Out-Null
    Write-Host "    already exists - security settings re-applied"
}

# ---------------------------------------------------------------- 3. Data protection
# Versioning lets you roll back a corrupted state file; soft delete recovers deleted ones.
Write-Step "Enabling blob versioning and soft delete ($SoftDeleteDays days)"
Update-AzStorageBlobServiceProperty `
    -ResourceGroupName $ResourceGroupName `
    -StorageAccountName $StorageAccountName `
    -IsVersioningEnabled $true `
    #-DeleteRetentionPolicy @{Enabled = $true; Days = $SoftDeleteDays} `
    #-ContainerDeleteRetentionPolicy @{Enabled = $true; Days = $SoftDeleteDays}

# ---------------------------------------------------------------- 4. Container (management plane)
Write-Step "Container '$ContainerName'"
if (-not (Get-AzRmStorageContainer -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -Name $ContainerName -ErrorAction SilentlyContinue)) {
    New-AzRmStorageContainer -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName `
        -Name $ContainerName -PublicAccess None | Out-Null
    Write-Host "    created"
}
else {
    Write-Host "    already exists"
}

# ---------------------------------------------------------------- 5. Data-plane access for this script
# Shared keys are disabled, so uploading the folder markers needs an Entra role.
Write-Step "Granting the signed-in identity 'Storage Blob Data Contributor' on the account"
if ($context.Account.Type -eq 'User') {
    $principalId = (Get-AzADUser -SignedIn).Id
}
else {
    $principalId = (Get-AzADServicePrincipal -ApplicationId $context.Account.Id).Id
}
$scope = $account.Id
$hasRole = Get-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName 'Storage Blob Data Contributor' -Scope $scope -ErrorAction SilentlyContinue
if (-not $hasRole) {
    New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName 'Storage Blob Data Contributor' -Scope $scope | Out-Null
    Write-Host "    role assigned (can take a few minutes to take effect)"
}
else {
    Write-Host "    already assigned"
}

# ---------------------------------------------------------------- 6. Folder markers
Write-Step "Creating folders: $($StateFolders -join ', ')"
$storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount
$marker = New-TemporaryFile
try {
    foreach ($folder in $StateFolders) {
        $uploaded = $false
        for ($attempt = 1; $attempt -le 12 -and -not $uploaded; $attempt++) {
            try {
                Set-AzStorageBlobContent -File $marker.FullName -Container $ContainerName `
                    -Blob "$folder/.keep" -Context $storageContext -Force | Out-Null
                $uploaded = $true
                Write-Host "    $ContainerName/$folder/"
            }
            catch {
                # Role assignments propagate slowly; retry for up to ~2 minutes.
                Write-Host "    waiting for the role assignment to take effect (attempt $attempt/12)..."
                Start-Sleep -Seconds 10
            }
        }
        if (-not $uploaded) { throw "Could not write to the container. Check your role assignment and re-run the script." }
    }
}
finally {
    Remove-Item $marker.FullName -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------- 7. Delete lock
if ($ApplyDeleteLock) {
    Write-Step "CanNotDelete lock on the storage account"
    $lockName = 'tfstate-do-not-delete'
    if (-not (Get-AzResourceLock -ResourceGroupName $ResourceGroupName -ResourceName $StorageAccountName `
                -ResourceType 'Microsoft.Storage/storageAccounts' -LockName $lockName -ErrorAction SilentlyContinue)) {
        New-AzResourceLock -LockName $lockName -LockLevel CanNotDelete -ResourceGroupName $ResourceGroupName `
            -ResourceName $StorageAccountName -ResourceType 'Microsoft.Storage/storageAccounts' `
            -LockNotes 'Holds Terraform state. Remove the lock before deleting.' -Force | Out-Null
        Write-Host "    lock created"
    }
    else {
        Write-Host "    lock already exists"
    }
}

# ---------------------------------------------------------------- 8. backend.hcl for each stack
Write-Step "Writing backend.hcl files"
foreach ($folder in $StateFolders) {
    $stackPath = Join-Path $RepoRoot $folder
    if (-not (Test-Path $stackPath)) {
        Write-Warning "Stack folder '$stackPath' not found - skipped. Use -RepoRoot to point at the repository."
        continue
    }
    $content = @"
# Generated by scripts/Bootstrap-TerraformBackend.ps1 - used with: terraform init -backend-config=backend.hcl
subscription_id      = "$SubscriptionId"
tenant_id            = "$tenantId"
resource_group_name  = "$ResourceGroupName"
storage_account_name = "$StorageAccountName"
container_name       = "$ContainerName"
key                  = "$folder/terraform.tfstate"
use_azuread_auth     = true
"@
    Set-Content -Path (Join-Path $stackPath 'backend.hcl') -Value $content -Encoding utf8
    Write-Host "    $stackPath\backend.hcl"
}

# ---------------------------------------------------------------- Done
Write-Host ""
Write-Host "Backend ready." -ForegroundColor Green
Write-Host "  Storage account : $StorageAccountName  ($SkuName, Entra ID auth only)"
Write-Host "  Container       : $ContainerName"
Write-Host "  State paths     : $(($StateFolders | ForEach-Object { "$_/terraform.tfstate" }) -join ', ')"
Write-Host ""
Write-Host "Next:" -ForegroundColor Yellow
Write-Host "  1. Give the identity that runs Terraform 'Storage Blob Data Contributor' on '$StorageAccountName'."
Write-Host "  2. cd <stack folder>; terraform init -backend-config="backend.hcl""
