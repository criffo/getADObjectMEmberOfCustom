#POWERSHELL FUNCTIONS TO GET RECURSIVELY AN AD OBJECT GROUPS MEMBERSHIPS

Both function are based on the ldap directory searcher and do not need active directory module

Function: Get-ADObjectMemberOfRecurseByBFS

It is based on a BFS approach by getting member of attributes of object first then groups recusrively
The result is a list with defined attributes. A nesting level and partial tree memberof is captured as attributes
The initial query is completed by loads of queries depending on the number of domain, forest and trusts
Parametter can narrow down or expand the ressearch and explicit domain search can be defined

Function: Get-ADObjectMemberOfRecurseByLDAPInChain

It is based on DB query with the FLAG LDAPINCHAIN-
The result is a Resutl Searcher Collection
As parameters serie of doamin can be included in the search
