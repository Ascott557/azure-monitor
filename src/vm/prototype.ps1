# Prerequisites: Ensure necessary Azure modules are installed and imported
Import-Module Az.Monitor -Force
Import-Module Az.Compute -Force
Import-Module Az.OperationalInsights -Force

# Global variables setup (adjust these as per your environment)
$resourceGroupName = "Andre-AzureMonitor"
$workspaceName = "amworkspace"
$jsonConfigPath = "C:\Ascott557\azure-monitor\src\monitoringConfig.json"
$actionGroupId = "prototype" # Make sure this is updated to a valid Action Group ID

# Retrieve workspace details
$workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName -Name $workspaceName

# Enhanced function with debugging for MMA extension installation
function Install-MMAExtension {
    param (
        [string]$vmName,
        [string]$resourceGroupName,
        [pscustomobject]$workspace,
        [string]$location
    )
    
    Write-Host "Checking for existing MMA extension on VM: $vmName..."
    try {
        $existingExtension = Get-AzVMExtension -VMName $vmName -ResourceGroupName $resourceGroupName -Name "MMA" -ErrorAction Stop
        if ($existingExtension) {
            Write-Host "MMA extension already present on $vmName."
        }
    }
    catch {
        Write-Host "MMA extension not found on $vmName. Attempting installation..."
        $settings = @{
            "workspaceId" = $workspace.CustomerId
        }
        $protectedSettings = @{
            "workspaceKey" = (Get-AzOperationalInsightsWorkspaceSharedKey -ResourceGroupName $resourceGroupName -Name $workspace.Name).PrimarySharedKey
        }

        try {
            Set-AzVMExtension -ResourceGroupName $resourceGroupName -VMName $vmName -Name "MMA" -Publisher "Microsoft.EnterpriseCloud.Monitoring" -ExtensionType "MicrosoftMonitoringAgent" -TypeHandlerVersion "1.0" -Settings $settings -ProtectedSettings $protectedSettings -Location $location
            Write-Host "MMA extension successfully installed on $vmName."
        }
        catch {
            Write-Host "Failed to install MMA extension on $vmName. Error: $_"
        }
    }
}

# Assuming $vms is populated correctly above this point

# Load JSON configurations
$configs = Get-Content -Path $jsonConfigPath | ConvertFrom-Json

# Iterate over configurations and apply them
foreach ($configGroup in $configs.monitoringConfigurations) {
    $taggedResources = Get-AzResource -Tag @{ Monitor = "Enabled" } | Where-Object { $_.Type -eq $configGroup.resourceType }

    foreach ($resource in $taggedResources) {
        Write-Host "Processing Resource: $($resource.Name) of Type: $($resource.Type)"
        foreach ($config in $configGroup.configurations) {
            if ($config.type -eq "metric") {
                # Ensure the correct function name is used here
                Set-MetricAlert -resourceId $resource.Id -config $config -actionGroupId $actionGroupId
            } elseif ($config.type -eq "log") {
                # Placeholder for log-based monitoring
                Write-Host "Intended to apply log alert for $($config.description) to $($resource.Name)"
            }
        }
    }
}

Write-Host "Monitoring configuration process completed."
