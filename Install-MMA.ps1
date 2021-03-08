if (Get-Service 'Microsoft Monitoring Agent') {
	& msiexec /i \\tssn-file\System\Installers\MMA-AMD64_Installer\MOMAgent.msi /qn /l*v \\tssn-file\System\Logs\MOMInstall\OMAgentInstall_$env:Computername.log USE_SETTINGS_FROM_AD=1 ACTIONS_USE_COMPUTER_ACCOUNT=1 USE_MANUALLY_SPECIFIED_SETTINGS=0 ADD_OPINSIGHTS_WORKSPACE=1 OPINSIGHTS_WORKSPACE_AZURE_CLOUD_TYPE=0 OPINSIGHTS_WORKSPACE_ID="c141e970-8446-422f-948b-9cb0c56b4f15" OPINSIGHTS_WORKSPACE_KEY="3hGqpSZoOiYJ5ifYdQ6zYa6MJ2cBpv8h+ABVkgiMkMee2S88M9OIRY3LXrNvJneoNsNu+YH1csgLwY76FzdIvw==" AcceptEndUserLicenseAgreement=1
}
else {
    $mma = New-Object -ComObject 'AgentConfigManager.MgmtSvcCfg'
    $WID = ($mma.getcloudworkspaces() | Select WorkspaceId).workspaceid

    if ($WID -ne 'c141e970-8446-422f-948b-9cb0c56b4f15') { 
        $workspaceId = "c141e970-8446-422f-948b-9cb0c56b4f15"
        $workspaceKey = "3hGqpSZoOiYJ5ifYdQ6zYa6MJ2cBpv8h+ABVkgiMkMee2S88M9OIRY3LXrNvJneoNsNu+YH1csgLwY76FzdIvw=="
        $mma = New-Object -ComObject 'AgentConfigManager.MgmtSvcCfg'
        $mma.AddCloudWorkspace($workspaceId, $workspaceKey)
        $mma.ReloadConfiguration()
    }
}