#POWERSHELL FUNCTION getADObjectMEmberOfCustom
        
Gets memberof attribute recusvely for an active directory object (computer,user,group) 

LDAP request via .Net classes, namespace System.DirectoryServices for the directory searcher 
and active dorectory classes, no need to import activedirectory module        
Allows to include the domain users or computers membership as well         
It takes by default the forest level but the search can be restricted 
to domain scope or extended to domain and its trusts, forest and its trusts or explicit domains         
it returns void in case of no result, and in case of result, 
a list of object with string attributes for csv export.
