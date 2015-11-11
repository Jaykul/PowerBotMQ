#requires -Module PowerBotMQ
using namespace System.Management.Automation
Add-Type -Path "$PSScriptRoot\..\lib\Meebey.SmartIrc4net.dll"

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

function InitializeAdapter {
    #.Synopsis
    #   Initialize the adapter (internal initialization from start-adapter)
    [CmdletBinding()]
    param(
        # The unique name that connects all the Adapter jobs
        [Parameter(Mandatory, Position=0)]
        [string]$Context,

        # The network connection information, e.g.: irc://chat.freenode.net:8001/PowerBot
        [Parameter(Mandatory, Position=1)]
        [Uri]$Network,

        # The channels you want to connect to
        [Parameter(Mandatory)]
        [string]$Channel,

        # The credentials (if any) needed to connect
        [AllowNull()]
        [Credential()]
        [PSCredential]$Credential,

        # Nickname for the user
        [Parameter(Mandatory)]
        [string[]]$Nick,

        [Parameter(Mandatory)]
        [string]$RealName
    )
    end {

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

        Write-Verbose "InitializeAdapter -Context $Context -Network $($Network.Authority) -Channel $Channel -Credential $Credential -Nick $Nick -RealName $RealName"

        # This causes errors to show up in the console
        $script:client.Add_OnError( {Write-Error "Error $($_.ErrorMessage)"} )
        # This give us the option of seeing every line as verbose output
        # $script:client.Add_OnReadLine( {Write-Verbose "ReadLine $($_.Line)" -Verbose} )

        ## UserModeChange (this happens, among other things, when we first go online, so it's a good time to join channels)
        $script:client.Add_OnUserModeChange( {
            Write-Verbose "RfcJoin $Channel" -Verbose
            $script:client.RfcJoin( $Channel )
        } )

        ## FOR DEBUGGING: repeat every line as verbose output
        # $script:client.Add_OnReadLine( {Write-Verbose $_.Line} )

        # We handle commands on query (private) messages or on channel messages
        # $script:client.Add_OnQueryMessage( {Write-Verbose "QUERY: $($_ | Fl * |Out-String)" } )
        $script:client.Add_OnChannelMessage( {
            Write-Verbose "IRC1: $Context $($Network.Host)\$($_.Data.Channel) MESSAGE <$($_.Data.Nick)> $($_.Data.Message)"
            PowerBotMQ\Send-Message -Type "Message" -Context $Context -Channel $_.Data.Channel -Network "$($Network.Host)" -User $_.Data.Nick -Message $_.Data.Message
        } )

        $script:client.Add_OnChannelAction( {
            $Flag = [char][byte]1
            $Message = $_.Data.Message -replace "${Flag}ACTION (.*)${Flag}",'$1'
            Write-Verbose "IRC1: $Context $($Network.Host)\$($_.Data.Channel) ACTION <$($_.Data.Nick)> $Message"
            PowerBotMQ\Send-Message -Type "Action" -Context $Context -Channel $_.Data.Channel -Network "$($Network.Host)" -User $_.Data.Nick -Message $Message
        } )

        Unregister-Event -SourceIdentifier IrcHandler -ErrorAction SilentlyContinue
        $null = Register-ObjectEvent $client OnChannelMessage -SourceIdentifier IrcHandler -Action {
            $Client = $Event.SourceArgs[0]
            $Data = $EventArgs.Data

            $Context = $Event.MessageData.Context
            $Network = $Event.MessageData.Network
            Write-Verbose "IRC2: $Context $Host\$($Data.Channel) <$($Data.Nick)> $($Data.Message)"
            PowerBotMQ\Send-Message -Type "Message" -Context $Context -Channel $Channel -Network $Network -User $Data.Nick -Message $Data.Message
        } -MessageData @{
            Context = $Context
            Network = "$($Network.Host)"
        }

        # Connect to the server
        $script:client.Connect($Network.Host, $Network.Port)

        # Login to the server
        if($Credential) {
            $script:client.Login($nick, $realname, 0, $Credential.GetNetworkCredential().UserName, $Credential.GetNetworkCredential().Password)
        } else {
            $script:client.Login($nick, $realname, 0, $nick[0])
        }


        return $script:client
    }
}

function Start-Adapter {
    #.Synopsis
    #   Start this adapter (mandatory adapter cmdlet)
    [CmdletBinding()]
    param(
        # The unique name that connects all the Adapter jobs
        [Parameter(Mandatory, Position=0)]
        [string]$Context,

        # The network connection information, e.g.: irc://chat.freenode.net:8001/PowerBot
        [Parameter(Mandatory, Position=1)]
        [Uri]$Network,

        # The channels you want to connect to
        [string]$Channel = $( $Network.Segments.Trim('/').Split(',',[StringSplitOptions]::RemoveEmptyEntries) | ? { $_ } ),

        # The credentials (if any) needed to connect
        [AllowNull()]
        [Credential()]
        [PSCredential]$Credential = $(if($Network.UserInfo){$Network.UserInfo}),

        # Nickname for the user
        [string[]]$Nick = @("PowerBot", "PowerBotMQ"),

        [string]$RealName = "$Nick PowerBot <http://GitHub.com/Jaykul/PowerBotMQ>"
    )
    $Channel = $Channel -replace "^#*","#"

    Register-Receiver $Context
    Write-Verbose "Start-Adapter -Context $Context -Network $Network -Channel $Channel -Credential $Credential -Nick $Nick -RealName $RealName"
    if(!$Script:Client) {
        $Script:Client = InitializeAdapter -Context $Context -Network $Network -Channel $Channel -Credential $Credential -Nick $Nick -RealName $RealName
    }

    $Character = $Null
    while($Character -ne "Q") {
        while(!$Host.UI.RawUI.KeyAvailable) {

            $script:client.Listen($false)
            foreach($envelope in PowerBotMQ\Receive-Message -NotFromNetwork $Network.Host -NotFromChannel $Channel -TimeoutMilliSeconds 100) {
                Write-Debug ($envelope.Network + " not $($Network.Host) " + $envelope.Channel + " not ($Channel) " + $envelope.Message )
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

Export-ModuleMember -Function "Send-Message", "Start-Adapter"