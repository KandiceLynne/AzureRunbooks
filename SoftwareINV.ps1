# Login to Azure
Connect-AzAccount

# Output file
$outputFile = ".\AVD-Software-Inventory.csv"

# Array for results
$results = @()

# Get all host pools
$hostPools = Get-AzWvdHostPool

foreach ($pool in $hostPools) {

    Write-Host "Processing Host Pool: $($pool.Name)" -ForegroundColor Cyan

    # Get session hosts
    $sessionHosts = Get-AzWvdSessionHost `
        -ResourceGroupName $pool.ResourceGroupName `
        -HostPoolName $pool.Name

    foreach ($host in $sessionHosts) {

        # Extract VM name from session host name
        $vmName = ($host.Name -split "/")[-1].Split(".")[0]

        Write-Host "Collecting software from $vmName ..." -ForegroundColor Yellow

        try {

            $software = Invoke-Command -ComputerName $vmName -ScriptBlock {

                $paths = @(
                    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
                )

                foreach ($path in $paths) {
                    Get-ItemProperty $path -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_.DisplayName -and $_.DisplayName.Trim() -ne ""
                    } |
                    Select-Object @{
                        Name = "ComputerName"
                        Expression = { $env:COMPUTERNAME }
                    },
                    DisplayName,
                    DisplayVersion,
                    Publisher,
                    InstallDate
                }
            }

            $results += $software

        }
        catch {
            Write-Warning "Failed to query $vmName : $_"
        }
    }
}

# Export results
$results |
Sort-Object ComputerName, DisplayName |
Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

Write-Host "Inventory exported to $outputFile" -ForegroundColor Green
