function Get-SecurityDatabase {
    [CmdletBinding()]
    [OutputType([Hashtable])]
    Param()

    $datahash = @{}

    secedit.exe /export /cfg "$env:APPDATA\secpol.cfg" | Out-Null
    Get-Content -Path $env:APPDATA\secpol.cfg | ForEach-Object {
        if($_.StartsWith('['))
        {
            $section = $_
            $datahash.add($section, @())
        }
        else
        {
            [array]$newdata = $datahash.Get_Item($section)
            $newdata += $_
            $datahash.Set_Item($section, $newdata)
        }
    }
    Remove-Item -path $env:APPDATA\secpol.cfg | Out-Null

    return $datahash
}

function Set-SecurityPrivilege {
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true)]
        [System.String]
        $Privilege,
        [parameter(Mandatory = $true)]
        [System.String]
        $PrivilegeString
    )
    $dbinfo = Get-SecurityDatabase
    Write-Verbose "Was: $($dbinfo.'[Privilege Rights]' -match "^$Privilege.*")"
    
    $dbinfo.'[Privilege Rights]' = $dbinfo.'[Privilege Rights]' -replace "^$Privilege.*","$Privilege = $PrivilegeString"

    $dbinfo.Keys | ForEach-Object {
        Write-Output $_
        $dbinfo.$_ | ForEach-Object {
            Write-Output $_
        }
    } | Out-File $env:APPDATA\tempsecinf.inf -Force
    $tempDB = "$env:TEMP\tempSecedit.sdb"   
    secedit.exe /configure /db $env:TEMP\tempSecedit.sdb /cfg $env:APPDATA\tempsecinf.inf
    Write-Verbose "Now: $Privilege = $PrivilegeString"
    Remove-Item $env:APPDATA\tempsecinf.inf
    Remove-Item $env:Temp\tempSecedit.sdb
}

function Get-TargetResource {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Privilege
    )
    $userRights = (Get-SecurityDatabase).Get_Item("[Privilege Rights]") -match $Privilege
    if($userRights.Count -gt 0) {
        $memberSIDs = $userRights.split('=')[1].trim() -split ',' | ForEach-object {
            $_ = $_.substring(1);$_
        }
        $memberNames = $memberSIDS | ForEach-Object {
            (New-Object System.Security.Principal.SecurityIdentifier($_)).Translate([System.Security.Principal.NTAccount]).Value
        }

        return @{
            Privilege = [System.String]$Privilege
            Members = [System.String[]]$memberNames
            SIDs = [System.String[]]$memberSIDs
        }
    }
    else {
        Write-Verbose "No users with $Privilege found on system"
        return @{
            Privilege = [System.String]$Privilege
            Members = [System.String[]]''
            SIDs = [System.String[]]''
        }
    }
}

function Set-TargetResource {
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Privilege,

        [System.String[]]
        $Members,

        [System.String[]]
        $MembersInclude,

        [System.String[]]
        $MembersExclude,

        [System.String[]]
        $SIDs,

        [System.String[]]
        $SIDsInclude,

        [System.String[]]
        $SIDsExclude
    )

    $temp = @()
    $tempmembers = (Get-TargetResource -Privilege $Privilege).SIDs
    write-verbose "$Privilege Current Members $($tempmembers -join ',')"
    
    if(($psboundparameters.keys -contains 'Members') -or ($psboundparameters.keys -contains 'SIDs')) {
        if($psboundparameters.keys -contains 'Members') {
            $Members | ForEach-Object {
                $parsed = $_.split("\")
                if($parsed[1]){
                    $objUser = New-Object System.Security.Principal.NTAccount($parsed[0], $parsed[1])
                }
                else {
                    $objUser = New-Object System.Security.Principal.NTAccount($parsed[0])
                }
                $temp += ($objUser.Translate([System.Security.Principal.SecurityIdentifier])).Value
            }
        }
        if($psboundparameters.keys -contains 'SIDs') {
            $SIDs | ForEach-Object {
                $temp += $_
            }
        }
        $temp = $temp | Select-Object -Unique | ForEach-Object {
            "*$_"
        }
        Write-Verbose "$Privilege Setting $($temp -join ',')"
        Set-SecurityPrivilege -Privilege $Privilege -PrivilegeString $($temp -join ',')
    }
    else {
        if($psboundparameters.keys -contains 'MembersInclude') {
            $MembersInclude | ForEach-Object {
                $parsed = $_.split("\")
                if($parsed[1]){
                    $objUser = New-Object System.Security.Principal.NTAccount($parsed[0], $parsed[1])
                }
                else {
                    $objUser = New-Object System.Security.Principal.NTAccount($parsed[0])
                }
                write-verbose "$Privilege MembersInclude adding $(($objUser.Translate([System.Security.Principal.SecurityIdentifier])).Value)"
                $tempmembers += ($objUser.Translate([System.Security.Principal.SecurityIdentifier])).Value
            }
        }
        if($psboundparameters.keys -contains 'MembersExclude') {
            $MembersExclude = $MembersExclude | ForEach-Object {
                $parsed = $_.split("\")
                if($parsed[1]){
                    $objUser = New-Object System.Security.Principal.NTAccount($parsed[0], $parsed[1])
                }
                else {
                    $objUser = New-Object System.Security.Principal.NTAccount($parsed[0])
                }
                ($objUser.Translate([System.Security.Principal.SecurityIdentifier])).Value
            }
            $tempmembers = $tempmembers | ForEach-Object {
                if($_ -notin $MembersExclude) {
                    $_
                } else {
                    write-verbose "$Privilege MembersExclude removing $_"
                }
             }
        }
        if($psboundparameters.keys -contains 'SIDsInclude') {
            $SIDsInclude | ForEach-Object {
                Write-Verbose "$Privilege SIDsInclude adding $_"
                $tempmembers += $_
            }
        }
        if($psboundparameters.keys -contains 'SIDsExclude') {
            $tempmembers = $tempmembers | ForEach-Object {
                if($_ -notin $SIDsExclude) {
                    $_
                } else {
                    write-verbose "$Privilege SIDsExclude removing $_"
                }
            }
        }
        $tempmembers = $tempmembers | Select-Object -Unique
        $tempmembers = $tempmembers | ForEach-Object {
            "*$_"
        }
        Set-SecurityPrivilege -Privilege $Privilege -PrivilegeString $($tempmembers -join ',')
    }

    #Write-Verbose "Use this cmdlet to deliver information about command processing."

    #Write-Debug "Use this cmdlet to write debug information while troubleshooting."

    #Include this line if the resource requires a system reboot.
    #$global:DSCMachineStatus = 1

}

function Test-TargetResource {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Privilege,

        [System.String[]]
        $Members,

        [System.String[]]
        $MembersInclude,

        [System.String[]]
        $MembersExclude,

        [System.String[]]
        $SIDs,

        [System.String[]]
        $SIDsInclude,

        [System.String[]]
        $SIDsExclude
    )

    $state = Get-TargetResource -Privilege $Privilege
    $results = $true

    if ($psboundparameters.keys -contains 'Members') {
        $Members | ForEach-Object {
            if($state.Members -notcontains $_) {
                Write-Verbose "$_ does not have $privilege right"
                $results = $false
            }
        }
        $state.Members | ForEach-Object {
            if($Members -notcontains $_) {
                Write-Verbose "$_ should not have $privilege right"
                $results = $false
            }
        }
    }
    if ($psboundparameters.keys -contains 'SIDs') {
        $SIDs | ForEacH-Object {
            if($state.SIDs -notcontains $_) {
                Write-Verbose "$_ does not have $privilege right"
                $results = $false
            }
        }
        $state.SIDs | ForEach-Object {
            if($SIDs -notcontains $_) {
                Write-Verbose "$_ should not have $privilege right"
                $results = $false
            }
        }
    }
    if ($psboundparameters.keys -contains 'MembersInclude') {
        $MembersInclude | ForEach-Object {
            if($state.Members -notcontains $_) {
                Write-Verbose "$_ does not have $privilege right"
                $results = $false
            }
        }
    }
    if ($psboundparameters.keys -contains 'MembersExclude') {
        $MembersExclude | ForEach-Object {
            if($state.Members -contains $_) {
                Write-Verbose "$_ should not have $privilege right"
                $results = $false
            }
        }
    }
    if ($psboundparameters.keys -contains 'SIDsInclude') {
        $SIDsInclude | ForEach-Object {
            if($state.SIDs -notcontains $_) {
                Write-Verbose "$_ does not have $privilege right"
                $results = $false
            }
        }
    }
    if ($psboundparameters.keys -contains 'SIDsExclude') {
        $SIDsExclude | ForEach-Object {
            if($state.SIDs -contains $_) {
                Write-Verbose "$_ should not have $privilege right"
                $results = $false
            }
        }    
    }
    
    return $results
}

Export-ModuleMember -Function *-TargetResource

