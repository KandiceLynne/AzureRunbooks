# -------------------------------------------------------------------
# AVD Software Inventory Script
# Azure Cloud Shell PowerShell
# -------------------------------------------------------------------

# =========================
# VARIABLES
# =========================

$TenantId       = "<TENANT-ID>"
$SubscriptionId = "<SUBSCRIPTION-ID>"

$ResourceGroupName = "rg-avd-prod"
$HostPoolName      = "hp-prod"

$OutputFile = "$HOME/avd_software_inventory.csv"

# =========================
# LOGIN
# =========================

Connect-AzAccount -Tenant $TenantId

Set-AzContext `
    -Tenant $TenantId `
    -SubscriptionId $SubscriptionId

# =========================
# GET SESSION HOSTS
# =========================

Write-Host ""
Write-Host "Getting session hosts..." -ForegroundColor Cyan

$SessionHosts = Get-AzWvdSessionHost `
    -ResourceGroupName $ResourceGroupName `
    -HostPoolName $HostPoolName

if (!$SessionHosts)
{
    Write-Host "No session hosts found." -ForegroundColor Yellow
    return
}

Write-Host "Found $($SessionHosts.Count) hosts." -ForegroundColor Green

# =========================
# RESULTS ARRAY
# =========================

$Results = @()

# =========================
# PROCESS EACH HOST
# =========================

foreach ($SessionHost in $SessionHosts)
{
    # Extract VM Name
    $FullName = ($SessionHost.Name -split "/")[1]
    $VMName   = ($FullName -split "\.")[0]

    Write-Host ""
    Write-Host "Processing: $VMName" -ForegroundColor Green

    try
    {
        # =========================================================
        # REMOTE SCRIPT
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

$Software |
Sort-Object DisplayName |
ConvertTo-Csv -NoTypeInformation
'@

        # =========================================================
        # EXECUTE COMMAND
        # =========================================================

        $RunCommand = Invoke-AzVMRunCommand `
            -ResourceGroupName $ResourceGroupName `
            -VMName $VMName `
            -CommandId 'RunPowerShellScript' `
            -ScriptString $Command `
            -ErrorAction Stop

        # =========================================================
        # GET RAW OUTPUT
        # =========================================================

        $RawOutput = $RunCommand.Value[0].Message

        # Uncomment for troubleshooting
        # Write-Host $RawOutput

        # =========================================================
        # CLEAN OUTPUT
        # =========================================================

        $Lines = $RawOutput -split "`n"

        # Keep only CSV lines
        $CsvLines = $Lines | Where-Object {
            $_ -match '^"'
        }

        if ($CsvLines.Count -gt 1)
        {
            $CsvText = $CsvLines -join "`n"

            $SoftwareList = $CsvText | ConvertFrom-Csv

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

            Write-Host "Inventory collected from $VMName" -ForegroundColor Cyan
        }
        else
        {
            Write-Host "No software data returned from $VMName" -ForegroundColor Yellow

            $Results += [PSCustomObject]@{
                VMName         = $VMName
                DisplayName    = "NO DATA"
                DisplayVersion = ""
                Publisher      = ""
                InstallDate    = ""
            }
        }
    }
    catch
    {
        Write-Host "Failed: $VMName" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red

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
Write-Host "Exporting CSV..." -ForegroundColor Cyan

$Results |
Sort-Object VMName, DisplayName |
Export-Csv `
    -Path $OutputFile `
    -NoTypeInformation `
    -Encoding UTF8

Write-Host ""
Write-Host "Completed." -ForegroundColor Green
Write-Host "Output File: $OutputFile" -ForegroundColor Yellow
