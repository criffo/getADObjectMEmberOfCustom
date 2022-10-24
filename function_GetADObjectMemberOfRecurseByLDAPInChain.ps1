function Get-ADObjectMemberOfRecurseByLDAPInChain {
        <#
        .SYNOPSIS
        Author  : Criffo
        Version : 1.0
        Gets memberof attribute recursively for an active directory object (computer,user,group)

        .DESCRIPTION
        Gets memberof attribute recusvely for an active directory object (computer,user,group)
        LDAP request via .Net classes, namespace System.DirectoryServices for the directory searcher and active dorectory classes, no need to import activedirectory module
        The search is based on LDAPInChain Flag
        A List of Domain can be supplied as an Array or List and if porperties more than ldap search result default these can be added as a list or array
        The function returns a SearchResult Collection object

        .PARAMETER Identity
        Specifies either the disitnguished name of the AD user or the samaccountname. Mandatory.

        .PARAMETER DomainOfObject
        Specifies the Full Qualified Domain Name (FQDN) of the AD object domain. Mandatory.

        .PARAMETER Domain
        Specifies an array of FQDN domains to perform the search in

        .PARAMETER Properties
        Specifies an array of properties to load in the SearchResult Collection

        .INPUTS
        None. You cannot pipe objects to Get-ADObjectMemberOfCustom.

        .OUTPUTS
        SearchResult Collection object

        .EXAMPLE
        C:\PS> Get-ADObjectMemberOfRecurseByLDAPInChain objectsamaccountname global.contoso.com global.contoso.com

        .EXAMPLE
        C:\PS> Get-ADObjectMemberOfRecurseByLDAPInChain objectsamaccountname global.contoso.com global.contoso.com,contoso.com,otherdomainotherforest member,memberof

        .EXAMPLE
        C:\PS> Get-ADObjectMemberOfRecurseByLDAPInChain objectdistinguishedname global.contoso.com global.contoso.com anyproperty

        .NOTES
            Author  : Criffo
            Version : 1.0
    #>
    param([string]$Identity,[string]$DomainOfObject,[string[]]$Domain,[string[]]$Properties)
    $results = new-object System.Collections.Generic.List[object]
    $root = [ADSI]"LDAP://$DomainOfObject"
    if ($Identity -match "DC=") {
        $search = new-Object System.DirectoryServices.DirectorySearcher($root,"(distinguishedName=$Identity)")
    } else {
        $search = new-Object System.DirectoryServices.DirectorySearcher($root,"(sAMAccountName=$Identity)")
    }
    $resultLDAP = $search.FindOne()
    if ($resultLDAP.properties.distinguishedname) {
        $userdn = $resultLDAP.properties.distinguishedname
        $search.PageSize = 1000
        foreach ($dom in $Domain) {
            $Search.SearchRoot = [ADSI]"LDAP://$dom"
            $strFilter = "(member:1.2.840.113556.1.4.1941:=$userdn)"
            $search.Filter = $strFilter
            $search.SearchScope = "Subtree"
            if ($propeties) {
                foreach ($i in $Properties)
                {
                    $search.PropertiesToLoad.Add($i) > $nul
                }
            }
            $colResults = $search.FindAll()
            foreach ($objResult in $colResults) {
                $ref = $objResult.Properties
                $results.add($ref)
            }
        }
    }
    $search.Dispose()
    return $results
}