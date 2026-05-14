# ------------------------------------------------------------
# SOFTWARE INVENTORY - RESOURCE GROUP ONLY
# ------------------------------------------------------------

# VARIABLES
$TenantId       = "<TENANT-ID>"
$SubscriptionId = "<SUBSCRIPTION-ID>"
$ResourceGroup  = "rg-avd-prod"

# Output
$OutputFile = "C:\Temp\AVD_Software_Inventory.csv"

# Connect
Connect-AzAccount -Tenant $TenantId

Set-AzContext `
    -Tenant $TenantId `
    -SubscriptionId $SubscriptionId

# ONLY RUNNING VMs
$VMs = Get-AzVM `
    -ResourceGroupName $ResourceGroup `
    -Status |
Where-Object {
    $_.PowerState -eq "VM running"
}

Write-Host "Found $($VMs.Count) running VMs"

# Results
$Results = @()

foreach ($VM in $VMs)
{
    Write-Host ""
    Write-Host "Processing $($VM.Name)..." -ForegroundColor Cyan

    try
    {
        # ----------------------------------------------------
        # REMOTE SCRIPT
        # ----------------------------------------------------

        $Script = @'
$Apps = Get-ItemProperty `
HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*,
HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* `
-ErrorAction SilentlyContinue |
Where-Object {
    $_.DisplayName
}

foreach ($App in $Apps)
{
    Write-Output "$($App.DisplayName)||$($App.DisplayVersion)||$($App.Publisher)||$($App.InstallDate)"
}
'@

        # ----------------------------------------------------
        # RUN COMMAND
        # ----------------------------------------------------

        $Job = Invoke-AzVMRunCommand `
            -ResourceGroupName $ResourceGroup `
            -VMName $VM.Name `
            -CommandId 'RunPowerShellScript' `
            -ScriptString $Script `
            -ErrorAction Stop

        # ----------------------------------------------------
        # VALIDATE OUTPUT
        # ----------------------------------------------------

        if ($null -eq $Job.Value)
        {
            Write-Host "No output returned from $($VM.Name)" -ForegroundColor Yellow
            continue
        }

        # ----------------------------------------------------
        # GET RAW MESSAGE
        # ----------------------------------------------------

        $Output = $Job.Value.Message

        # DEBUG
        Write-Host "RAW OUTPUT:"
        Write-Host $Output

        # ----------------------------------------------------
        # PARSE SOFTWARE LINES
        # ----------------------------------------------------

        $Lines = $Output -split "`r?`n"

        $SoftwareLines = $Lines | Where-Object {
            $_ -match '\|\|'
        }

        foreach ($Line in $SoftwareLines)
        {
            $Parts = $Line -split '\|\|',4

            $Results += [PSCustomObject]@{
                VMName         = $VM.Name
                DisplayName    = $Parts[0]
                DisplayVersion = $Parts[1]
                Publisher      = $Parts[2]
                InstallDate    = $Parts[3]
            }
        }

        Write-Host "Collected $($SoftwareLines.Count) entries from $($VM.Name)" -ForegroundColor Green
    }
    catch
    {
        Write-Host "Failed: $($VM.Name)" -ForegroundColor Red
        Write-Host $_.Exception.Message

        $Results += [PSCustomObject]@{
            VMName         = $VM.Name
            DisplayName    = "ERROR"
            DisplayVersion = ""
            Publisher      = $_.Exception.Message
            InstallDate    = ""
        }
    }
}

# ------------------------------------------------------------
# EXPORT
# ------------------------------------------------------------

$Results |
Export-Csv `
    -Path $OutputFile `
    -NoTypeInformation `
    -Encoding UTF8

Write-Host ""
Write-Host "Completed"
Write-Host "Output File: $OutputFile"
