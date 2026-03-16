public with sharing class CMEmailSimulationController {
    private static final Integer SEARCH_LIMIT = 100;
    private static final Integer MAX_ACCOUNTS_PER_RUN = 20;

    @AuraEnabled(cacheable=true)
    public static List<AccountOption> searchAccounts(String searchTerm) {
        String normalized = searchTerm == null ? '' : searchTerm.trim();
        List<Account> accounts;

        if (String.isBlank(normalized)) {
            accounts = [
                SELECT Id, Name, Industry, Type
                FROM Account
                ORDER BY LastModifiedDate DESC
                LIMIT :SEARCH_LIMIT
            ];
        } else {
            String likeTerm = '%' + normalized + '%';
            accounts = [
                SELECT Id, Name, Industry, Type
                FROM Account
                WHERE Name LIKE :likeTerm
                ORDER BY Name
                LIMIT :SEARCH_LIMIT
            ];
        }

        Map<Id, Integer> countsByAccountId = getEmailCounts(accounts);
        List<AccountOption> rows = new List<AccountOption>();
        for (Account accountRow : accounts) {
            AccountOption dto = new AccountOption();
            dto.id = accountRow.Id;
            dto.name = accountRow.Name;
            dto.industry = accountRow.Industry;
            dto.type = accountRow.Type;
            dto.emailActivityCount = countsByAccountId.containsKey(accountRow.Id)
                ? countsByAccountId.get(accountRow.Id)
                : 0;
            rows.add(dto);
        }
        return rows;
    }

    @AuraEnabled
    public static List<SimulationResult> runSimulation(
        List<Id> accountIds,
        Integer emailCount,
        String simulationDirection,
        String department,
        String startDate,
        String endDate
    ) {
        if (accountIds == null || accountIds.isEmpty()) {
            throw new AuraHandledException('Please select at least one Account.');
        }
        if (accountIds.size() > MAX_ACCOUNTS_PER_RUN) {
            throw new AuraHandledException('You can run up to 20 Accounts per execution.');
        }

        Map<Id, Account> accountsById = new Map<Id, Account>([
            SELECT Id, Name
            FROM Account
            WHERE Id IN :accountIds
        ]);

        List<SimulationResult> results = new List<SimulationResult>();

        for (Id accountId : accountIds) {
            SimulationResult result = new SimulationResult();
            result.accountId = accountId;
            result.accountName = accountsById.containsKey(accountId) ? accountsById.get(accountId).Name : String.valueOf(accountId);

            try {
                if (!accountsById.containsKey(accountId)) {
                    throw new AuraHandledException('Account no longer exists.');
                }

                result.deletedCount = deleteExistingEmails(accountId);

                CMEmailTimelineSimulationService.Request requestItem =
                    new CMEmailTimelineSimulationService.Request();
                requestItem.accountId = accountId;
                requestItem.backgroundContext = null;
                requestItem.emailCount = emailCount;
                requestItem.simulationDirection = simulationDirection;
                requestItem.department = department;
                requestItem.startDate = startDate;
                requestItem.endDate = endDate;

                List<CMEmailTimelineSimulationService.Result> generated =
                    CMEmailTimelineSimulationService.generateSimulatedEmailTimelineData(
                        new List<CMEmailTimelineSimulationService.Request>{ requestItem }
                    );
                CMEmailTimelineSimulationService.Result generatedResult =
                    generated.isEmpty() ? null : generated[0];

                result.createdCount = generatedResult == null || generatedResult.createdCount == null
                    ? 0
                    : generatedResult.createdCount;
                result.message = generatedResult == null ? 'No generation result.' : generatedResult.message;
                result.status = result.createdCount > 0 ? 'Success' : 'Failed';
            } catch (Exception ex) {
                result.createdCount = 0;
                result.status = 'Failed';
                result.message = ex.getMessage();
            }

            results.add(result);
        }

        return results;
    }

    private static Map<Id, Integer> getEmailCounts(List<Account> accounts) {
        Map<Id, Integer> countsByAccountId = new Map<Id, Integer>();
        if (accounts.isEmpty()) {
            return countsByAccountId;
        }

        Set<Id> accountIds = new Set<Id>();
        for (Account accountRow : accounts) {
            accountIds.add(accountRow.Id);
        }

        for (AggregateResult row : [
            SELECT RelatedToId accountId, COUNT(Id) total
            FROM EmailMessage
            WHERE RelatedToId IN :accountIds
            GROUP BY RelatedToId
        ]) {
            countsByAccountId.put(
                (Id) row.get('accountId'),
                Integer.valueOf(String.valueOf(row.get('total')))
            );
        }

        return countsByAccountId;
    }

    private static Integer deleteExistingEmails(Id accountId) {
        List<EmailMessage> existingEmails = [
            SELECT Id
            FROM EmailMessage
            WHERE RelatedToId = :accountId
            ORDER BY CreatedDate DESC
            LIMIT 10000
        ];
        if (existingEmails.isEmpty()) {
            return 0;
        }

        Integer deletedCount = 0;
        for (Database.DeleteResult deleteResult : Database.delete(existingEmails, false)) {
            if (deleteResult.isSuccess()) {
                deletedCount++;
            }
        }
        return deletedCount;
    }

    public class AccountOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String industry;
        @AuraEnabled public String type;
        @AuraEnabled public Integer emailActivityCount;
    }

    public class SimulationResult {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Integer deletedCount;
        @AuraEnabled public Integer createdCount;
        @AuraEnabled public String status;
        @AuraEnabled public String message;
    }
}
