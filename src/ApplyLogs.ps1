# Ensure necessary Azure modules are installed and imported
Import-Module Az.Monitor -Force
Import-Module Az.Compute -Force
Import-Module Az.OperationalInsights -Force

# Global variables setup
$resourceGroupName = "Andre-AzureMonitor"
$workspaceName = "amworkspace"
$jsonConfigPath = "C:\Ascott557\azure-monitor\src\monitoringConfig.json" # Adjust as necessary
$actionGroupId = "prototype" # Ensure this is correctly specified


# Function to install the MMA extension on a VM
function Install-MMAExtensionOnVMs {
    param (
        [Parameter(Mandatory=$true)]
        [Microsoft.Azure.Commands.ResourceManager.Cmdlets.SdkModels.PSResource]
        $vm
    )

    # Get the workspace
    $workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName -Name $workspaceName

    # Get the workspaceId and workspaceKey
    $workspaceId = $workspace.CustomerId
    $workspaceKey = (Get-AzOperationalInsightsWorkspaceSharedKey -ResourceGroupName $resourceGroupName -Name $workspaceName).PrimarySharedKey

    # Define the public and private settings for the MMA extension
    $publicSettings = @{ "workspaceId" = $workspaceId }
    $privateSettings = @{ "workspaceKey" = $workspaceKey }

     # Get the MMA extension if it's installed on the VM
     $mmaExtension = Get-AzVMExtension -ResourceGroupName $vm.ResourceGroupName -VMName $vm.Name -Name "MMAExtension" -ErrorAction SilentlyContinue

     # Check if the MMA extension is already installed
     if ($null -ne $mmaExtension) {
         Write-Host "MMA extension is already installed on VM: $($vm.Name)"
     } else {
         # Output the name of the VM where the extension is being installed
         Write-Host "Installing MMA extension on VM: $($vm.Name)"
 
         # Install the MMA extension
         Set-AzVMExtension -ResourceGroupName $vm.ResourceGroupName -VMName $vm.Name -Name "MMAExtension" -Publisher "Microsoft.EnterpriseCloud.Monitoring" -ExtensionType "MicrosoftMonitoringAgent" -TypeHandlerVersion "1.0" -Location $vm.Location -SettingString (ConvertTo-Json $publicSettings) -ProtectedSettingString (ConvertTo-Json $privateSettings)
 
         # Output a message after the extension is installed
         Write-Host "MMA extension installed on VM: $($vm.Name)"
     }
 }

# Get all VMs with Monitor tag set to Enabled
$vms = Get-AzResource -Tag @{ Monitor = "Enabled" } -ResourceType "Microsoft.Compute/virtualMachines"

# Output the number of VMs found
Write-Host "Found $($vms.Count) VMs with Monitor tag set to Enabled"

# Loop through each VM
foreach ($vm in $vms) {
    # Call the function to install the MMA extension
    Install-MMAExtensionOnVMs -vm $vm
}
function Apply-LogAlert {
    param (
        [string]$resourceId,
        [pscustomobject]$config,
        [string]$actionGroupId
    )

    $actionGroupResourceId = (Get-AzActionGroup -Name $actionGroupId -ResourceGroupName $resourceGroupName).Id

    $dimension = New-AzScheduledQueryRuleDimensionObject -Name "Computer" -Operator "Include" -Value "*"
    $condition = New-AzScheduledQueryRuleConditionObject -Dimension $dimension -Query $config.query -TimeAggregation "Average" -MetricMeasureColumn $config.metricMeasureColumn -Operator "GreaterThan" -Threshold 0 -FailingPeriodNumberOfEvaluationPeriod 1 -FailingPeriodMinFailingPeriodsToAlert 1

    # Ensure the time window is a supported granularity
    if ($config.timeWindowInMinutes -notin @(5, 10, 15, 30, 45, 60, 120, 180, 240, 300, 360, 1440, 2880)) {
        Write-Error "The time window must be one of the following values: 5, 10, 15, 30, 45, 60, 120, 180, 240, 300, 360, 1440, 2880"
        return
    }

    New-AzScheduledQueryRule -ResourceGroupName $resourceGroupName -Name $config.description -Location "northeurope" -Description $config.description -ActionGroupResourceId $actionGroupResourceId -CriterionAllOf $condition -Severity $config.severity -Enabled -EvaluationFrequency ([TimeSpan]::FromMinutes($config.frequencyInMinutes)) -WindowSize ([TimeSpan]::FromMinutes($config.timeWindowInMinutes)) -Scope $resourceId

    Write-Host "Log alert `"$($config.description)`" has been applied to $resourceId"
}
# function Apply-LogAlert {
#     param (
#         [string]$resourceId,
#         [pscustomobject]$config,
#         [string]$actionGroupId
#     )

#     $actionGroupResourceId = (Get-AzActionGroup -Name $actionGroupId -ResourceGroupName $resourceGroupName).Id

#     $alertRule = @{
#         "Location" = "Global" # Update this if your alert rule is in a specific location
#         "Source" = @{
#             "Query" = $config.query
#             "DataSourceId" = $resourceId
#             "QueryType" = "ResultCount"
#         }
#         "Schedule" = @{
#             "FrequencyInMinutes" = $config.frequencyInMinutes
#             "TimeWindowInMinutes" = $config.timeWindowInMinutes
#         }
#         "AznsAction" = @{
#             "ActionGroup" = @($actionGroupResourceId)
#         }
#         "Severity" = $config.severity
#         "Trigger" = @{
#             "ThresholdOperator" = "GreaterThan"
#             "Threshold" = 0
#         }
#     }

#     New-AzScheduledQueryRule -ResourceGroupName $resourceGroupName -Name $config.description -Location $alertRule.Location -Description $config.description -Source $alertRule.Source -Schedule $alertRule.Schedule -AznsAction $alertRule.AznsAction -Severity $alertRule.Severity -TriggerOperator $alertRule.Trigger.ThresholdOperator -TriggerThreshold $alertRule.Trigger.Threshold

#     Write-Host "Log alert `"$($config.description)`" has been applied to $resourceId"
# }
# function Apply-LogAlert {
#     param (
#         [string]$resourceId,
#         [pscustomobject]$config,
#         [string]$actionGroupId
#     )

#     $token = (Get-AzAccessToken -ResourceUrl https://management.azure.com).Token

#     $headers = @{
#         "Authorization" = "Bearer $token"
#         "Content-Type" = "application/json"
#     }
#     $actionGroupResourceId = (Get-AzActionGroup -Name $actionGroupId -ResourceGroupName $resourceGroupName).Id

#     $body = @{
#         "properties" = @{
#             "description" = $config.description
#             "enabled" = $true
#             "source" = @{
#                 "query" = $config.query
#                 "dataSourceId" = $resourceId
#                 "queryType" = "ResultCount"
#             }
#             "schedule" = @{
#                 "frequencyInMinutes" = $config.frequencyInMinutes
#                 "timeWindowInMinutes" = $config.frequencyInMinutes
#             }
#             "action" = @{
#                 "odata.type" = "Microsoft.WindowsAzure.Management.Monitoring.Alerts.Models.Microsoft.AppInsights.Nexus.DataContracts.Resources.ScheduledQueryRules.AlertingAction"
#                 "aznsAction" = @{
#                     "actionGroup" = @($actionGroupResourceId)
#                 }
#                 "severity" = $config.severity
#                 "trigger" = @{
#                     "thresholdOperator" = "GreaterThan"
#                     "threshold" = 0
#                 }
#             }
#         }
#     } | ConvertTo-Json -Depth 10

#     if ($resourceId -match "^/subscriptions/.+/resourceGroups/.+/providers/.+/.+/.+$") {
#         Write-Output "Resource ID is valid"
#     } else {
#         Write-Output "Resource ID is not valid"
#         # Exit the script if the resource ID is not valid
#         exit
#     }
#     # $apiVersion = "2023-09-01" # Update to a valid API version
#     # $uri = "https://management.azure.com${resourceId}/providers/microsoft.insights/metricAlerts/${config.description}?api-version=${apiVersion}"
#     $config.description = $config.description -replace ' ', '-'
#     # Remove any other characters that are not letters, numbers, hyphens, or underscores
#     $config.description = $config.description -replace '[^a-zA-Z0-9-_]', ''
#     $uri = "https://management.azure.com$($resourceId)/providers/microsoft.insights/scheduledQueryRules/$($config.description)?api-version=2023-09-01"
#     Invoke-RestMethod -Method Put -Uri $uri -Headers $headers -Body $body

#     Write-Host "Log alert `"$($config.description)`" has been applied to $resourceId"
# }

# Load JSON configurations
$configs = Get-Content -Path $jsonConfigPath | ConvertFrom-Json

# Iterate over configurations and apply them
foreach ($configGroup in $configs.monitoringConfigurations) {
    $taggedResources = Get-AzResource -Tag @{ Monitor = "Enabled" } | Where-Object { $_.Type -eq $configGroup.resourceType }

    foreach ($resource in $taggedResources) {
        foreach ($config in $configGroup.configurations) {
            if ($config.type -eq "metric") {
                Apply-MetricAlert -resourceId $resource.Id -config $config -actionGroupId $actionGroupId
            } elseif ($config.type -eq "log") {
                Apply-LogAlert -resourceId $resource.Id -config $config -actionGroupId $actionGroupId
            }
        }
    }
}

# # Function to apply metric-based alerts
# function Apply-MetricAlert {
#     param (
#         [string]$resourceId,
#         [pscustomobject]$config,
#         [string]$actionGroupId
#     )

#     $windowSize = "PT" + $config.frequencyInMinutes + "M"
#     $evaluationFrequency = "PT" + $config.frequencyInMinutes + "M"

#     $condition = New-AzMetricAlertRuleV2Criteria -MetricName $config.metricName `
#         -Operator $config.operator -Threshold $config.threshold `
#         -TimeAggregation $config.timeAggregation

#     New-AzMetricAlertRuleV2 -Name $config.name `
#         -ResourceGroupName (Get-AzResource -ResourceId $resourceId).ResourceGroupName `
#         -WindowSize $windowSize -Frequency $evaluationFrequency `
#         -TargetResourceId $resourceId -Criteria $condition `
#         -ActionGroupId $actionGroupId -Severity $config.severity `
#         -Description $config.description

#     Write-Host "Metric alert `"$($config.name)`" has been applied to $resourceId"
# }

# # Load JSON configurations
# $configs = Get-Content -Path $jsonConfigPath | ConvertFrom-Json

# # Iterate over configurations and apply them
# foreach ($configGroup in $configs.monitoringConfigurations) {
#     $taggedResources = Get-AzResource -Tag @{ Monitor = "Enabled" } | Where-Object { $_.Type -eq $configGroup.resourceType }

#     foreach ($resource in $taggedResources) {
#         foreach ($config in $configGroup.configurations) {
#             if ($config.type -eq "metric") {
#                 Apply-MetricAlert -resourceId $resource.Id -config $config -actionGroupId $actionGroupId
#             } elseif ($config.type -eq "log") {
#                 # Placeholder for applying log-based monitoring using KQL queries
#                 # Extend this section with a similar function for log alerts
#                 Write-Host "Applying log alert for $($config.description) to $($resource.Name)"
#             }
#         }
#     }
# }

Write-Host "Monitoring configuration process completed."
