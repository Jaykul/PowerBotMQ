Start-BridgeJob -Verbose

foreach($Adapter in Get-ChildItem $PSScriptRoot\Adapters -File -Filter *.psm1) {
    $VerbosePreference = "Continue"
    
    $Array = (Resolve-Path $PSScriptRoot\PowerBotMQ.psm1), $Adapter.FullName
    Write-Verbose $Array[0]
    Write-Verbose $Array[1]

    Start-Job -Name $Adapter.BaseName -ScriptBlock {
        param($PowerBotPath, $AdapterPath)
        $VerbosePreference = "Continue"
        Write-Verbose "Import BOT: $PowerBotPath" -Verbose
        Write-Verbose "Import ADAPTER: $AdapterPath" -Verbose
        $Bot, $Adapter = Import-Module $PowerBotPath, $AdapterPath -PassThru
        Write-Verbose "Imported BOT: $Bot"
        Write-Verbose "Imported ADAPTER: $Adapter"
        Write-Verbose "Start-Adapter ... "
        Start-Adapter
    } -ArgumentList (Resolve-Path $PSScriptRoot\PowerBotMQ.psm1), $Adapter.FullName
}