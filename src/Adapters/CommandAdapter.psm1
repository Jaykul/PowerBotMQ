#requires -Module PowerBotMQ
#requires -Module CodeFlow
#requires -Module Strings
# source the ThrowError function instead of using `throw`
. "$PSScriptRoot\..\ThrowError.ps1"

function global:New-ProxyFunction {
   param(
      [Parameter(ValueFromPipeline=$True)]
      [ValidateScript({$_ -is [System.Management.Automation.CommandInfo]})]
      $Command
   )
   process {
      $FullName = "{0}\{1}" -f $Command.ModuleName, $Command.Name
      $Pattern  = "(?:" + [regex]::escape($Command.ModuleName) + "\\)?" + [regex]::escape($Command.Name)

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
    
    InitializeAdapter $RoleWhiteList

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
                    # In the modules, I want the roles capitalized for legibility
                    $Roles = $User.Roles | ForEach { $_[0].ToString().ToUpper() + $_.SubString(1) }
                } else {
                    $Roles = @("Guest") 
                }
                Write-Verbose "Executing from roles $($Roles -join ', ') the script: $ScriptString"

                # Figure out which modules the user is allowed to use.
                # Everyone gets access to the "Guest" commands
                $AllowedModules = @(
                    "PowerBotGuestCommands"
                    # They may get other roles ...
                    foreach($Role in $Roles) {
                        "PowerBot${Role}Commands"
                    }
                    # TODO: Hack to allow the owner from the console 
                    # if($From -eq $ConsoleUser) {
                    #    "PowerBotOwnerCommands"
                    # }
                ) | Select-Object -Unique

                # Use ResolveAlias to strip dissallowed commands out
                $AllowedCommands = (Get-Module $AllowedModules).ExportedCommands.Values | % { $_.ModuleName + '\' + $_.Name }
                $Script = Protect-Script -Script $ScriptString -AllowedModule $AllowedModules -AllowedVariable "Message" -WarningVariable warnings
                
                Write-Verbose "AllowedModules ($AllowedModules)`n$(Get-Module $AllowedModules | Out-String)"
                if(!$Script) {
                    if($Warnings) {
                        Send-Message -Context $Message.Context -NetworkFrom Robot -ChannelFrom "CommandAdapterWarning" -Type $Message.Type -Message "WARNING [$($Message.Network)\$($Message.Channel):$($Message.DisplayName)]: $($Warnings -join ' | ')"
                    }
                }
                else {
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

    Write-Verbose "WhiteList:`n$(($RoleWhiteList | Out-String -Stream) -replace "\s+$" -join "`n")`n$(($RoleWhiteList.Values | Out-String -Stream) -replace "\s+$" -join "`n")"

    ## For each role, we generate a new module, and import (nested) the modules and commands assigned to that role
    ## Then we import that dynamically generated module to the global scope so that Resolve-Alias can see it.
    foreach($Role in $RoleWhiteList.Keys) {
        Write-Verbose "Generating $Role Role Module"

        # Make sure the modules are available
        foreach($module in $RoleWhiteList[$Role].Keys) {
            if(!(Get-Module ($module.Split("\")[-1]))) { 
                Import-Module $module -Scope Global
            }
            # Write-Verbose "Get-Module $($module.Split('\')[-1])`n$((Get-Module ($module.Split("\")[-1]) | Out-String -Stream) -replace "\s+$" -join "`n")"
        }
        
        New-Module "PowerBot${Role}Commands" {
            param($Role, $WhiteList, $Force)
        
            Write-Verbose "PowerBot${Role}Commands SubModules: $($WhiteList.Keys -join ', ')"
            foreach($module in $WhiteList.Keys) {
                Write-Verbose "WhiteList ${module}: $($WhiteList[$module] -join ', ')"
                    
                # get only the whitelisted commands (supports wildcards)
                foreach($command in (Get-Module ($module.split("\")[-1])).ExportedCommands.Values |
                    Where {
                        $_.CommandType -ne "Alias" -and 
                        $(foreach($name in $WhiteList[$module]) { $_.Name -like $name }) -Contains $True 
                    } 
                ) {
                    Write-Verbose "Generating $Role Role Command $(($command | Out-String -Stream) -replace "\s+$" -join "`n")"
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
                                
                function Get-Help {
                    #.FORWARDHELPTARGETNAME Microsoft.PowerShell.Core\Get-Help
                    #.FORWARDHELPCATEGORY Cmdlet
                    [CmdletBinding(DefaultParameterSetName='AllUsersView')]
                    param(
                        [Parameter(Position=0, ValueFromPipelineByPropertyName=$true, ValueFromRemainingArguments=$true)]
                        [System.String]
                        ${Name},
                        
                        [System.String]
                        ${Path},
                
                        [System.String[]]
                        ${Category},
                
                        [System.String[]]
                        ${Component},
                
                        [System.String[]]
                        ${Functionality},
                
                        [System.String[]]
                        ${Role},
                
                        [Parameter(ParameterSetName='DetailedView')]
                        [Switch]
                        ${Detailed},
                
                        [Parameter(ParameterSetName='Full')]
                        [Switch]
                        ${Full},
                
                        [Parameter(ParameterSetName='Examples')]
                        [Switch]
                        ${Examples},
                
                        [Parameter(ParameterSetName='Parameters')]
                        [System.String]
                        ${Parameter}
                    )
                    begin
                    {
                        if(!$Global:PowerBotHelpNames) {
                            $Global:PowerBotHelpNames = Microsoft.PowerShell.Core\Get-Help * | Select-Object -Expand Name
                        }
                    
                        function Write-BotHelp {
                            [CmdletBinding()]
                            param(
                                [Parameter(Position=0,ValueFromPipelineByPropertyName=$true)]
                                [String]$Name,
                    
                                [Parameter(ValueFromPipeline=$true)]
                                [PSObject]$Help
                            )
                            begin {
                                $helps = @()
                                Write-Verbose "Name: $Name    Help: $Help"
                                if($Help) { $helps += @($Help) }
                            }
                            process {
                                if(!$Name) {
                                "Displays information about Windows PowerShell commands and concepts. To get help for a cmdlet, type: Get-Help [cmdlet-name].`nIf you want information about bot commands, try Get-Command."
                                }
                                Write-Verbose "PROCESS $Help"
                                if($Help) { $helps += @($Help) }
                            }
                            end {
                                Write-Verbose "END $($Helps.Count)"
                                if($Name) {
                                    if($helps) {
                                        if($helps.Count -eq 1) {
                                            if($uri = $helps[0].RelatedLinks.navigationLink | Select -Expand uri) {
                                                $uri = "Full help online: " + $uri
                                            }
                                            $syntax = @(($helps[0].Syntax | Out-String -width 1000 -Stream).Trim().Split("`n",4,"RemoveEmptyEntries"))
                                            if($syntax.Count -gt 4){ $uri = "... and more. " + $uri } 
                                            @( $helps[0].Synopsis, $syntax[0..3], $uri )
                                        } else {
                                            $commands = @( Microsoft.PowerShell.Core\Get-Command "*$Name" | Where-Object { $_.ModuleName -ne $PSCmdlet.MyInvocation.MyCommand.ModuleName } )
                                            switch($commands.Count) {
                                                1 {
                                                    $helps = @( $helps | Where-Object { $_.ModuleName -eq $commands[0].ModuleName } | Select -First 1 )
                                                    if($uri = $helps[0].RelatedLinks.navigationLink | Select -Expand uri) {
                                                        $uri = "Full help online: " + $uri
                                                    }
                                                    $syntax = @(($helps[0].Syntax | Out-String -width 1000 -Stream).Trim().Split("`n",4,"RemoveEmptyEntries"))
                                                    if($syntax.Count -gt 4){ $uri = "... and more. " + $uri } 
                                                    @( $helps[0].Synopsis, $syntax[0..3], $uri )
                                                }
                                                2 {
                                                    $h1,$h2 = Microsoft.PowerShell.Core\Get-Command "*$Name" | % { if($_.ModuleName) { "{0}\{1}" -f $_.ModuleName,$_.Name } else { $_.Name } }
                                                    "You're going to need to be more specific, I know about $h1 and $h2"
                                                }
                                                3 {
                                                    $h1,$h2,$h3 = Microsoft.PowerShell.Core\Get-Command "*$Name" | % { if($_.ModuleName) { "{0}\{1}" -f $_.ModuleName,$_.Name } else { $_.Name } }
                                                    "You're going to need to be more specific, I know about $h1, $h2, and $h3"
                                                }
                                                default {
                                                    $h1,$h2,$h3 = Microsoft.PowerShell.Core\Get-Command "*$Name" | Select-Object -First 2 -Last 1 | % { if($_.ModuleName) {  "{0}\{1}" -f $_.ModuleName,$_.Name } else { $_.Name } }
                                                    "You're going to need to be more specific, I know about $($helps.Count): $h1, $h2, ... and even $h3"
                                                }
                                            }
                                        }
                                    } else {
                                        "There was no help for '$Name', sorry.  I probably don't have the right module available."
                                    }
                                }
                            }
                        }
                    
                        $outBuffer = $null
                        if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer) -and $outBuffer -gt 1024)
                        {
                            $PSBoundParameters['OutBuffer'] = 1024
                        }
                        foreach($k in $PSBoundParameters.Keys) {
                            Write-Host "$k : $($PSBoundParameters[$k])" -fore green
                        }
                        try {
                            if($Name -and ($Global:PowerBotHelpNames -NotContains (Split-Path $Name -Leaf))) {
                                Write-Output "I couldn't find the help file for '$Name', sorry.  I probably don't have the right module available."
                                return
                            }
                            if(!$Name) {
                                Write-Output "Get-Help Displays information about PowerShell commands. You must specify a command name."
                                return
                            }
                    
                            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCmdlet('Microsoft.PowerShell.Core\Get-Help')
                            Write-Host $(($wrappedCmd | Out-String -Stream) -replace "\s+$" -join "`n")
                            # $wrappedCmd = Microsoft.PowerShell.Core\Get-Command Microsoft.PowerShell.Core\Get-Help -Type Cmdlet
                            $scriptCmd = {& $wrappedCmd @PSBoundParameters -ErrorAction Stop | Select-Object @{n="Name";e={Split-Path -Leaf $_.Name}}, Synopsis, Syntax, ModuleName, RelatedLinks | Write-BotHelp }
                            Write-Host $(($scriptCmd | Out-String -Stream) -replace "\s+$" -join "`n")
                            $steppablePipeline = $scriptCmd.GetSteppablePipeline($MyInvocation.CommandOrigin)
                        
                        } catch [Microsoft.PowerShell.Commands.HelpNotFoundException],[System.Management.Automation.CommandNotFoundException] {
                            Write-Host "Exception:" $_.GetType().FullName -fore cyan
                            Write-Output "$($_.Message)  `n`nI probably don't have the right module available."
                            break
                        }
                    
                        $steppablePipeline.Begin($PSCmdlet)
                    }
                    process
                    {
                        try {
                            if($Global:PowerBotHelpNames -Contains $Name) {
                                $steppablePipeline.Process($_) 
                            } elseif($steppablePipeline) {
                                Write-Output "I couldn't find the help for '$Name', sorry.  I probably don't have the right module available."
                                return
                            }
                        } catch [Microsoft.PowerShell.Commands.HelpNotFoundException],[System.Management.Automation.CommandNotFoundException] {
                            Write-Host "Exception:" $_.GetType().FullName -fore yellow
                            if($_.Message -match "ambiguous. Possible matches") {
                                Write-Output "$($_.Exception.Message)"
                            } else {
                                Write-Output "$($_.Exception.Message)`n`nI probably don't have the right module available."
                            }
                            continue
                        } catch {
                            Write-Host $_.GetType().FullName -fore yellow
                            Write-Host "I have no idea what just happened:`n`n$($_|out-string)" -Fore Red
                            throw $_
                        }
                    }
                    
                    end
                    {
                        if($steppablePipeline) {
                            try {
                                $steppablePipeline.End()
                            } catch {
                                throw
                            }
                        }
                    }
                }
                
                # Make sure Get-Command is available without prefix even for elevated users 
                Set-Alias Get-Command Get-UserCommand
                Export-ModuleMember -Function * -Alias Get-Command
            }
        } -Args ($Role, $RoleWhiteList[$Role], $Force) | 
            Import-Module -Scope Global -Prefix $(if($Role -notmatch "User|Guest") { $Role } else {""}) -Passthru | 
            Out-String -Stream | Write-Verbose
    }
}

Export-ModuleMember -Function Start-Adapter