# -------------------------------------------------------------------
# AVD Software Inventory Script
# Runs in Azure Cloud Shell PowerShell
#
# Requirements:
# - Az.Accounts
# - Az.Compute
# - Az.DesktopVirtualization
#
# Output:
# - CSV containing installed software from all AVD session hosts
# -------------------------------------------------------------------

# =========================
# VARIABLES
# =========================

$TenantId       = "<TENANT-ID>"
$SubscriptionId = "<SUBSCRIPTION-ID>"

# Host Pool Information
$ResourceGroupName = "rg-avd-prod"
$HostPoolName      = "hp-prod"

# Output file
$OutputFile = "$HOME/avd_software_inventory.csv"

# =========================
# LOGIN / CONTEXT
# =========================

Connect-AzAccount -Tenant $TenantId

Set-AzContext `
    -Tenant $TenantId `
    -SubscriptionId $SubscriptionId

# =========================
# GET SESSION HOSTS
# =========================

Write-Host "Getting AVD session hosts..." -ForegroundColor Cyan

$SessionHosts = Get-AzWvdSessionHost `
    -ResourceGroupName $ResourceGroupName `
    -HostPoolName $HostPoolName

if (!$SessionHosts)
{
    Write-Host "No session hosts found." -ForegroundColor Yellow
    return
}

# =========================
# RESULTS ARRAY
# =========================

$Results = @()

# =========================
# LOOP THROUGH SESSION HOSTS
# =========================

foreach ($SessionHost in $SessionHosts)
{
    # Extract VM name from session host name
    # Example:
    # hp-prod/avd-01.domain.local
    # becomes:
    # avd-01

    $FullName = ($SessionHost.Name -split "/")[1]
    $VMName   = ($FullName -split "\.")[0]

    Write-Host ""
    Write-Host "Processing VM: $VMName" -ForegroundColor Green

    try
    {
        # =========================================================
        # RUN COMMAND ON VM
        # =========================================================

        $Command = @'
$Paths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$Software = foreach ($Path in $Paths)
{
    Get-ItemProperty $Path -ErrorAction SilentlyContinue |
    Where-Object {
        $_.DisplayName -and $_.DisplayName.Trim() -ne ""
    } |
    Select-Object `
        DisplayName,
        DisplayVersion,
        Publisher,
        InstallDate
}

$Software | Sort-Object DisplayName | ConvertTo-Json -Depth 3
'@

        $RunCommand = Invoke-AzVMRunCommand `
            -ResourceGroupName $ResourceGroupName `
            -VMName $VMName `
            -CommandId 'RunPowerShellScript' `
            -ScriptString $Command `
            -ErrorAction Stop

        # =========================================================
        # PARSE RESULTS
        # =========================================================

        $JsonResult = $RunCommand.Value[0].Message

        if ($JsonResult)
        {
            $SoftwareList = $JsonResult | ConvertFrom-Json

            foreach ($App in $SoftwareList)
            {
                $Results += [PSCustomObject]@{
                    VMName         = $VMName
                    DisplayName    = $App.DisplayName
                    DisplayVersion = $App.DisplayVersion
                    Publisher      = $App.Publisher
                    InstallDate    = $App.InstallDate
                }
            }
        }
    }
    catch
    {
        Write-Host "Failed: $VMName" -ForegroundColor Red
        Write-Host $_.Exception.Message

        $Results += [PSCustomObject]@{
            VMName         = $VMName
            DisplayName    = "ERROR"
            DisplayVersion = ""
            Publisher      = $_.Exception.Message
            InstallDate    = ""
        }
    }
}

# =========================
# EXPORT RESULTS
# =========================

Write-Host ""
Write-Host "Exporting results..." -ForegroundColor Cyan

$Results |
Sort-Object VMName, DisplayName |
Export-Csv `
    -Path $OutputFile `
    -NoTypeInformation `
    -Encoding UTF8

Write-Host ""
Write-Host "Completed." -ForegroundColor Green
Write-Host "Output File: $OutputFile" -ForegroundColor Yellow
