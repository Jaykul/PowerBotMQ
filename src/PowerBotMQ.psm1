## This script requires Meebey.SmartIrc4net.dll which you can get as part of SmartIrc4net
## http://voxel.dl.sourceforge.net/sourceforge/smartirc4net/SmartIrc4net-0.4.0.bin.tar.bz2
## And the docs are at http://smartirc4net.meebey.net/docs/0.4.0/html/
############################################################################################
## You should configure the PrivateData in the PowerBot.psd1 file
############################################################################################
## You should really configure the PrivateData in the PowerBot.psd1 file
############################################################################################
## You need to configure the PrivateData in the PowerBot.psd1 file
############################################################################################

## Set some default ParametersValues for inside PowerBot
$PSDefaultParameterValues."Out-String:Stream" = $true
$PSDefaultParameterValues."Format-Table:Auto" = $true

## Store the PSScriptRoot
$global:PowerBotScriptRoot = Get-Variable PSScriptRoot -ErrorAction SilentlyContinue | ForEach-Object { $_.Value }
if(!$global:PowerBotScriptRoot) {
    $global:PowerBotScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}

$AsyncIO = (Join-Path $PowerBotScriptRoot "..\lib\AsyncIO.dll")
$NetMQ = (Join-Path $PowerBotScriptRoot "..\lib\NetMQ.dll")
$PowerBot = (Join-Path $PowerBotScriptRoot "..\lib\PowerBot.dll")

Add-Type -Path $NetMQ, $AsyncIO, $PowerBot

$PowerBotBridgePublisher   = "tcp://127.0.0.1:50005"
$PowerBotBridgeSubscriber  = "tcp://127.0.0.1:50015"

function Register-Receiver {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory=$false)]
		[AllowEmptyString()]
		[string]$Filter=""
	)
	# Connect our subscriber to the bridge publisher
	Write-Verbose "Connecting Subscriber to $PowerBotBridgePublisher"
	$script:Receiver = $PowerBotContext.CreateSubscriberSocket()
	$script:Receiver.Connect($PowerBotBridgePublisher);
	Write-Verbose "Subscribing with filter $Filter"
	$script:Receiver.Subscribe($Filter)
}

function Register-Sender {
	[CmdletBinding()]
	param()
	# Connect our publisher to the bridge subscriber
	Write-Verbose "Connecting Publisher to $PowerBotBridgeSubscriber"
	$script:Sender = $PowerBotContext.CreatePublisherSocket()
	$script:Sender.Connect($PowerBotBridgeSubscriber);
}

function Send-Message {
	[CmdletBinding()]
	param(
		[PoshCode.MessageType]
		$Type = [PoshCode.MessageType]::Message,
	
		[Parameter(Mandatory=$true, Position=0)]
		$Context,
	
		[Parameter(Mandatory=$true, Position=1)]
		$ChannelFrom,
	
		[Parameter(Position=2)]
		$NetworkFrom = "Robot",

		[Parameter(Position=3)]
		$UserFrom = $Script:PowerBotName,

		[Parameter(Mandatory=$true, Position=4, ValueFromPipelineByPropertyName=$true, ValueFromPipeline=$true, ValueFromRemainingArguments=$true)]
		[string[]]$Message
	)
	begin {
		if(!(Test-Path Variable:Script:Sender)) {
			Register-Sender
		}
	}

	process {
		$count = $Message.Length - 1

		Write-Verbose "Sending $($Message.Length)-line message of type $Type from ${ChannelFrom}#${AdapterFrom}#${UserFrom}: $Message"
		[NetMQ.OutgoingSocketExtensions]::Send( $script:Sender, $Context, [System.Text.Encoding]::UTF8, $false, $true )
		[NetMQ.OutgoingSocketExtensions]::Send( $script:Sender, $NetworkFrom, [System.Text.Encoding]::UTF8, $false, $true )
		[NetMQ.OutgoingSocketExtensions]::Send( $script:Sender, $ChannelFrom, [System.Text.Encoding]::UTF8, $false, $true )
		[NetMQ.OutgoingSocketExtensions]::Send( $script:Sender, $UserFrom, [System.Text.Encoding]::UTF8, $false, $true )
		[NetMQ.OutgoingSocketExtensions]::Send( $script:Sender, $Type, [System.Text.Encoding]::UTF8, $false, $true )

		for ($i = 0; $i -le $count; $i++) {
			Write-Verbose "Sending Part $i of ${count}: $('' + $Message[$i])"
			[NetMQ.OutgoingSocketExtensions]::Send( $script:Sender, ("" + $Message[$i]), [System.Text.Encoding]::UTF8, $false, ($i -lt $count))
		}
	}
}

function Receive-Message {
	[CmdletBinding()]
	param(
		[String]$NotFromChannel = "",
		[String]$NotFromNetwork = "",
	
		[Parameter(Mandatory=$false)]
		[int]$TimeoutMilliSeconds = 10000
	)
	begin {
		if(!(Test-Path Variable:Script:Receiver)) {
            $exception = New-Object System.InvalidOperationException "No Receiver registered. You must call Register-Receiver!"
            $errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, "ReceiverNotSubscribed", "InvalidOperation", $ExceptionObject    
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
	}
	end {
		$Message = New-Object System.Collections.Generic.List[String] 6
		if([NetMQ.ReceivingSocketExtensions]::TryReceiveMultipartStrings(	$script:Receiver, 
			[TimeSpan]::FromMilliseconds($TimeoutMilliSeconds),
			[System.Text.Encoding]::UTF8,
			[ref]$Message,
			6)
		) {
			Write-Verbose "'$NotFromChannel' -ne '$($Message[2])' -and '$NotFromNetwork' -ne '$($Message[1])'"
			if($NotFromChannel -ne $Message[2] -or $NotFromNetwork -ne $Message[1]) {
				[PoshCode.Envelope]@{
					Context = $Message[0]
					Network = $Message[1]
					Channel = $Message[2]
					User = $Message[3]
					Type = $Message[4]
					Message = $Message | Select -Skip 5
				}
			}
		}
	}
}

function Start-ZeroMqHub {
    [CmdletBinding()]
    param($Name="PubSubProxy")
    Write-Verbose "[PoshCode.ZeroMqHub]::new($PowerBotBridgePublisher, $PowerBotBridgeSubscriber, 10000)"
    $Proxy = [PoshCode.ZeroMqHub]::new($PowerBotBridgePublisher, $PowerBotBridgeSubscriber, 10000)
    # $Proxy.Name = "PubSubProxy"
    $Proxy.Start()

    if ($Proxy) {
        $PSCmdlet.JobRepository.Add($Proxy)
        Write-Output $Proxy
    }
}

if(!(Test-Path Variable:Script:PowerBotContext) ){
	$Script:PowerBotContext = [NetMQ.NetMQContext]::Create()
}


Export-ModuleMember -Function Register-Receiver, Register-Sender, Send-Message, Receive-Message, Start-ZeroMqHub
