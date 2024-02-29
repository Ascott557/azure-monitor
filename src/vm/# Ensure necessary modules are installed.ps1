# Ensure necessary modules are installed and imported
Install-Module -Name Az -AllowClobber -Force -Scope CurrentUser
Import-Module Az.Monitor -Force
Import-Module Az.Compute -Force
Import-Module Az.OperationalInsights -Force



# Setup variables
$resourceGroupName = "Andre-AzureMonitor"
$workspaceName = "amworkspace"
$location = "North Europe"

# Retrieve workspace details
$workspace = Get-AzOperationalInsightsWorkspace `
    -ResourceGroupName $resourceGroupName `
    -Name $workspaceName

$actionGroupId = (Get-AzActionGroup `
    -ResourceGroupName $resourceGroupName).Id

# Identify and iterate over VMs
$vms = Get-AzResource `
    -Tag @{ Monitor="Enabled" } `
    | Where-Object { $_.ResourceType -eq "Microsoft.Compute/virtualMachines" }

foreach ($vm in $vms) {
    Write-Host "Processing VM: $($vm.Name) in Resource Group: $($vm.ResourceGroupName)"
    
    # Check for existing MMA extension
    $existingExtension = Get-AzVMExtension `
        -ResourceGroupName $vm.ResourceGroupName `
        -VMName $vm.Name `
        -Name "MMA" `
        -ErrorAction SilentlyContinue
    
    if ($existingExtension) {
        Write-Host "MMA extension already present on $($vm.Name)."
    } else {
        # Apply MMA extension
        $settings = @{ "workspaceId" = $workspace.CustomerId }
        $protectedSettings = @{ "workspaceKey" = (Get-AzOperationalInsightsWorkspaceSharedKey `
            -ResourceGroupName $resourceGroupName `
            -Name $workspaceName).PrimarySharedKey }

        Set-AzVMExtension `
            -ResourceGroupName $vm.ResourceGroupName `
            -VMName $vm.Name `
            -Name "MMA" `
            -Publisher "Microsoft.EnterpriseCloud.Monitoring" `
            -ExtensionType "MicrosoftMonitoringAgent" `
            -TypeHandlerVersion "1.0" `
            -Settings $settings `
            -ProtectedSettings $protectedSettings `
            -Location $vm.Location

        Write-Host "MMA extension installed on $($vm.Name)."
    }

    # Configure CPU utilization alert
    $condition = New-AzMetricAlertRuleV2Criteria `
        -MetricName "Percentage CPU" `
        -Operator GreaterThanOrEqual `
        -Threshold 85 `
        -TimeAggregation Average

    $actionGroup = Get-AzActionGroup -ResourceGroupName $resourceGroupName
    $actionGroupId = $actionGroup.Id

    $alertParams = @{
        Name = "HighCPUUsage-$($vm.Name)"
        ResourceGroupName = $vm.ResourceGroupName
        Scope = @($vm.Id)
        Condition = $condition
        ActionGroupId = @($actionGroupId)
        WindowSize = [TimeSpan]::FromMinutes(5)
        EvaluationFrequency = [TimeSpan]::FromMinutes(1)
        Severity = 3
        Description = "Alert when CPU usage is over 85%."
    }

    Add-AzMetricAlertRuleV2 @alertParams


Write-Host "Monitoring and alert configuration process completed."


