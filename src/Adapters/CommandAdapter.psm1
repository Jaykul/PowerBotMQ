#requires -Module PowerBotMQ
#requires -Module CodeFlow
#requires -Module Strings
# source the ThrowError function instead of using `throw`
. "$PSScriptRoot\..\ThrowError.ps1"

function New-ProxyFunction {
   param(
      [Parameter(ValueFromPipeline=$True)]
      [ValidateScript({$_ -is [System.Management.Automation.CommandInfo]})]
      $Command
   )
   process {
      $FullName = "{0}\{1}" -f $Command.ModuleName, $Command.Name
      $Pattern  = [regex]::escape($Command.Name)

      [System.Management.Automation.ProxyCommand]::Create($Command) -replace "${Pattern}", "${FullName}"
   }
}

function Start-Adapter {
    #.Synopsis
    #   Start this adapter (mandatory adapter cmdlet)
    [CmdletBinding()]
    param(
        # The Context to start this adapter for. Generally, the channel name that's common across networks.
        # Defaults to "PowerShell"
        $Context = "PowerShell",

        # The Name of this adapter.
        # Defaults to "PowerBot"
        [String]$Name = "PowerBot",
        
        # The Command Prefix (defaults to "!")
        [String]$CommandPrefix = "!",

        # The allowed commands for each role...
        [Hashtable]$RoleWhiteList
    )
    
    # Push the roles into the user roles module
    & (Get-Module UserRoles) { $Script:Roles = $Args } @Roles

    if($Reactions.Count -eq 0) {
        InitializeAdapter
    }

    $Script:PowerBotName = $Name
    Register-Receiver $Context
    $Character = $Null
    while($Character -ne "Q") {
        while(!$Host.UI.RawUI.KeyAvailable) {
            if($Message = Receive-Message -NotFromNetwork "Robot") {
                Write-Verbose "Receive-Message -NotFromNetwork Robot"
                $Message | Format-Table | Out-String | Write-Verbose
                
                if($Message.Message -join "`n" -match "^$CommandPrefix") {
                    $ScriptString = $Message.Message -join "`n" -replace "^$CommandPrefix" 
                } else {
                    continue
                }

                # The default role for authenticated users with no roles set is user
                # But even unauthenticated users get the Guest role, no matter what
                if($Message.AuthenticatedUser) {
                    $User = $Message | Get-Role
                    $Roles = $User.Roles
                } else {
                    $Roles = @("Guest")
                }
                

                # Figure out which modules the user is allowed to use.
                # Everyone gets access to the "Guest" commands
                $AllowedModule = @(
                    "PowerBotGuestCommands"
                    # They may get other roles ...
                    foreach($Role in $global:Roles) {
                        "PowerBot${Role}Commands"
                    }
                    # TODO: Hack to allow the owner from the console 
                    # if($From -eq $ConsoleUser) {
                    #    "PowerBotOwnerCommands"
                    # }
                ) | Select-Object -Unique

                # Use ResolveAlias to strip dissallowed commands out
                $AllowedCommands = (Get-Module $AllowedModule).ExportedCommands.Values | % { $_.ModuleName + '\' + $_.Name }
                $Script = Protect-Script -Script $ScriptString -AllowedModule $AllowedModule -AllowedVariable "Message" -WarningVariable warnings
                
                if(!$Script) {
                    if($Warnings) {
                        Send-Message -Context $Message.Context -NetworkFrom Robot -ChannelFrom "CommandAdapterWarning" -Type $Message.Type -Message "WARNING [$($Message.Network)\$($Message.Channel):$($Message.DisplayName)]: $($Warnings -join ' | ')" 
                    }
                }
                                
                if($Script) {
                    Write-Verbose "SCRIPT: $Script"
                    try {
                        Invoke-Expression $Script | 
                            Format-Csv -Width $MaxLength | 
                            Select-Object -First 8 | # Hard limit to the number of messages, no matter what.
                            Send-Message -Context $Message.Context -NetworkFrom Robot -ChannelFrom "CommandAdapter" -Type $Message.Type 
                    } catch {
                        Send-Message -Context $Message.Context -NetworkFrom Robot -ChannelFrom "CommandAdapterError" -Type $Message.Type -Message "ERROR [$($Message.Network)\$($Message.Channel):$($Message.DisplayName)]: $_" 
                        Write-Warning "EXCEPTION IN COMMAND ($Script): $_"
                    }
                }
            }
        }
        $Character = $Host.UI.RawUI.ReadKey().Character
    }
}

function InitializeAdapter {
    #.Synopsis
    #   Initialize the adapter (mandatory adapter cmdlet)
    [CmdletBinding()]
    param([Hashtable]$RoleWhiteList)

    ## For each role, we generate a new module, and import (nested) the modules and commands assigned to that role
    ## Then we import that dynamically generated module to the global scope so it can access the PowerBot module if it needs to
    foreach($Role in $RoleWhiteList.Keys) {
        Write-Host "Generating $Role Role Command Module" -Fore Cyan
        
        New-Module "PowerBot${Role}Commands" {
            param($Role, $RoleModules, $Force)
        
            foreach($module in $RoleModules.Keys) {
                # get only the whitelisted commands (supports wildcards)
                foreach($command in (Get-Module $module.split("\")[-1]).ExportedCommands.Values |
                    Where { 
                        $_.CommandType -ne "Alias" -and 
                        $(foreach($name in $RoleModules.$module) { $_.Name -like $name }) -Contains $True 
                    } 
                ) {
                    Set-Content "function:local:$($command.Name)" (New-ProxyFunction $command)
                }  
            }
        
            # There are a few special commands for Owners and "Everyone" (Users)
            if($Role -eq "Owner") 
            {
                # None of the commands from the IRC-only PowerBot made sense
                # And I can't think how to do this, because we're inside a Job...
                # TODO: add a restart-adapter command 
            } 
            if($Role -ne "User") {
                function Get-Command {
                    #.SYNOPSIS
                    #  Lists the special commands available to elevated users via the bot
                    param(
                        # A filter for the command name (allows wildcards)
                        [Parameter(Position=0,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
                        [String[]]$Name = "*"
                    )
                    process {
                        $ExecutionContext.SessionState.Module.ExportedCommands.Values | Where { $_.CommandType -ne "Alias"  -and $_.Name -like $Name } | Sort Name
                    }
                }
            } else {
                function Get-Alias {
                    #.SYNOPSIS
                    #  Lists the commands available via the bot
                    param(
                        # A filter for the command name (allows wildcards)
                        [Parameter(Position=0,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
                        [String[]]$Name = "*"
                    )
                    process {
                        Microsoft.PowerShell.Utility\Get-Alias -Definition $ExecutionContext.SessionState.Module.ExportedCommands.Values.Name -ErrorAction SilentlyContinue | Where { $_.Name -like $Name }
                    }
                }
        
                function Get-UserCommand {
                    #.SYNOPSIS
                    #  Lists the commands available via the bot to normal users
                    param(
                        # A filter for the command name (allows wildcards)
                        [Parameter(Position=0,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
                        [String[]]$Name = "*"
                    )
                    process {
                        @(Get-Module PowerBotGuestCommands, PowerBotUserCommands).ExportedCommands.Values | Where { $_.CommandType -ne "Alias"  -and $_.Name -like $Name  -and $_.Name -ne "Get-UserCommand"} | Sort Name
                    }
                }
                # Make sure Get-Command is available without prefix even for elevated users 
                Set-Alias Get-Command Get-UserCommand
                Export-ModuleMember -Function * -Alias Get-Command
            }
        } -Args ($Role, $RoleWhiteList[,$Role], $Force) | Import-Module -Global -Prefix $(if($Role -notmatch "User|Guest") { $Role } else {""})
    }
}

Export-ModuleMember -Function Start-Adapter