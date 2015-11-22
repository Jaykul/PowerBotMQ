# source the ThrowError function instead of using `throw`
. "$PSScriptRoot\ThrowError.ps1"

## Set some default ParametersValues for inside PowerBot
$PSDefaultParameterValues."Out-String:Stream" = $true
$PSDefaultParameterValues."Format-Table:Auto" = $true

## Store the PSScriptRoot
$global:PowerBotScriptRoot = Get-Variable PSScriptRoot -ErrorAction SilentlyContinue | ForEach-Object { $_.Value }
if(!$global:PowerBotScriptRoot) {
    $global:PowerBotScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}

if(!$global:BotStoragePath) {
    trap { 
        [string]$global:BotStoragePath = Join-Path $PowerBotScriptRoot "Data"
        continue
    }
    [string]$global:BotStoragePath = Get-StoragePath -CompanyName "HuddledMasses.org" -Name "PowerBot"
}
[string]$script:LogFolder = Join-Path $global:BotStoragePath Logs
if(!(Test-Path $script:LogFolder)) {
    $script:LogFolder = mkdir $script:LogFolder -force
}    

$NetMQ    = Join-Path $PowerBotScriptRoot "lib\NetMQ.dll"
$AsyncIO  = Join-Path $PowerBotScriptRoot "lib\AsyncIO.dll"
$PowerBot = Join-Path $PowerBotScriptRoot "lib\PowerBot.dll"

Add-Type -Path  $NetMQ, $AsyncIO, $PowerBot

$PowerBotBridgePublisher   = "tcp://127.0.0.1:50005"
$PowerBotBridgeSubscriber  = "tcp://127.0.0.1:50015"

function Register-Receiver {
	#.Synopsis
	#	Register a Receiver to the PowerBot Bridge
	#.Example
	#	Register-Receiver "PowerShell"
	#	Registers a receiver for PowerShell messages
	[CmdletBinding()]
	param(
		# The Context filter for this receiver, e.g. a channel name that's common across networks
		[Parameter(Mandatory=$false)]
		[AllowEmptyString()]
		[string]$Filter=""
	)
	# Connect our subscriber to the bridge publisher
	Write-Verbose "Connecting a subscriber to $PowerBotBridgePublisher"
	$script:Receiver = $PowerBotContext.CreateSubscriberSocket()
	$script:Receiver.Connect($PowerBotBridgePublisher);
	Write-Verbose "Subscribing with filter $Filter"
	$script:Receiver.Subscribe($Filter)
}

function Register-Sender {
	#.Synopsis
	#	Register a Sender to the PowerBot Bridge
	[CmdletBinding()]
	param()
	# Connect our publisher to the bridge subscriber
	Write-Verbose "Connecting Publisher to $PowerBotBridgeSubscriber"
	$script:Sender = $PowerBotContext.CreatePublisherSocket()
	$script:Sender.Connect($PowerBotBridgeSubscriber);
}

function Send-Message {
	#.Synopsis
	#	Send a message to the PowerBot Bridge
	#.Example
	#   Send-Message -Context $Context -Channel $Channel -Network $Network -User $User -Message "Hello World"
	[CmdletBinding()]
	param(
		# The Context for the message (a channel name that's common across networks)
		[Parameter(Mandatory=$true, Position=0)]
		$Context,

		# The Network the message came from (defaults to "Robot")
		[Parameter(Position=2)]
		[Alias("NetworkFrom")]
		$Network = "Robot",

		# The Channel the message came from
		[Parameter(Mandatory=$true, Position=1)]
		[Alias("ChannelFrom")]
		$Channel,

		# The User the message came from (defaults to the bot name)
		[Parameter(Position=3)]
		$DisplayName = "PowerBot",
		
		# A context\adapter unique persistent identifier for the user
		# If an adapter can't guarantee this will be persistent, it should be blank
		[Parameter()]
		[AllowEmptyString()][AllowNull()]
		$AuthenticatedUser = "",

		# The timestamp the message was received from the user
		[Parameter()]
		$TimeStamp = [DateTimeOffset]::Now,

		# The Message Type
		[PoshCode.MessageType]
		$Type = [PoshCode.MessageType]::Message,

		# The message
		[Parameter(Mandatory=$true, Position=4, ValueFromPipelineByPropertyName=$true, ValueFromPipeline=$true, ValueFromRemainingArguments=$true)]
		[string[]]$Message
	)
	begin {
        $LogFile = Join-Path $script:LogFolder ("{0:yyyy-MM-dd}.log" -f [DateTimeOffset]::Now)
		if(!(Test-Path Variable:Script:Sender)) {
			Register-Sender
		}
	}
	process {
		# Context    Network              Channel DisplayName AuthenticatedUser TimeStamp             Type    Message
		# -------    -------              ------- ----------- ----------------- ---------             ----    -------
		# PowerShell powershell.slack.com testing jaykul      U03MS9QL0         11/19/2015 2:07:34 AM Message {Hmmm...}
        $Envelope = [PoshCode.Envelope]$MyInvocation.ParameterValues
        $Envelope | Export-Csv -Path $LogFile -Append        
		$Script:Sender.SendMessage($Envelope)
	}
}

function Receive-Message {
	#.Synopsis
	#	Receive a message (if there is one) from the PowerBot Bridge
	[CmdletBinding()]
	[OutputType([PoshCode.Envelope])]
	param(
		# Exclusion filter for channels (normally you pass your own channel)
		[String]$NotFromChannel = "",

		# Exclusion filter for networks (normally you pass your own network)
		[String]$NotFromNetwork = "",

		# Timeout (defaults to 10,000: 10 seconds)
		# If no message comes within this time, the cmdlet returns without output
		[Parameter(Mandatory=$false)]
		[int]$TimeoutMilliSeconds = 10000
	)
	begin {
		if(!(Test-Path Variable:Script:Receiver)) {
            ThrowError $PSCmdlet System.InvalidOperationException "No Receiver registered. You must call Register-Receiver!" $Receiver "ReceiverNotSubscribed" "InvalidOperation"
        }
	}
	end {
		$Message = New-Object System.Collections.Generic.List[String] 8
		if([NetMQ.ReceivingSocketExtensions]::TryReceiveMultipartStrings(
            $script:Receiver,
			[TimeSpan]::FromMilliseconds($TimeoutMilliSeconds),
			[System.Text.Encoding]::UTF8,
			[ref]$Message,
			8)
		) {
			Write-Verbose "'$NotFromChannel' -ne '$($Message[2])' -and '$NotFromNetwork' -ne '$($Message[1])'"
            # If they didn't black list a specific channel, and the network matches, skip it
            if([string]::IsNullOrEmpty($NotFromChannel)) {
                if($NotFromNetwork -eq $Message[1]) { return }
            
            # If they didn't black list a specific network, and the channel matches, skip it
            } elseif([string]::IsNullOrEmpty($NotFromNetwork)) {
                if($NotFromChannel -eq $Message[2]) { return }
            # If they specified both, then both should match
            } else {
                if($NotFromNetwork -eq $Message[1] -and $NotFromChannel -eq $Message[2]) { return }
            }
            
            [PoshCode.Envelope]@{
                Context = $Message[0]
                Network = $Message[1]
                Channel = $Message[2]
                DisplayName = $Message[3]
                AuthenticatedUser = $Message[4]
                TimeStamp = $Message[5] 
                Type = $Message[6]
                Message = $Message | Select -Skip 7
            }
		}
	}
}

function Start-ZeroMqHub {
	#.Synopsis
	# 	Start the PowerBot Bridge PoshCode.ZeroMqHub as a job
    [CmdletBinding()]
	[OutputType([PoshCode.ZeroMqHub])]
    param(
		# The name of this bridge (currently ignored)
		$Name="PubSubProxy"
	)
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

Update-TypeData -TypeName System.Management.Automation.InvocationInfo -MemberName ParameterValues -MemberType ScriptProperty -Value {
    $results = @{}
    foreach($parameter in $this.MyCommand.Parameters.GetEnumerator()) {
        try {
            $key = $parameter.Key
            if($value = Get-Variable -Name $key -Scope 1 -ValueOnly -ErrorAction Ignore) {
                $results.$key = $value
            }
        } finally {}
    }
    return $results
} -Force

Update-TypeData -TypeName NetMQ.Sockets.PublisherSocket -MemberName SendMessage -MemberType ScriptMethod -Value {
	param([PoshCode.Envelope]$Envelope) 

	$count = $Envelope.Message.Length - 1

	Write-Verbose "Sending $($Envelope.Message.Length)-line message of type $($Envelope.Type) from $($Envelope.Network)#$($Envelope.Channel)#$($Envelope.DisplayName): $($Envelope.Message)"
	[NetMQ.OutgoingSocketExtensions]::Send( $this, $Envelope.Context,           [System.Text.Encoding]::UTF8, $false, $true )
	[NetMQ.OutgoingSocketExtensions]::Send( $this, $Envelope.Network,       	[System.Text.Encoding]::UTF8, $false, $true )
	[NetMQ.OutgoingSocketExtensions]::Send( $this, $Envelope.Channel,       	[System.Text.Encoding]::UTF8, $false, $true )
	[NetMQ.OutgoingSocketExtensions]::Send( $this, $Envelope.DisplayName,       [System.Text.Encoding]::UTF8, $false, $true )
	[NetMQ.OutgoingSocketExtensions]::Send( $this, $Envelope.AuthenticatedUser, [System.Text.Encoding]::UTF8, $false, $true )
	[NetMQ.OutgoingSocketExtensions]::Send( $this, $Envelope.TimeStamp,         [System.Text.Encoding]::UTF8, $false, $true )
	[NetMQ.OutgoingSocketExtensions]::Send( $this, $Envelope.Type,              [System.Text.Encoding]::UTF8, $false, $true )

	for ($i = 0; $i -le $count; $i++) {
		Write-Verbose "Sending Part $i of ${count}: $('' + $Envelope.Message[$i])"
		[NetMQ.OutgoingSocketExtensions]::Send( $this, ("" + $Envelope.Message[$i]), [System.Text.Encoding]::UTF8, $false, ($i -lt $count))
	}
} -Force

Export-ModuleMember -Function Register-Receiver, Register-Sender, Send-Message, Receive-Message, Start-ZeroMqHub
