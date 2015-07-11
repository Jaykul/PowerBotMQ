Start-ZeroMqHub -Verbose
$PowerBotAdapters = "$PSScriptRoot\Adapters"
$PowerBotMQ = Resolve-Path $PSScriptRoot\PowerBotMQ.psm1

$GetAdapterNames = { (Get-ChildItem $PowerBotAdapters -File -Filter *.psm1 | Select -Expand BaseName) -replace "Adapter$" }

function Restart-Adapter {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="Medium")]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({
            if(Get-ChildItem $PowerBotAdapters -File -Filter "${_}*.psm1") { 
                return $true 
            } else { 
                throw ("Invalid AdapterName. Valid names are " + (&$GetAdapterNames -join ", ")) 
            }
        })]
        [string[]]$Name
    )
    process {
        foreach($AdapterName in $Name) {
            foreach($Adapter in Get-ChildItem $PSScriptRoot\Adapters -File -Filter "${AdapterName}*.psm1") {

                $Job = Get-Job $Adapter.BaseName -ErrorAction SilentlyContinue -ErrorVariable ObjectNotFound
                if($ObjectNotFound -and $ObjectNotFound[0].CategoryInfo.Category -ne "ObjectNotFound") {
                    throw $ObjectNotFound[0]
                }
                if($Job.State -notin "Stopped","Failed") {
                    if($PSCmdlet.ShouldProcess( "Stopped the Job '$($Adapter.BaseName)'",
                                       "The '$($Adapter.BaseName)' job is $($Job.State). Stop it?",
                                       "Starting $($Adapter.BaseName) job" )) {
                        $Job | Stop-Job
                    }
                }

                Start-Job -Name $Adapter.BaseName -ScriptBlock {
                    param($PowerBotPath, $AdapterPath)
                    Import-Module $PowerBotPath, $AdapterPath
                    Start-Adapter
                } -ArgumentList $PowerBotMQ, $Adapter.FullName
            }
        }
    }
}

Microsoft.PowerShell.Core\Register-ArgumentCompleter -Command Start-Adapter -Parameter AdapterName -ScriptBlock $GetAdapterNames


Restart-Adapter *
