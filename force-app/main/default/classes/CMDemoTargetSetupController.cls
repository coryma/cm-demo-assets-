public with sharing class CMDemoTargetSetupController {
    private static final Integer SEARCH_LIMIT = 8;

    @AuraEnabled(cacheable=true)
    public static DemoTargetAccount getActiveDemoTarget() {
        List<Account> accounts = [
            SELECT
                Id,
                Name,
                Industry,
                Type,
                Website,
                Description,
                CM_Is_Demo_Target__c,
                CM_Supply_Scenario_Catalog__c
            FROM Account
            WHERE CM_Is_Demo_Target__c = true
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];

        return accounts.isEmpty() ? null : toDto(accounts[0]);
    }

    @AuraEnabled(cacheable=true)
    public static List<DemoTargetAccount> searchAccounts(String searchTerm) {
        String normalized = searchTerm == null ? '' : searchTerm.trim();
        List<Account> accounts;

        if (String.isBlank(normalized)) {
            accounts = [
                SELECT
                    Id,
                    Name,
                    Industry,
                    Type,
                    Website,
                    Description,
                    CM_Is_Demo_Target__c,
                    CM_Supply_Scenario_Catalog__c
                FROM Account
                ORDER BY LastModifiedDate DESC
                LIMIT :SEARCH_LIMIT
            ];
        } else {
            String likeTerm = '%' + normalized + '%';
            accounts = [
                SELECT
                    Id,
                    Name,
                    Industry,
                    Type,
                    Website,
                    Description,
                    CM_Is_Demo_Target__c,
                    CM_Supply_Scenario_Catalog__c
                FROM Account
                WHERE Name LIKE :likeTerm
                ORDER BY Name
                LIMIT :SEARCH_LIMIT
            ];
        }

        List<DemoTargetAccount> results = new List<DemoTargetAccount>();
        for (Account account : accounts) {
            results.add(toDto(account));
        }
        return results;
    }

    @AuraEnabled
    public static DemoTargetAccount setActiveDemoTarget(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Please select an Account.');
        }

        Account selected = [
            SELECT
                Id,
                Name,
                Industry,
                Type,
                Website,
                Description,
                CM_Is_Demo_Target__c,
                CM_Supply_Scenario_Catalog__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        List<Account> updates = new List<Account>();

        for (Account account : [
            SELECT Id, CM_Is_Demo_Target__c
            FROM Account
            WHERE CM_Is_Demo_Target__c = true
            AND Id != :accountId
        ]) {
            account.CM_Is_Demo_Target__c = false;
            updates.add(account);
        }

        if (selected.CM_Is_Demo_Target__c != true) {
            selected.CM_Is_Demo_Target__c = true;
            updates.add(selected);
        }

        if (!updates.isEmpty()) {
            update updates;
        }

        return toDto([
            SELECT
                Id,
                Name,
                Industry,
                Type,
                Website,
                Description,
                CM_Is_Demo_Target__c,
                CM_Supply_Scenario_Catalog__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ]);
    }

    @AuraEnabled
    public static DemoTargetAccount saveDemoTarget(
        Id accountId,
        String industry,
        String website,
        String description,
        String supplyScenarioCatalog
    ) {
        if (accountId == null) {
            throw new AuraHandledException('Please select an Account.');
        }

        Account selected = [
            SELECT
                Id,
                Name,
                Industry,
                Type,
                Website,
                Description,
                CM_Is_Demo_Target__c,
                CM_Supply_Scenario_Catalog__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
            FOR UPDATE
        ];

        List<Account> updates = new List<Account>();

        for (Account account : [
            SELECT Id, CM_Is_Demo_Target__c
            FROM Account
            WHERE CM_Is_Demo_Target__c = true
            AND Id != :accountId
        ]) {
            account.CM_Is_Demo_Target__c = false;
            updates.add(account);
        }

        selected.Industry = normalizeValue(industry);
        selected.Website = normalizeValue(website);
        selected.Description = normalizeValue(description);
        selected.CM_Supply_Scenario_Catalog__c = normalizeScenarioCatalog(
            supplyScenarioCatalog
        );
        selected.CM_Is_Demo_Target__c = true;
        updates.add(selected);

        update updates;

        return toDto([
            SELECT
                Id,
                Name,
                Industry,
                Type,
                Website,
                Description,
                CM_Is_Demo_Target__c,
                CM_Supply_Scenario_Catalog__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ]);
    }

    private static String normalizeValue(String value) {
        String normalized = value == null ? null : value.trim();
        return String.isBlank(normalized) ? null : normalized;
    }

    private static String normalizeScenarioCatalog(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        List<String> normalizedLines = new List<String>();
        String normalizedText = value.replace('\r', '\n');
        while (normalizedText.contains('\n\n')) {
            normalizedText = normalizedText.replace('\n\n', '\n');
        }

        for (String rawLine : normalizedText.split('\n')) {
            if (String.isBlank(rawLine)) {
                continue;
            }
            normalizedLines.add(rawLine.trim());
        }
        return normalizedLines.isEmpty() ? null : String.join(normalizedLines, '\n');
    }

    private static DemoTargetAccount toDto(Account account) {
        DemoTargetAccount dto = new DemoTargetAccount();
        dto.id = account.Id;
        dto.name = account.Name;
        dto.industry = account.Industry;
        dto.type = account.Type;
        dto.website = account.Website;
        dto.description = account.Description;
        dto.supplyScenarioCatalog = account.CM_Supply_Scenario_Catalog__c;
        dto.isDemoTarget = account.CM_Is_Demo_Target__c;

        List<String> missing = new List<String>();
        if (String.isBlank(account.Industry)) {
            missing.add('Industry');
        }
        if (String.isBlank(account.Website)) {
            missing.add('Website');
        }
        if (String.isBlank(account.Description)) {
            missing.add('Description');
        }
        if (String.isBlank(account.CM_Supply_Scenario_Catalog__c)) {
            missing.add('CM_Supply_Scenario_Catalog');
        }

        dto.hasContext = missing.isEmpty();
        dto.missingContext = String.join(missing, ', ');
        return dto;
    }

    public class DemoTargetAccount {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String industry;
        @AuraEnabled public String type;
        @AuraEnabled public String website;
        @AuraEnabled public String description;
        @AuraEnabled public String supplyScenarioCatalog;
        @AuraEnabled public Boolean isDemoTarget;
        @AuraEnabled public Boolean hasContext;
        @AuraEnabled public String missingContext;
    }
}
