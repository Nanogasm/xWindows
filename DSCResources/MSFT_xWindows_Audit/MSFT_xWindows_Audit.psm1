function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $AuditSubCategory,

        [System.Boolean]
        $Success,

        [System.Boolean]
        $Failure
    )
    Write-Verbose "Get $AuditSubCategory.  Extra Values $Success $Failure"
    Write-Verbose $PSBoundParameters.Keys
    [System.String]$results = (auditpol.exe "/get" ("/subcategory:{0}" -f ((auditpol /list /subcategory:* /v | Select-Object -Skip 1 | ForEach-Object {@{$_.substring(0,40).trim() = $_.substring(40).trim()}}).$AuditSubCategory))) | Select-String $AuditSubCategory
    
    [System.Collections.Hashtable]@{
        AuditSubCategory = [System.String]$AuditSubCategory
        Success = $results -match 'Success'
        Failure = $results -match 'Failure'
    }
}

function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $AuditSubCategory,

        [System.Boolean]
        $Success,

        [System.Boolean]
        $Failure
    )

    $GUID = (auditpol.exe /list /subcategory:* /v | Select-Object -Skip 1 | ForEach-Object {@{$_.substring(0,40).trim() = $_.substring(40).trim()}}).$AuditSubCategory

    Write-Verbose $PSBoundParameters.Keys
    if($PSBoundParameters.ContainsKey('Success')){
        if($Success){
            $successString = '/success:enable'
        }
        else {
            $successString = '/success:disable'
        }
    }
    if($PSBoundParameters.ContainsKey('Failure')){
        if($Failure){
            $failString = '/failure:enable'
        }
        else {
            $failString = '/failure:disable'
        }
    }
    Write-Verbose "AuditPol String: auditpol.exe /set /subcategory:$GUID $failString $successString"
    auditpol.exe '/set' "/subcategory:$GUID" $failString $successString
}

function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $AuditSubCategory,

        [System.Boolean]
        $Success,

        [System.Boolean]
        $Failure
    )
    $systemValue = Get-TargetResource @PSBoundParameters
    
    if($PSBoundParameters.ContainsKey('Success')){
        if($systemValue.Success -eq $Success){
        }
        else {
            return $false
        }
    }
    if($PSBoundParameters.ContainsKey('Failure')){
        if($systemValue.Failure -eq $Failure){
        }
        else {
            return $false
        }
    }
    return $true
}

Export-ModuleMember -Function *-TargetResource

