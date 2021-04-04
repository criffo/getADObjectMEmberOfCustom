function Get-ADObjectMemberOfCustom {
    <#
        .SYNOPSIS
        Author  : Christophe Fortunati
        Version : 1.0
        Gets memberof attribute recursively for an active directory object (computer,user,group)

        .DESCRIPTION
        Gets memberof attribute recusvely for an active directory object (computer,user,group)
        LDAP request via .Net classes, namespace System.DirectoryServices for the directory searcher and active dorectory classes, no need to import activedirectory module
        Allows to include the domain users or computers membership as well
        It takes by default the forest level but the search can be restreined to domain or extended to domain and its trusts, forest and its trusts or explicit domains
        it returns void in case of no result and in case of result a list of object with string attributes for csv export

        .PARAMETER DnOrSamAccountame
        Specifies either the disitnguished name of the AD object or the samaccountname. Mandatory.

        .PARAMETER ADObjectDomainm
        Specifies the Full Qualified Domain Name (FQDN) of the AD object domain. Mandatory.

        .PARAMETER Include
        Specifies to include the either Domain users group either Domain computers group or none of them. Not Mandatory.
        Default none of them is included. Validateset.

        .PARAMETER Scope
        Specifies the search scope for the Breath depth search. Validateset. Not Mandatory. Default is Forest.
        Domain : search scope within the adobject domain only.
        Forest : search scope within the adobject forest (so parent and children domain of the forest).
        ForestTrusts : search scope within the adobject forest (so parent and children domain of the forest) and the Forest trusts.
        DomainTrusts : search scope within the adobject domain and the domain trusts.
        ForestAndDomainTrusts : search scope within the adobject forest (so parent and children domain of the forest), the Forest trusts and the domain trusts.
        ExplicitDomains : if specified, it will search within the object domain and will use the ExplicitDomainsNamesSearch paramter to look in these domain(s) as well.

        .PARAMETER ExplicitDomainsNamesSearch
        Specifies the list of domains to look in if the parameter Scope is set to ExplicitDomains. Mandatory only if Scope parameter is set to ExplicitDomains.
        domains are FQDN and separated by comma in case of several domains to look into.

        .PARAMETER SearcherPageSize
        Specifies the page size of domain controllers to proceed the LDAP query. Not Mandatory.
        Default is applied, a ldap query returns maximum 1000 objects.
        Page size defined on the .net class, directory searcher.

        .INPUTS
        None. You cannot pipe objects to Get-ADObjectMemberOfCustom.

        .OUTPUTS
        System.Collections.Generic.List[object]. Get-ADObjectMemberOfCustom a list of objects with string attributes in order to allow export-csv
        Nothing is returned in case of no result.

        .EXAMPLE
        C:\PS> Get-ADObjectMemberOfCustom samcountname global.contoso.com

        .EXAMPLE
        C:\PS> Get-ADObjectMemberOfCustom distinguishedname global.contoso.com IncludeDomainUsersBuiltinGroup ForestAndDomainTrusts -SearcherPageSize 1000

        .EXAMPLE
        C:\PS> Get-ADObjectMemberOfCustom distinguishedname global.contoso.com IncludeDomainUsersBuiltinGroup ExplicitDomains "corp1.constoso.com","corp2.contoso.com","external.com"

        .NOTES
            Author  : Christophe Fortunati
            Version : 1.0
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $DnOrSamAccountame,
        
        [Parameter(Mandatory=$true)]
        [string]
        $ADObjectDomain,

        [Parameter(Mandatory=$false)]
        [Validateset("IncludeDomainUsersBuiltinGroup", "IncludeDomainComputersBuiltinGroup", "None")]
        [String]
        $Include = "None",

        [Parameter(Mandatory=$false)]
        [Validateset("Domain", "Forest", "ForestTrusts", "DomainTrusts", "ForestAndDomainTrusts", "ExplicitDomains")]
        [String]
        $Scope = "Forest",

        [Parameter(Mandatory=$false)]
        [string[]]
        $ExplicitDomainsNamesSearch,

        [Parameter(Mandatory=$false)]
        [int16]
        $SearcherPageSize
    )

    $DomainToQuery = @{}
    $ObjectAlreadyQueried = @{}
    $memberOfTemp = New-Object System.Collections.Generic.List[string]
    $listBFS = New-Object System.Collections.Generic.List[string]
    $tsilBFS = New-Object System.Collections.Generic.List[string]
    $resutls = New-Object System.Collections.Generic.List[object]
    $nestingLevel = 0
    $Searcher = new-Object System.DirectoryServices.DirectorySearcher
    $Searcher.DerefAlias = [System.DirectoryServices.DereferenceAlias]::Always
    #it page size of ADSI seracher must be different than default, default 0 can conain 1000 objects from iobservable collection retunr page form DC
    if ($SearcherPageSize) {$Searcher.pagesize = $SearcherPageSize}
    #we control if the ad object exists in its domain first
    if ($DnOrSamAccountame -match "DC=") {
        $Searcher.Filter = "(distinguishedName=$DnOrSamAccountame)"
    } else {
        $Searcher.Filter = "(sAMAccountName=$DnOrSamAccountame)"
    }
    $Searcher.SearchRoot = "LDAP://" + $ADObjectDomain
    $Searcher.SearchScope = "subtree"
    $InitialADObjectResult = $Searcher.FindOne()
    #in case computer and samaccountname give we need to search with $ at the end
    if ($InitialADObjectResult -eq $null) {
        if (!($DnOrSamAccountame -match "DC=")) {
            $Searcher.Filter = "(sAMAccountName=$DnOrSamAccountame$)"
            $InitialADObjectResult = $Searcher.FindOne()
        }
    }
    if ($InitialADObjectResult -eq $null) {
        write-warning -Message ("No AD object with Distinguished Name or SamAccoutname " + $DnOrSamAccountame + " has been found in domain " + $ADObjectDomain)
    } else {
        #we take into account the parameters for the scope search
        switch ($Scope) {
            "Domain" {
                #the memberof recurse search is done within user domain only
                $DomainDirectoryContextType = [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new([System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Domain, $ADObjectDomain)
                try {
                    $DomainSiteConfiguration = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($DomainDirectoryContextType)
                } catch {
                    write-warning -Message ("Cannot query the domain " + $ADObjectDomain + " : " + $_.Exception.message)
                }
                if ($DomainSiteConfiguration -ne $null) {
                    $DomainToQuery.Add($DomainSiteConfiguration.Name,$DomainSiteConfiguration.Forest.name)
                    $DomainSiteConfiguration.Dispose()
                }
                ;break}
            "Forest" {
                #the memberof recurse search is done within all the domains within the user forest
                $DomainDirectoryContextType = [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new([System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Domain, $ADObjectDomain)
                try {
                    $DomainSiteConfiguration = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($DomainDirectoryContextType)
                } catch {
                    write-warning -Message ("Cannot query the domain " + $ADObjectDomain + " : " + $_.Exception.message)
                }
                if ($DomainSiteConfiguration -ne $null) {
                    $DomainToQuery.Add($DomainSiteConfiguration.Name,$DomainSiteConfiguration.Forest.name)
                    $ForestDirectoryContextType = [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new([System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Forest, $DomainSiteConfiguration.Forest.name)
                    try {
                        $ForestSiteConfiguration = [System.DirectoryServices.ActiveDirectory.Forest]::GetForest($ForestDirectoryContextType)
                    } catch {
                        write-warning -Message ("Cannot query the forest " + $DomainSiteConfiguration.Forest + " : " + $_.Exception.message)
                    }
                    if ($ForestSiteConfiguration.Domains -ne $null) {
                        $ForestSiteConfiguration.Domains.Name.Foreach({
                            if (-not ($DomainToQuery."$psitem")) {
                                $DomainContextTemp = [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new([System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Domain, $psitem)
                                try {
                                    $domainTempSiteConfiguration = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($DomainContextTemp)
                                    $DomainToQuery.Add($psitem,$DomainSiteConfiguration.Forest.name)
                                    $domainTempSiteConfiguration.Dispose()
                                } catch {
                                    write-warning -Message ("Cannot query the domain " + $ADObjectDomain + " : " + $_.Exception.message)
                                }
                            }
                        })
                        $ForestSiteConfiguration.Dispose()
                    }
                    $DomainSiteConfiguration.Dispose()
                };break}
            "ForestTrusts" {
                #the memberof recurse search is done within the user domain and within the user forest and child domain and trust external made on the forest if bidirectionnal or inbound to target external
                $DomainDirectoryContextType = [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new([System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Domain, $ADObjectDomain)
                try {
                    $DomainSiteConfiguration = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($DomainDirectoryContextType)
                } catch {
                    write-warning -Message ("Cannot query the domain " + $ADObjectDomain + " : " + $_.Exception.message)
                }
                if ($DomainSiteConfiguration -ne $null) {
                    $DomainToQuery.Add($DomainSiteConfiguration.Name,$DomainSiteConfiguration.Forest.name)
                    $ForestDirectoryContextType = [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new([System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Forest, $DomainSiteConfiguration.Forest.name)
                    try {
                        $ForestSiteConfiguration = [System.DirectoryServices.ActiveDirectory.Forest]::GetForest($ForestDirectoryContextType)
                    } catch {
                        write-warning -Message ("Cannot query the forest " + $DomainSiteConfiguration.Forest + " : " + $_.Exception.message)
                    }
                    if ($ForestSiteConfiguration.Domains -ne $null) {
                        $ForestSiteConfiguration.Domains.Name.Foreach({
                            if (-not ($DomainToQuery."$psitem")) {
                                $DomainContextTemp = [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new([System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Domain, $psitem)
                                try {
                                    $domainTempSiteConfiguration = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($DomainContextTemp)
                                    $DomainToQuery.Add($psitem,$domainTempSiteConfiguration.Forest.name)
                                    $domainTempSiteConfiguration.Dispose()
                                } catch {
                                    write-warning -Message ("Cannot query the domain " + $ADObjectDomain + " : " + $_.Exception.message)
                                }
                            }
                        })
                        $ForestTrusts = $ForestSiteConfiguration.GetAllTrustRelationships()
                        if ($ForestTrusts -ne $null) {
                            $SelectionOfAccurateForestTrusts = $ForestTrusts.Where({$_.TrustDirection -ne "Outbound"})
                            if ($SelectionOfAccurateForestTrusts -ne $null) {
                                $SelectionOfAccurateForestTrusts.Foreach({
                                    $forestTemp = $psitem.TargetName
                                    $ForestDirectoryContextTypeTemp = [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new([System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Forest, $forestTemp)
                                    try {
                                        $ForestSiteConfigurationTemp = [System.DirectoryServices.ActiveDirectory.Forest]::GetForest($ForestDirectoryContextTypeTemp)
                                        $ForestSiteConfigurationTemp.Domains.name.Foreach({
                                            if (-not $DomainToQuery."$psitem") {
                                                $DomainContextTemp = [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new([System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Domain, $psitem)
                                                try {
                                                    $domainTempSiteConfiguration = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($DomainContextTemp)
                                                    $DomainToQuery.Add($psitem,$domainTempSiteConfiguration.Forest.name)
                                                    $domainTempSiteConfiguration.Dispose()
                                                } catch {
                                                    write-warning -Message ("Cannot query the domain " + $domainTempSiteConfiguration.name + " : " + $_.Exception.message)
                                                }
                                            }                                        
                                        })
                                        $ForestSiteConfigurationTemp.Dispose()
                                    } catch {
                                        write-warning -Message ("Cannot query the forest " + $forestTemp + " : " + $_.Exception.message)
                                    }
                                })
                            }
                        }
                        $ForestSiteConfiguration.Dispose()
                    }
                    $DomainSiteConfiguration.Dispose()
                }
                ;break}
            "DomainTrusts" {
                #the memberof recurse search is done within all the user domain and trust external or crosslink made on the user domain if bidirectionnal or inbound to target external
                $DomainDirectoryContextType = [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new([System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Domain, $ADObjectDomain)
                try {
                    $DomainSiteConfiguration = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($DomainDirectoryContextType)
                } catch {
                    write-warning -Message ("Cannot query the domain " + $ADObjectDomain + " : " + $_.Exception.message)
                }
                if ($DomainSiteConfiguration -ne $null) {
                    $DomainToQuery.Add($DomainSiteConfiguration.Name,$DomainSiteConfiguration.Forest.name)
                    $DomainTrusts = $DomainSiteConfiguration.GetAllTrustRelationships()
                    if ($DomainTrusts -ne $null) {
                        $SelectionOfAccurateDomainTrusts = $DomainTrusts.Where({$_.TrustDirection -ne "Outbound" -and $_.TrustType -ne "ParentChild"})
                        if ($SelectionOfAccurateDomainTrusts) {
                            $SelectionOfAccurateDomainTrusts.Foreach({
                                $domTemp = $psitem.TargetName
                                if (-not ($DomainToQuery."$domTemp")) {
                                    $DomainContextTemp = [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new([System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Domain, $domTemp)
                                    try {
                                        $domainTempSiteConfiguration = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($DomainContextTemp)
                                        $DomainToQuery.Add($domTemp,$domainTempSiteConfiguration.Forest.name)
                                        $domainTempSiteConfiguration.Dispose()
                                    } catch {
                                        write-warning -Message ("Cannot query the domain " + $domTemp + " : " + $_.Exception.message)
                                    }
                                }
                            })
                        }
                    }
                    $DomainSiteConfiguration.Dispose()
                }
                ;break}
            "ForestAndDomainTrusts" {
                #the memberof recurse search is done within all the domains within the user forest and trust external made on the forest and user domain if bidirectionnal or inbound to target external
                $DomainDirectoryContextType = [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new([System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Domain, $ADObjectDomain)
                try {
                    $DomainSiteConfiguration = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($DomainDirectoryContextType)
                } catch {
                    write-warning -Message ("Cannot query the domain " + $ADObjectDomain + " : " + $_.Exception.message)
                }
                if ($DomainSiteConfiguration -ne $null) {
                    $DomainToQuery.Add($DomainSiteConfiguration.Name,$DomainSiteConfiguration.Forest.name)
                    $ForestDirectoryContextType = [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new([System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Forest, $DomainSiteConfiguration.Forest.name)
                    try {
                        $ForestSiteConfiguration = [System.DirectoryServices.ActiveDirectory.Forest]::GetForest($ForestDirectoryContextType)
                    } catch {
                        write-warning -Message ("Cannot query the forest " + $DomainSiteConfiguration.Forest.name + " : " + $_.Exception.message)
                    }
                    if ($ForestSiteConfiguration.Domains -ne $null) {
                        $ForestSiteConfiguration.Domains.Name.Foreach({
                            if (-not ($DomainToQuery."$psitem")) {
                                $DomainContextTemp = [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new([System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Domain, $psitem)
                                try {
                                    $domainTempSiteConfiguration = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($DomainContextTemp)
                                    $DomainToQuery.Add($psitem,$domainTempSiteConfiguration.Forest.name)
                                    $domainTempSiteConfiguration.Dispose()
                                } catch {
                                    write-warning -Message ("Cannot query the domain " + $ADObjectDomain + " : " + $_.Exception.message)
                                }
                            }
                        })
                        $ForestTrusts = $ForestSiteConfiguration.GetAllTrustRelationships()
                        if ($ForestTrusts -ne $null) {
                            $SelectionOfAccurateForestTrusts = $ForestTrusts.Where({$_.TrustDirection -ne "Outbound"})
                            if ($SelectionOfAccurateForestTrusts -ne $null) {
                                $SelectionOfAccurateForestTrusts.Foreach({
                                    $forestTemp = $psitem.TargetName
                                    $ForestDirectoryContextTypeTemp = [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new([System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Forest, $forestTemp)
                                    try {
                                        $ForestSiteConfigurationTemp = [System.DirectoryServices.ActiveDirectory.Forest]::GetForest($ForestDirectoryContextTypeTemp)
                                        $ForestSiteConfigurationTemp.Domains.name.Foreach({
                                            if (-not $DomainToQuery."$psitem") {
                                                $DomainContextTemp = [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new([System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Domain, $psitem)
                                                try {
                                                    $domainTempSiteConfiguration = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($DomainContextTemp)
                                                    $DomainToQuery.Add($psitem,$domainTempSiteConfiguration.Forest.name)
                                                    $domainTempSiteConfiguration.Dispose()
                                                } catch {
                                                    write-warning -Message ("Cannot query the domain " + $domainTempSiteConfiguration.name + " : " + $_.Exception.message)
                                                }
                                            }                                        
                                        })
                                        $ForestSiteConfigurationTemp.Dispose()
                                    } catch {
                                        write-warning -Message ("Cannot query the forest " + $forestTemp + " : " + $_.Exception.message)
                                    }
                                })
                            }
                        }
                        $ForestSiteConfiguration.Dispose()
                    }
                    $DomainTrusts = $DomainSiteConfiguration.GetAllTrustRelationships()
                    if ($DomainTrusts -ne $null) {
                        $SelectionOfAccurateDomainTrusts = $DomainTrusts.Where({$_.TrustDirection -ne "Outbound" -and $_.TrustType -ne "ParentChild"})
                        if ($SelectionOfAccurateDomainTrusts) {
                            $SelectionOfAccurateDomainTrusts.Foreach({
                                $domTemp = $psitem.TargetName
                                if (-not ($DomainToQuery."$domTemp")) {
                                    $DomainContextTemp = [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new([System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Domain, $domTemp)
                                    try {
                                        $domainTempSiteConfiguration = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($DomainContextTemp)
                                        $DomainToQuery.Add($domTemp,$domainTempSiteConfiguration.Forest.name)
                                        $domainTempSiteConfiguration.Dispose()
                                    } catch {
                                        write-warning -Message ("Cannot query the domain " + $domTemp + " : " + $_.Exception.message)
                                    }
                                }
                            })
                        }
                    }
                    $DomainSiteConfiguration.Dispose()
                }
                ;break}
            "ExplicitDomains" {
                #only explicite domain memberof recurse search paired with switch multistrings comma separated -ExplicitDomainsNamesSearch FQDN of domains
                if (-not ($ExplicitDomainsNamesSearch)) {
                    write-warning -Message "No FQDN of doamins to query defined in switch  -ExplicitDomainsNamesSearch, please add one or some comma separated"
                    exit
                } else {
                    $DomainDirectoryContextType = [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new([System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Domain, $ADObjectDomain)
                    try {
                        $DomainSiteConfiguration = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($DomainDirectoryContextType)
                    } catch {
                        write-warning -Message ("Cannot query the domain " + $ADObjectDomain + " : " + $_.Exception.message)
                    }
                    if ($DomainSiteConfiguration -ne $null) {
                        $DomainToQuery.Add($DomainSiteConfiguration.Name,$DomainSiteConfiguration.Forest.name)
                        $DomainSiteConfiguration.Dispose()
                    }
                    foreach ($domTemp in $ExplicitDomainsNamesSearch) {
                        $domTemp = $domTemp.Trim()
                        if (-not $DomainToQuery."$domTemp") {
                            $DomainContextTemp = [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new([System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Domain, $domTemp)
                            try {
                                $domainTempSiteConfiguration = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($DomainContextTemp)
                                $DomainToQuery.Add($domTemp,$domainTempSiteConfiguration.Forest.name)
                                $domainTempSiteConfiguration.Dispose()
                            } catch {
                                write-warning -Message ("Cannot query the domain " + $domTemp + " : " + $_.Exception.message)
                            }
                        }
                    }
                }
            }
        }
        #end switch statement we control that we have some domain to equery to keep on
        #so first we add in the direct membership the meberof of the adobject in its domain
        $DomRefofCurrentObjectToControlMemberOf = $InitialADObjectResult.properties.distinguishedname -split "DC="
        $DomRefofCurrentObjectToControlMemberOf = ($DomRefofCurrentObjectToControlMemberOf[1 .. ($DomRefofCurrentObjectToControlMemberOf.count-1)] -join ".") -replace ",",""
        #as we don t find the builtin domain user or computer in the direct memberof we can incliude the switch to search as well that group
        #so we had it as direct member not nested and we had the group as well to pefrom the search in the while loop for nested groups
        if ($Include -eq "IncludeDomainUsersBuiltinGroup" -or $include -eq "IncludeDomainComputersBuiltinGroup") {
            if ($Include -eq "IncludeDomainUsersBuiltinGroup") {
                $InitialADObjectResult.properties.memberof += "DomainUsers"
            } 
            if ($Include -eq "IncludeDomainComputersBuiltinGroup") {
                $InitialADObjectResult.properties.memberof += "DomainComputers"
            }
        }
        if ($InitialADObjectResult.properties.memberof) {
            $InitialADObjectResult.properties.memberof | %{
                if ($psitem -eq "DomainUsers") {
                    $Searcher.Filter = "(samaccountname=Domain users)"
                } elseif ($psitem -eq "DomainComputers") {
                    $Searcher.Filter = "(samaccountname=Domain computers)"
                } else {
                    $Searcher.Filter = "(distinguishedName=" + $psitem + ")"
                }
                $Searcher.SearchRoot = "LDAP://" + $DomRefofCurrentObjectToControlMemberOf
                $resultTemp = $Searcher.FindOne()
                if ($resultTemp -ne $null) {
                    if ($resultTemp.properties.memberof) {
                        $resultTemp.properties.memberof.Foreach({
                            $listBFS.add($psitem)
                            $memberOfTemp.add($psitem)
                        })
                    }
                    #in order to populate the property member of of this current object we do search in other domains and we will pass as well not to mutiplicate query stores these objects into an hastable
                    $keySID = (New-Object System.Security.Principal.SecurityIdentifier($resultTemp.properties.objectsid[0], 0)).toString()
                    $DomainToQuery.keys.ForEach({
                        $DomTarget = $psitem
                        if ($DomTarget -ne $DomRefofCurrentObjectToControlMemberOf) {
                            if ($DomainToQuery."$DomTarget" -eq $DomainToQuery."$DomRefofCurrentObjectToControlMemberOf") {
                                $Searcher.Filter = "(member=" + $resultTemp.properties.distinguishedname + ")"
                                $Searcher.SearchRoot = "LDAP://" + $DomTarget
                                $resultTempSec = $Searcher.FindAll()
                                if ($resultTempSec -ne $null) {
                                    foreach ($item in $resultTempSec) {
                                        $dn = $item.properties.distinguishedname.Trim()
                                        $listBFS.add($item.properties.distinguishedname)
                                        $memberOfTemp.add($item.properties.distinguishedname)
                                        if (-not ($ObjectAlreadyQueried."$dn")) {
                                            $ObjectAlreadyQueried.add([string]$dn,$item.properties)
                                        }
                                    }
                                }
                            } else {
                                #adobject is not in same forest ot targeted queried domain so we search based on dn but FSP
                                $domTargetTable = $domtarget -split "\."
                                $dnFSP = "CN=" + $keySID + ",CN=ForeignSecurityPrincipals"
                                foreach ($partDom in $domTargetTable) {
                                    $dnFSP += ",DC=" + $partDom
                                }
                                $Searcher.Filter = "(member=" + $dnFSP + ")"
                                $Searcher.SearchRoot = "LDAP://" + $DomTarget
                                $resultTempSec = $Searcher.FindAll()
                                if ($resultTempSec -ne $null) {
                                    foreach ($item in $resultTempSec) {
                                        $dn = $item.properties.distinguishedname.Trim()
                                        $listBFS.add($item.properties.distinguishedname)
                                        $memberOfTemp.add($item.properties.distinguishedname)
                                        if (-not ($ObjectAlreadyQueried."$dn")) {
                                            $ObjectAlreadyQueried.add([string]$dn,$item.properties)
                                        }
                                    }
                                }
                            }
                        }                        
                    })
                    if ($memberOfTemp.count -gt 0) {$memberOf = $memberOfTemp -join "`r`n"} else {$memberOf = [string]::Empty}
                    #assessment of grouptype in order to avoid the search in the other domain if it is a domain local group and provide with the information in the results
                    $grouptype = "undefined"
                    switch ($resultTemp.properties.grouptype[0]) {
                        2 {$grouptype = "GlobalDistribution";break}
                        4 {$grouptype = "DomainLocalDistribution";break}
                        8 {$grouptype = "UniversalDistribution";break}
                        -2147483646 {$grouptype = "GlobalSecurity";break}
                        -2147483644 {$grouptype = "DomainLocalSecurity";break}
                        -2147483640 {$grouptype = "UniversalSecurity"}
                    }
                    $resultTemp.properties.groutypedescription = $grouptype
                    $resultTemp.properties.visited = $true
                    $resultTemp.properties.sid = $keySID
                    $resultTemp.properties.membership = "Direct"
                    $resultTemp.properties.shortestnestingLevel = [string]$nestingLevel
                    $resultTemp.properties.domain = $DomRefofCurrentObjectToControlMemberOf
                    $resultTemp.properties.memberof = $memberOf
                    $ObjectAlreadyQueried.add([string]$resultTemp.properties.distinguishedname.Trim(),$resultTemp.properties)
                    $memberOfTemp.Clear()
                }
            }
        }
        #now we perform the user direct membership in the other domains
        $DomainToQuery.keys.ForEach({
            $DomTargetMain = $psitem
            if ($DomTargetMain -ne $DomRefofCurrentObjectToControlMemberOf) {
                if ($DomainToQuery."$DomTargetMain" -eq $DomainToQuery."$DomRefofCurrentObjectToControlMemberOf") {
                    $Searcher.Filter = "(member=" + $InitialADObjectResult.properties.distinguishedname + ")"
                    $Searcher.SearchRoot = "LDAP://" + $DomTargetMain
                    $resultTemp = $Searcher.FindAll()
                    if ($resultTemp -ne $null) {
                        foreach ($item in $resultTemp) {
                            $dn = $item.properties.distinguishedname.Trim()
                            if ($ObjectAlreadyQueried."$dn" -and -not($ObjectAlreadyQueried."$dn".visited)) {
                                $item = $ObjectAlreadyQueried."$dn"
                            } else {
                                $item = $item.properties
                            }
                            $DomRefofCurrentGroup = $item.distinguishedname -split "DC="
                            $DomRefofCurrentGroup = ($DomRefofCurrentGroup[1 .. ($DomRefofCurrentGroup.count-1)] -join ".") -replace ",",""
                            $keySID = (New-Object System.Security.Principal.SecurityIdentifier($item.objectsid[0], 0)).toString()
                            if ($item.memberof) {
                                $item.memberof.Foreach({
                                    $listBFS.add($psitem)
                                    $memberOfTemp.add($psitem)
                                })
                            }
                            #we don t look in other domain for domain local groups memrships
                            if ($item.grouptype[0] -ne 2 -and $item.grouptype[0] -ne -2147483644) {
                                $DomainToQuery.keys.ForEach({
                                    $domTarget = $psitem
                                    if ($DomTarget -ne $DomRefofCurrentGroup) {
                                        if ($DomainToQuery."$DomTarget" -eq $DomainToQuery."$DomRefofCurrentGroup") {
                                            $Searcher.Filter = "(member=" + $item.distinguishedname + ")"
                                            $Searcher.SearchRoot = "LDAP://" + $DomTarget
                                            $resultTempSec = $Searcher.FindAll()
                                            if ($resultTempSec -ne $null) {
                                                foreach ($itemT in $resultTempSec) {
                                                    $dn = $itemT.properties.distinguishedname.Trim()
                                                    $listBFS.add($itemT.properties.distinguishedname)
                                                    $memberOfTemp.add($itemT.properties.distinguishedname)
                                                    if (-not ($ObjectAlreadyQueried."$dn")) {
                                                        $ObjectAlreadyQueried.add([string]$dn,$itemT.properties)
                                                    }
                                                }
                                            }
                                        } else {
                                            #adobject is not in same forest ot targeted queried domain so we search based on dn but FSP
                                            $domTargetTable = $domtarget -split "\."
                                            $dnFSP = "CN=" + $keySID + ",CN=ForeignSecurityPrincipals"
                                            foreach ($partDom in $domTargetTable) {
                                                $dnFSP += ",DC=" + $partDom
                                            }
                                            $Searcher.Filter = "(member=" + $dnFSP + ")"
                                            $Searcher.SearchRoot = "LDAP://" + $DomTarget
                                            $resultTempSec = $Searcher.FindAll()
                                            if ($resultTempSec -ne $null) {
                                                foreach ($item in $resultTempSec) {
                                                    $dn = $item.properties.distinguishedname.Trim()
                                                    $listBFS.add($item.properties.distinguishedname)
                                                    $memberOfTemp.add($item.properties.distinguishedname)
                                                    if (-not ($ObjectAlreadyQueried."$dn")) {
                                                        $ObjectAlreadyQueried.add([string]$dn,$item.properties)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                })
                            }
                            if ($memberOfTemp.count -gt 0) {$memberOf = $memberOfTemp -join "`r`n"} else {$memberOf = [string]::Empty}
                            $grouptype = "undefined"
                            switch ($item.grouptype[0]) {
                                2 {$grouptype = "GlobalDistribution";break}
                                4 {$grouptype = "DomainLocalDistribution";break}
                                8 {$grouptype = "UniversalDistribution";break}
                                -2147483646 {$grouptype = "GlobalSecurity";break}
                                -2147483644 {$grouptype = "DomainLocalSecurity";break}
                                -2147483640 {$grouptype = "UniversalSecurity"}
                            }
                            $item.groutypedescription = $grouptype
                            $item.visited = $true
                            $item.sid = $keySID
                            $item.membership = "Direct"
                            $item.shortestnestingLevel = [string]$nestingLevel
                            $item.domain = $DomRefofCurrentGroup
                            $item.memberof = $memberOf
                            if (-not ($ObjectAlreadyQueried."$dn")) {$ObjectAlreadyQueried.add([string]$item.distinguishedname,$item)}
                            $memberOfTemp.Clear()
                        }
                    }
                } else {
                    $keySID = (New-Object System.Security.Principal.SecurityIdentifier($InitialADObjectResult.properties.objectsid[0], 0)).toString()
                    $domTargetTable = $DomTargetMain -split "\."
                    $dnFSP = "CN=" + $keySID + ",CN=ForeignSecurityPrincipals"
                    foreach ($partDom in $domTargetTable) {
                        $dnFSP += ",DC=" + $partDom
                    }
                    $Searcher.Filter = "(member=" + $dnFSP + ")"
                    $Searcher.SearchRoot = "LDAP://" + $DomTargetMain
                    $resultTemp = $Searcher.FindAll()
                    if ($resultTemp -ne $null) {
                        foreach ($item in $resultTemp.properties) {
                            try {$dn = $item.properties.distinguishedname} catch {$dn = $item.distinguishedname}
                            if ($ObjectAlreadyQueried."$dn" -and -not($ObjectAlreadyQueried."$dn".visited)) {
                                $item = $ObjectAlreadyQueried."$dn"
                            } else {
                                if ($item.properties) {
                                    $item = $item.properties
                                }
                            }
                            $DomRefofCurrentGroup = $item.distinguishedname -split "DC="
                            $DomRefofCurrentGroup = ($DomRefofCurrentGroup[1 .. ($DomRefofCurrentGroup.count-1)] -join ".") -replace ",",""
                            $keySID = (New-Object System.Security.Principal.SecurityIdentifier($item.objectsid[0], 0)).toString()
                            if ($item.memberof) {
                                $item.memberof.Foreach({
                                    $listBFS.add($psitem)
                                    $memberOfTemp.add($psitem)
                                })
                            }
                            if ($item.grouptype[0] -ne 2 -and $item.grouptype[0] -ne -2147483644) {
                                $DomainToQuery.keys.ForEach({
                                    $domTarget = $psitem
                                    if ($DomTarget -ne $DomRefofCurrentGroup) {
                                        if ($DomainToQuery."$DomTarget" -eq $DomainToQuery."$DomRefofCurrentGroup") {
                                            $Searcher.Filter = "(member=" + $item.distinguishedname + ")"
                                            $Searcher.SearchRoot = "LDAP://" + $DomTarget
                                            $resultTempSec = $Searcher.FindAll()
                                            if ($resultTempSec -ne $null) {
                                                foreach ($itemT in $resultTempSec) {
                                                    try {$dn = $itemT.distinguishedname} catch {$dn = $itemT.properties.distinguishedname}
                                                    $listBFS.add($dn)
                                                    $memberOfTemp.add($dn)
                                                    if (-not ($ObjectAlreadyQueried."$dn")) {
                                                        $ObjectAlreadyQueried.add([string]$dn,$itemT.properties)
                                                    }
                                                }
                                            }
                                        } else {
                                            #adobject is not in same forest ot targeted queried domain so we search based on dn but FSP
                                            $domTargetTable = $domtarget -split "\."
                                            $dnFSP = "CN=" + $keySID + ",CN=ForeignSecurityPrincipals"
                                            foreach ($partDom in $domTargetTable) {
                                                $dnFSP += ",DC=" + $partDom
                                            }
                                            $Searcher.Filter = "(member=" + $dnFSP + ")"
                                            $Searcher.SearchRoot = "LDAP://" + $DomTarget
                                            $resultTempSec = $Searcher.FindAll()
                                            if ($resultTempSec -ne $null) {
                                                foreach ($item in $resultTempSec) {
                                                    try {$dn = $item.distinguishedname} catch {$dn = $item.properties.distinguishedname}
                                                    $listBFS.add($dn)
                                                    $memberOfTemp.add($dn)
                                                    if (-not ($ObjectAlreadyQueried."$dn")) {
                                                        if ($item.properties) {
                                                            $ObjectAlreadyQueried.add([string]$dn,$item.properties)
                                                        } else {
                                                            $ObjectAlreadyQueried.add([string]$dn,$item)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                })
                            }
                            if ($memberOfTemp.count -gt 0) {$memberOf = $memberOfTemp -join "`r`n"} else {$memberOf = [string]::Empty}
                            $grouptype = "undefined"
                            switch ($resultTemp.properties.grouptype[0]) {
                                2 {$grouptype = "GlobalDistribution";break}
                                4 {$grouptype = "DomainLocalDistribution";break}
                                8 {$grouptype = "UniversalDistribution";break}
                                -2147483646 {$grouptype = "GlobalSecurity";break}
                                -2147483644 {$grouptype = "DomainLocalSecurity";break}
                                -2147483640 {$grouptype = "UniversalSecurity"}
                            }
                            $item.groutypedescription = $grouptype
                            $dn = $item.distinguishedname.Trim()
                            $item.visited = $true
                            $item.sid = $keySID
                            $item.membership = "Direct"
                            $item.shortestnestingLevel = [string]$nestingLevel
                            $item.domain = $DomRefofCurrentGroup
                            $item.memberof = $memberOf
                            if (-not ($ObjectAlreadyQueried."$dn")) {$ObjectAlreadyQueried.add([string]$dn,$item)}                    
                            $memberOfTemp.Clear()
                        }
                    }
                }
            }
        })
        $SwitchListToTsil = $true
        $listREF = $listBFS
        $listFurther = $tsilBFS
        do {
            #we control direct membership in the other domains and populate the list for shorttestnestinglevel = 1 and proceed the meberof of these groups to complete object in the collection
            $nestingLevel = $nestingLevel + 1
            While ($listREF.count -gt 0) {
                    $currentDN = $listREF[0].Trim()
                    if ($ObjectAlreadyQueried."$currentDN") {
                        if ($ObjectAlreadyQueried."$currentDN".visited -ne $true) {
                            $currentObject = $ObjectAlreadyQueried."$currentDN"
                            $DomRefofCurrentGroupMain = $currentObject.distinguishedname -split "DC="
                            $DomRefofCurrentGroupMain = ($DomRefofCurrentGroupMain[1 .. ($DomRefofCurrentGroupMain.count-1)] -join ".") -replace ",",""
                            $keySID = (New-Object System.Security.Principal.SecurityIdentifier($currentObject.objectsid[0], 0)).toString()
                            if ($currentObject.memberof) {
                                $currentObject.memberof.Foreach({
                                    $listFurther.add($psitem)
                                    $memberOfTemp.add($psitem)
                                })
                            }
                            if ($currentObject.grouptype[0] -ne 2 -and $currentObject.grouptype[0] -ne -2147483644) {
                                $DomainToQuery.keys.ForEach({
                                    $domTarget = $psitem
                                    if ($DomTarget -ne $DomRefofCurrentGroupMain) {
                                        if ($DomainToQuery."$DomTarget" -eq $DomainToQuery."$DomRefofCurrentGroupMain") {
                                            $Searcher.Filter = "(member=" + $currentObject.distinguishedname + ")"
                                            $Searcher.SearchRoot = "LDAP://" + $DomTarget
                                            $resultTempSec = $Searcher.FindAll()
                                            if ($resultTempSec -ne $null) {
                                                foreach ($itemT in $resultTempSec) {
                                                    $dn = $itemT.properties.distinguishedname.Trim()
                                                    $listFurther.add($itemT.properties.distinguishedname)
                                                    $memberOfTemp.add($itemT.properties.distinguishedname)
                                                    if (-not ($ObjectAlreadyQueried."$dn")) {
                                                        $ObjectAlreadyQueried.add([string]$dn,$itemT.properties)
                                                    }
                                                }
                                            }
                                        } else {
                                            #adobject is not in same forest ot targeted queried domain so we search based on dn but FSP
                                            $domTargetTable = $domtarget -split "\."
                                            $dnFSP = "CN=" + $keySID + ",CN=ForeignSecurityPrincipals"
                                            foreach ($partDom in $domTargetTable) {
                                                $dnFSP += ",DC=" + $partDom
                                            }
                                            $Searcher.Filter = "(member=" + $dnFSP + ")"
                                            $Searcher.SearchRoot = "LDAP://" + $DomTarget
                                            $resultTempSec = $Searcher.FindAll()
                                            if ($resultTempSec -ne $null) {
                                                foreach ($item in $resultTempSec) {
                                                    $dn = $item.properties.distinguishedname.Trim()
                                                    $listFurther.add($item.properties.distinguishedname)
                                                    $memberOfTemp.add($item.properties.distinguishedname)
                                                    if (-not ($ObjectAlreadyQueried."$dn")) {
                                                        $ObjectAlreadyQueried.add([string]$dn,$item.properties)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                })
                            }
                            if ($memberOfTemp.count -gt 0) {$memberOf = $memberOfTemp -join "`r`n"} else {$memberOf = [string]::Empty}
                            $grouptype = "undefined"
                            switch ($currentObject.grouptype[0]) {
                                2 {$grouptype = "GlobalDistribution";break}
                                4 {$grouptype = "DomainLocalDistribution";break}
                                8 {$grouptype = "UniversalDistribution";break}
                                -2147483646 {$grouptype = "GlobalSecurity";break}
                                -2147483644 {$grouptype = "DomainLocalSecurity";break}
                                -2147483640 {$grouptype = "UniversalSecurity"}
                            }
                            $currentObject.groutypedescription = $grouptype
                            $currentObject.visited = $true
                            $currentObject.sid = $keySID
                            $currentObject.membership = "Nested"
                            $currentObject.shortestnestingLevel = [string]$nestingLevel
                            $currentObject.domain = $DomRefofCurrentGroupMain
                            $currentObject.memberof = $memberOf                        
                            $memberOfTemp.Clear()
                        }
                    } else {
                        $DomRefofCurrentGroupMain = $currentDN -split "DC="
                        $DomRefofCurrentGroupMain = ($DomRefofCurrentGroupMain[1 .. ($DomRefofCurrentGroupMain.count-1)] -join ".") -replace ",",""
                        $Searcher.Filter = "(distinguishedName=" + $currentDN + ")"
                        $Searcher.SearchRoot = "LDAP://" + $DomRefofCurrentGroupMain
                        $resultMain = $Searcher.FindOne()
                        if ($resultMain -ne $null) {
                            $currentObject = $resultMain.properties
                            $keySID = (New-Object System.Security.Principal.SecurityIdentifier($currentObject.objectsid[0], 0)).toString()
                            if ($currentObject.memberof) {
                                $currentObject.memberof.Foreach({
                                    $listFurther.add($psitem)
                                    $memberOfTemp.add($psitem)
                                })
                            }
                            if ($currentObject.grouptype[0] -ne 2 -and $currentObject.grouptype[0] -ne -2147483644) {
                                $DomainToQuery.keys.ForEach({
                                    $domTarget = $psitem
                                    if ($DomTarget -ne $DomRefofCurrentGroupMain) {
                                        if ($DomainToQuery."$DomTarget" -eq $DomainToQuery."$DomRefofCurrentGroupMain") {
                                            $Searcher.Filter = "(member=" + $currentObject.distinguishedname + ")"
                                            $Searcher.SearchRoot = "LDAP://" + $DomTarget
                                            $resultTempSec = $Searcher.FindAll()
                                            if ($resultTempSec -ne $null) {
                                                foreach ($itemT in $resultTempSec) {
                                                    $dn = $itemT.properties.distinguishedname.Trim()
                                                    $listFurther.add($itemT.properties.distinguishedname)
                                                    $memberOfTemp.add($itemT.properties.distinguishedname)
                                                    if (-not ($ObjectAlreadyQueried."$dn")) {
                                                        $ObjectAlreadyQueried.add([string]$dn,$itemT.properties)
                                                    }
                                                }
                                            }
                                        } else {
                                            #adobject is not in same forest ot targeted queried domain so we search based on dn but FSP
                                            $domTargetTable = $domtarget -split "\."
                                            $dnFSP = "CN=" + $keySID + ",CN=ForeignSecurityPrincipals"
                                            foreach ($partDom in $domTargetTable) {
                                                $dnFSP += ",DC=" + $partDom
                                            }
                                            $Searcher.Filter = "(member=" + $dnFSP + ")"
                                            $Searcher.SearchRoot = "LDAP://" + $DomTarget
                                            $resultTempSec = $Searcher.FindAll()
                                            if ($resultTempSec -ne $null) {
                                                foreach ($item in $resultTempSec) {
                                                    $dn = $item.properties.distinguishedname.Trim()
                                                    $listFurther.add($item.properties.distinguishedname)
                                                    $memberOfTemp.add($item.properties.distinguishedname)
                                                    if (-not ($ObjectAlreadyQueried."$dn")) {
                                                        $ObjectAlreadyQueried.add([string]$dn,$item.properties)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                })
                            }
                            if ($memberOfTemp.count -gt 0) {$memberOf = $memberOfTemp -join "`r`n"} else {$memberOf = [string]::Empty}
                            $grouptype = "undefined"
                            switch ($currentObject.grouptype[0]) {
                                2 {$grouptype = "GlobalDistribution";break}
                                4 {$grouptype = "DomainLocalDistribution";break}
                                8 {$grouptype = "UniversalDistribution";break}
                                -2147483646 {$grouptype = "GlobalSecurity";break}
                                -2147483644 {$grouptype = "DomainLocalSecurity";break}
                                -2147483640 {$grouptype = "UniversalSecurity"}
                            }
                            $currentObject.groutypedescription = $grouptype
                            $currentObject.visited = $true
                            $currentObject.sid = $keySID
                            $currentObject.membership = "Nested"
                            $currentObject.shortestnestingLevel = [string]$nestingLevel
                            $currentObject.domain = $DomRefofCurrentGroupMain
                            $currentObject.memberof = $memberOf
                            if (-not($ObjectAlreadyQueried."$currentDN")) {$ObjectAlreadyQueried.add([string]$currentObject.distinguishedname.Trim(),$currentObject)}
                            $memberOfTemp.Clear()
                        }
                    }
                    $listREF.Remove($listREF[0]) | out-null
            }
            if ($SwitchListToTsil -eq $true) {
                $listREF = $tsilBFS
                $listFurther = $listBFS
                $SwitchListToTsil = $false
            } else {
                $listREF = $listBFS
                $listFurther = $tsilBFS
                $SwitchListToTsil = $true
            }
        } while ($listBFS.count -gt 0 -or $tsilBFS.count -gt 0)        
    }
    if ($ObjectAlreadyQueried) {
        foreach ($CollectedItem in $ObjectAlreadyQueried.GetEnumerator()) {
            if ($CollectedItem.value.description) {
                $description = [string]$CollectedItem.value.description
            } else {
                $description = [string]::Empty
            }
            $resutls.add((
                new-object psobject -property @{
                    Domain = $CollectedItem.value.domain
                    Membership = $CollectedItem.value.membership
                    ShortestNestingLevel = $CollectedItem.value.shortestnestingLevel
                    GroupName = [string]$CollectedItem.value.name
                    SamAccountName = [string]$CollectedItem.value.samaccountname
                    GroupType = $CollectedItem.value.groutypedescription
                    distinguishedname = [string]$CollectedItem.value.distinguishedname
                    objectclass = [string]$CollectedItem.value.objectclass
                    whencreated = [string]$CollectedItem.value.whencreated
                    whenchanged = [string]$CollectedItem.value.whenchanged
                    Sid = $CollectedItem.value.sid
                    MemberOf = $CollectedItem.value.memberof
                    Description = $description
                }
            ))
        }
    }
    #we dispose the directory searcher
    $Searcher.Dispose()
    if ($resutls) {return $resutls}
}