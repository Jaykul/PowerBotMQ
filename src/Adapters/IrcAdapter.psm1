#requires -Module PowerBotMQ
Add-Type -Path "$PSScriptRoot\..\lib\Meebey.SmartIrc4net.dll"

[String[]]$Nick = "ShellE", "Shell_E"
$RealName = "$Nick PowerBot <http://GitHub.com/Jaykul/PowerBot>"
$Network = "chat.freenode.net"
$Channel = "#PowerBot"
$Context = "#PowerShell"
$Port = 8001

Register-Receiver $Context

function Send-Message {
    #.Synopsis
    #  Sends a message to the IRC server
    [CmdletBinding()]
    param(
        # Who to send the message to (a channel or nickname)
        [Parameter(Position=0)]
        [String]$To,

        # The message to send
        [Parameter(Position=1, ValueFromPipeline=$true)]
        [String]$Message,

        # How to send the message: Message, Reply, Topic, Action
        [PoshCode.MessageType]$Type = "Message"
    )
    process {
        Write-Verbose "Send-IrcMessage $Message"

        if($Message.Contains("`n")) {
            $Message.Trim().Split("`n") | Send-Message -To $To -Type $Type
        } else {
            $Message = $Message.Trim()
            Write-Verbose "SendMessage( '$Type', '$To', '$Message' )"
            $script:client.SendMessage("$Type", $To, $Message)
        }
    }
}

function Initialize-Adapter {
    $script:client = New-Object Meebey.SmartIrc4net.IrcClient -Property @{
        # TODO: Expose these options to configuration
        AutoRejoin = $true
        AutoRejoinOnKick = $false
        AutoRelogin = $true
        AutoReconnect = $true
        AutoRetry = $true
        AutoRetryDelay = 60
        SendDelay = 400
        Encoding = [Text.Encoding]::UTF8
        # SmartIrc will track channels for us
        ActiveChannelSyncing = $true
    }

    # This causes errors to show up in the console
    $script:client.Add_OnError( {Write-Error "Error $($_.ErrorMessage)"} )
    # This give us the option of seeing every line as verbose output
    # $script:client.Add_OnReadLine( {Write-Verbose "ReadLine $($_.Line)" -Verbose} )

    ## UserModeChange (this happens, among other things, when we first go online, so it's a good time to join channels)
    $script:client.Add_OnUserModeChange( {Write-Verbose "RfcJoin $Channel" -Verbose; $script:client.RfcJoin( $Channel ) } )

    # We handle commands on query (private) messages or on channel messages
    # $script:client.Add_OnQueryMessage( {Write-Verbose "QUERY: $($_ | Fl * |Out-String)" } )
    $script:client.Add_OnChannelMessage( {
        Write-Verbose "IRC1: $Context $Network\$($_.Data.Channel) MESSAGE <$($_.Data.Nick)> $($_.Data.Message)"
        PowerBotMQ\Send-Message -Type "Message" -Context $Context -Channel $_.Data.Channel -Network $Network -User $_.Data.Nick -Message $_.Data.Message
    } )

    $script:client.Add_OnChannelAction( {
        $Flag = [char][byte]1
        $Message = $_.Data.Message -replace "${Flag}ACTION (.*)${Flag}",'$1'
        Write-Verbose "IRC1: $Context $Network\$($_.Data.Channel) ACTION <$($_.Data.Nick)> $Message"
        PowerBotMQ\Send-Message -Type "Action" -Context $Context -Channel $_.Data.Channel -Network $Network -User $_.Data.Nick -Message $Message
    } )

    Unregister-Event -SourceIdentifier IrcHandler -ErrorAction SilentlyContinue
    $null = Register-ObjectEvent $client OnChannelMessage -SourceIdentifier IrcHandler -Action {
        $Client = $Event.SourceArgs[0]
        $Data = $EventArgs.Data

        $Context = $Event.MessageData.Context
        $Network = $Event.MessageData.Network
        Write-Verbose "IRC2: $Context $Network\$($Data.Channel) <$($Data.Nick)> $($Data.Message)"
        PowerBotMQ\Send-Message -Type "Message" -Context $Context -Channel $Channel -Network $Network -User $Data.Nick -Message $Data.Message
    } -MessageData @{
        Context = $Context
        Network = $Network
    }

    return $script:client
}

function Start-Adapter {
    if(!$Script:Client) {
        $Script:Client = IrcAdapter\Initialize-Adapter
    }
    # Connect to the server
    $script:client.Connect($Network, $Port)
    # Login to the server
    if($Password) {
        $script:client.Login(([string[]]$nick), $realname, 0, @($nick)[0], $password)
    } else {
        $script:client.Login(([string[]]$nick), $realname, 0, @($nick)[0])
    }

    $Character = $Null
    while($Character -ne "Q") {
        while(!$Host.UI.RawUI.KeyAvailable) {
          
            $script:client.Listen($false)  
            foreach($envelope in PowerBotMQ\Receive-Message -NotFromNetwork $Network -NotFromChannel $Channel -TimeoutMilliSeconds 100) {
                Write-Debug ($envelope.Network + " not ($Network) " + $envelope.Channel + " not ($Channel) " + $envelope.Message )
                foreach($Message in $envelope.Message) {
                    if($Envelope.Network -eq "Robot") {
                        IrcAdapter\Send-Message -To $Channel -Type $envelope.Type -Message $Message
                    } else {
                        IrcAdapter\Send-Message -To $Channel -Type $envelope.Type -Message ("<{0}> {1}" -f ($envelope.User -replace "^(.)", "`$1$([char]0x200C)"), $Message)
                    }
                }
            }
      
        }
        $Character = $Host.UI.RawUI.ReadKey().Character
    }
}

