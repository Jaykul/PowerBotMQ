# source the ThrowError function instead of using `throw`
. "$PSScriptRoot\ThrowError.ps1"

if(!$global:PowerBotStoragePath) {
    trap { 
        [string]$global:PowerBotStoragePath = Join-Path $PowerBotScriptRoot "Data"
        continue
    }
    [string]$global:PowerBotStoragePath = Get-StoragePath -CompanyName "HuddledMasses.org" -Name "PowerBot"
}

## If Jim Christopher's SQLite module is available, we'll use it
Import-Module -Name SQLitePSProvider -Scope Global -ErrorAction SilentlyContinue
if(!(Test-Path data:) -and (Microsoft.PowerShell.Core\Get-Command -Name Mount-SQLite)) {
    $BotDataFile = Join-Path $global:PowerBotStoragePath "botdata.sqlite"
    Mount-SQLite -Name data -DataSource ${BotDataFile}
} elseif(!(Test-Path data:)) {
    Write-Warning "No data drive, UserTracking and Roles disabled"
	return
}

if(Test-Path data:) {
    # So all we have to worry about is whether the Roles table is present
    if(!(Test-Path data:\Role)) {
        New-Item data:\Role -Value "guid TEXT PRIMARY KEY, Roles TEXT"
        New-Item data:\User -Value "guid TEXT NOT NULL, Network TEXT NOT NULL, AuthenticatedUser TEXT NOT NULL, DisplayName TEXT NOT NULL, unique (Network, AuthenticatedUser), FOREIGN KEY(guid) REFERENCES Roles(guid)"
    }
}

function Get-Role {
    #.Synopsis
    #   Fetch the official user tracking and roles for a given network user     
    [CmdletBinding(DefaultParameterSetName="ByName")]
    param(
        # The Users's GUID
        [Parameter(Position=0, Mandatory=$True, ValueFromPipelineByPropertyName=$true, ParameterSetName='ByGuid')]
        [Guid]$Guid,
        
        # The Network the user belongs to
        [Parameter(Position=0, Mandatory=$True, ValueFromPipelineByPropertyName=$true, ParameterSetName='ByName')]
        [string]$Network,
        
        # The AuthenticatedUser to fetch roles for
        [Parameter(Position=1, Mandatory=$True, ValueFromPipelineByPropertyName=$true, ParameterSetName='ByName')]
        [string]$AuthenticatedUser,
        
        # The AuthenticatedUser to fetch roles for
        [Parameter(Position=2, ValueFromPipelineByPropertyName=$true)]
        [string]$DisplayName                
    )
    
    if($PSCmdlet.ParameterSetName -eq "ByGuid") {
        $FullUser = Invoke-Item data: -sql "SELECT * from User LEFT OUTER JOIN Role ON User.guid = Role.guid WHERE User.guid = '$($Guid.Guid)'"
    } else {
        $Network = $Network.ToLowerInvariant() -replace "'","''"
        $AuthenticatedUser = $AuthenticatedUser.ToLowerInvariant() -replace "'","''"
        $WildName = $AuthenticatedUser -replace '\*','%'
        $DisplayName = $DisplayName -replace "'","''"
    
        # Do a SQL query and then just try to pick the best match
        $MatchingUsers = @(Invoke-Item data: -sql "SELECT * from User LEFT OUTER JOIN Role ON User.guid = Role.guid 
                                                   WHERE User.Network LIKE '%${Network}%' AND
                                                   (User.AuthenticatedUser = '${AuthenticatedUser}' OR User.DisplayName LIKE '${WildName}')")
        $FullUser = $MatchingUsers[0]
        if($MatchingUsers.Count -gt 1) {
            if(!($FullUser = $MatchingUsers | Where AuthenticatedUser -eq $AuthenticatedUser | Select -First 1)) {
                if(!($FullUser = $MatchingUsers | Where DisplayName -eq $AuthenticatedUser | Select -First 1)) {
                    if(!($FullUser = $MatchingUsers | Where DisplayName -like $AuthenticatedUser | Select -First 1)) {
                        $FullUser = $MatchingUsers | Select -First 1
                    }
                }
            }
        }
    }
    
    if(!$FullUser) {
        if([string]::IsNullOrEmpty($DisplayName)) {
            ThrowError $PSCmdlet System.InvalidOperationException "User does not exist, and the DisplayName is missing." $DisplayName "UserNotFound" "Cannot create user without display name"            
        }
        $GUID = [Guid]::NewGuid().Guid
        $null = Invoke-Item data: -sql "INSERT into Role (Guid, Roles) VALUES ('$guid', 'user')"
        $null = Invoke-Item data: -sql "INSERT into User (Guid, Network, AuthenticatedUser, DisplayName) VALUES ('$guid', '$Network', '$AuthenticatedUser', '$DisplayName')"
        
        $FullUser = Invoke-Item data: -sql "SELECT * from User LEFT OUTER JOIN Role ON User.guid = Role.guid 
                                            WHERE User.Network = '$Network' AND User.AuthenticatedUser = '$AuthenticatedUser'"
        if(!$FullUser) {
            $FullUser = New-Object PSObject -Property @{Network = $Network; AuthenticatedUser = "Unidentified '$DisplayName'"; DisplayName = $DisplayName; Roles = @("guest"); PSTypeName = "PowerBot.Roles"}
        }  
    }
    $FullUser = Select-Object -InputObject $FullUser Network, AuthenticatedUser, DisplayName, @{n="Roles"; e={[string[]]($_.Roles -split "\s+")}}, guid
    $FullUser.PSTypeNames.Insert(0, "PoshCode.PowerBot.User")
    return $FullUser
}


function Add-Role {
    #.Synopsis
    #   Add a role to the specified user     
    [CmdletBinding(DefaultParameterSetName="ByName")]
    param(
        # The Network the user belongs to
        [Parameter(Position=0, Mandatory=$True, ValueFromPipelineByPropertyName=$true, ParameterSetName='ByName')]
        [string]$Network,
        
        # The AuthenticatedUser to fetch roles for
        [Parameter(Position=1, Mandatory=$True, ValueFromPipelineByPropertyName=$true, ParameterSetName='ByName')]
        [string]$AuthenticatedUser,

        [Parameter(Position=0, Mandatory=$False, ValueFromPipelineByPropertyName=$true, ParameterSetName='ByGuid')]
        [Guid]$Guid,

        # The role(s) to add
        [Parameter(Position=1, Mandatory=$true)]
        [ValidateScript({if($Script:Roles -contains $_){ $True } else { throw "'$_' is not a valid Role. Please use one of: $($Script:Roles -join ', ')"}})]
        [String[]]$Role
    )
   
    if(!$Guid) {
        $User = Get-Role -Network $Network -AuthenticatedUser $AuthenticatedUser
    } else {
        $User = Get-Role -Guid $Guid
    }
    $Guid = $User.Guid
    $Role = @($Role.ToLower()) + @($User.Roles) | Select -unique
    Write-Verbose "Update user '$($Guid.Guid)' ($($User.DisplayName)) with $Role"
    $Null = Set-Item data:\Role -Filter "guid = '$($Guid.Guid)'" -Value @{Roles = $Role -join ' '} -ErrorAction SilentlyContinue

    Get-Role -Guid $Guid
}


function Remove-Role {
    #.Synopsis
    #   Remove a role from the specified user 
    [CmdletBinding(DefaultParameterSetName="ByName")]
    param(
        # The Network the user belongs to
        [Parameter(Position=0, Mandatory=$True, ValueFromPipelineByPropertyName=$true, ParameterSetName='ByName')]
        [string]$Network,
        
        # The AuthenticatedUser to fetch roles for
        [Parameter(Position=1, Mandatory=$True, ValueFromPipelineByPropertyName=$true, ParameterSetName='ByName')]
        [string]$AuthenticatedUser,

        [Parameter(Position=0, Mandatory=$False, ValueFromPipelineByPropertyName=$true, ParameterSetName='ByGuid')]
        [Guid]$Guid,

        # The role(s) to add
        [Parameter(Position=1, Mandatory=$true)]
        [ValidateScript({if($Script:Roles -contains $_){ $True } else { throw "'$_' is not a valid Role. Please use one of: $($Script:Roles -join ', ')"}})]
        [String[]]$Role
    )
   
    if(!$Guid) {
        $User = Get-Role -Network $Network -AuthenticatedUser $AuthenticatedUser
    } else {
        $User = Get-Role -Guid $Guid
    }
    $Guid = $User.Guid
    $Role = $Role.ToLower()
    $Role = $User.Roles | Where { $_ -notin $Role } | Select -unique
    Write-Verbose "Update user '$($Guid.Guid)' ($($User.DisplayName)) with $Role"
    $Null = Set-Item data:\Role -Filter "guid = '$($Guid.Guid)'" -Value @{Roles = $Role -join ' '} -ErrorAction SilentlyContinue

    Get-Role -Guid $Guid
}

# Set-Alias Where Microsoft.PowerShell.Core\Where-Object -Force -Option AllScope
# Set-Alias ForEach Microsoft.PowerShell.Core\ForEach-Object -Force -Option AllScope
# Set-Alias Select Microsoft.PowerShell.Core\Select-Object -Force -Option AllScope

Update-TypeData -DefaultDisplayPropertySet Network, AuthenticatedUser, DisplayName, Roles -TypeName "PoshCode.PowerBot.User" -Force

Export-ModuleMember -Function Get-Role, Add-Role, Remove-Role
