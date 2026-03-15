public with sharing class CMAccountRoleSetupController {
    private static final Integer SEARCH_LIMIT = 50;
    private static final List<String> ROLE_ORDER = new List<String>{
        'Customer',
        'Supplier',
        'Partner'
    };
    private static final Set<String> ALLOWED_ROLES = new Set<String>(ROLE_ORDER);

    @AuraEnabled
    public static List<AccountRoleOption> searchAccounts(String searchTerm) {
        String normalized = searchTerm == null ? '' : searchTerm.trim();
        List<Account> accounts;

        if (String.isBlank(normalized)) {
            accounts = [
                SELECT Id, Name, Type, Industry, CM_Account_Roles__c
                FROM Account
                ORDER BY LastModifiedDate DESC
                LIMIT :SEARCH_LIMIT
            ];
        } else {
            String likeTerm = '%' + normalized + '%';
            accounts = [
                SELECT Id, Name, Type, Industry, CM_Account_Roles__c
                FROM Account
                WHERE Name LIKE :likeTerm
                ORDER BY Name
                LIMIT :SEARCH_LIMIT
            ];
        }

        List<AccountRoleOption> results = new List<AccountRoleOption>();
        for (Account account : accounts) {
            results.add(toDto(account));
        }
        return results;
    }

    @AuraEnabled
    public static List<AccountRoleOption> saveAccountRoles(List<Id> accountIds, List<String> roles) {
        if (accountIds == null || accountIds.isEmpty()) {
            throw new AuraHandledException('Please select at least one Account.');
        }

        Set<Id> uniqueIds = new Set<Id>(accountIds);
        List<String> normalizedRoles = normalizeRoles(roles);
        String roleValue = normalizedRoles.isEmpty() ? null : String.join(normalizedRoles, ';');

        List<Account> accountsToUpdate = [
            SELECT Id, CM_Account_Roles__c
            FROM Account
            WHERE Id IN :uniqueIds
            FOR UPDATE
        ];

        if (accountsToUpdate.isEmpty()) {
            throw new AuraHandledException('Selected Accounts were not found.');
        }

        for (Account account : accountsToUpdate) {
            account.CM_Account_Roles__c = roleValue;
        }

        update accountsToUpdate;

        List<AccountRoleOption> results = new List<AccountRoleOption>();
        for (Account account : [
            SELECT Id, Name, Type, Industry, CM_Account_Roles__c
            FROM Account
            WHERE Id IN :uniqueIds
            ORDER BY Name
        ]) {
            results.add(toDto(account));
        }
        return results;
    }

    private static List<String> normalizeRoles(List<String> roles) {
        Set<String> requested = new Set<String>();
        if (roles != null) {
            for (String role : roles) {
                String normalized = role == null ? '' : role.trim();
                if (String.isBlank(normalized)) {
                    continue;
                }
                if (!ALLOWED_ROLES.contains(normalized)) {
                    throw new AuraHandledException('Unsupported role: ' + normalized);
                }
                requested.add(normalized);
            }
        }

        List<String> ordered = new List<String>();
        for (String role : ROLE_ORDER) {
            if (requested.contains(role)) {
                ordered.add(role);
            }
        }
        return ordered;
    }

    private static List<String> parseRoles(String roles) {
        if (String.isBlank(roles)) {
            return new List<String>();
        }

        Set<String> parsed = new Set<String>();
        for (String rawRole : roles.split(';')) {
            String normalized = rawRole == null ? '' : rawRole.trim();
            if (!String.isBlank(normalized) && ALLOWED_ROLES.contains(normalized)) {
                parsed.add(normalized);
            }
        }

        List<String> ordered = new List<String>();
        for (String role : ROLE_ORDER) {
            if (parsed.contains(role)) {
                ordered.add(role);
            }
        }
        return ordered;
    }

    private static AccountRoleOption toDto(Account account) {
        List<String> roleValues = parseRoles(account.CM_Account_Roles__c);

        AccountRoleOption dto = new AccountRoleOption();
        dto.id = account.Id;
        dto.name = account.Name;
        dto.type = account.Type;
        dto.industry = account.Industry;
        dto.roles = account.CM_Account_Roles__c;
        dto.roleValues = roleValues;
        dto.roleSummary = roleValues.isEmpty() ? '' : String.join(roleValues, ', ');
        return dto;
    }

    public class AccountRoleOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String type;
        @AuraEnabled public String industry;
        @AuraEnabled public String roles;
        @AuraEnabled public List<String> roleValues;
        @AuraEnabled public String roleSummary;
    }
}