public without sharing class CMQBRTranscriptResolver {
    private static final String STATUS_COMPLETED = 'Completed';

    public class Request {
        @InvocableVariable(required=true)
        public Id accountId;
    }

    public class Response {
        @InvocableVariable
        public String transcript;

        @InvocableVariable
        public String status;

        @InvocableVariable
        public String message;
    }

    @InvocableMethod(label='Resolve QBR Transcript From Demo Setup')
    public static List<Response> resolveForFlow(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null) {
            return responses;
        }

        Set<Id> accountIds = new Set<Id>();
        for (Request requestItem : requests) {
            if (requestItem != null && requestItem.accountId != null) {
                accountIds.add(requestItem.accountId);
            }
        }

        Map<Id, String> transcriptByAccount = resolveByAccount(accountIds);

        for (Request requestItem : requests) {
            Response response = new Response();
            Id accountId = requestItem == null ? null : requestItem.accountId;
            if (accountId == null) {
                response.status = 'Failed';
                response.message = 'Account Id is required.';
            } else {
                response.transcript = transcriptByAccount.get(accountId);
                if (String.isBlank(response.transcript)) {
                    response.status = 'Missing';
                    response.message = 'No setup transcript found for this account.';
                } else {
                    response.status = 'Found';
                }
            }
            responses.add(response);
        }

        return responses;
    }

    public static String resolveForAccount(Id accountId) {
        if (accountId == null) {
            return null;
        }
        Map<Id, String> transcriptByAccount = resolveByAccount(new Set<Id>{ accountId });
        return transcriptByAccount.get(accountId);
    }

    public static Map<Id, String> resolveByAccount(Set<Id> accountIds) {
        return resolveByAccount(accountIds, getActiveDemoTargetAccountId());
    }

    public static Map<Id, String> resolveByAccount(Set<Id> accountIds, Id focusCompanyId) {
        Map<Id, String> transcriptByAccount = new Map<Id, String>();
        if (accountIds == null || accountIds.isEmpty() || focusCompanyId == null) {
            return transcriptByAccount;
        }

        for (CM_Meeting_Transcript__c transcript : [
            SELECT Counterparty_Account__c, Transcript__c, Generated_At__c, LastModifiedDate
            FROM CM_Meeting_Transcript__c
            WHERE Focus_Company__c = :focusCompanyId
              AND Counterparty_Account__c IN :accountIds
              AND Status__c = :STATUS_COMPLETED
            ORDER BY Counterparty_Account__c, Generated_At__c DESC, LastModifiedDate DESC
            LIMIT 2000
        ]) {
            Id counterpartyId = transcript.Counterparty_Account__c;
            if (
                counterpartyId != null &&
                !String.isBlank(transcript.Transcript__c) &&
                !transcriptByAccount.containsKey(counterpartyId)
            ) {
                transcriptByAccount.put(counterpartyId, transcript.Transcript__c);
            }
        }

        return transcriptByAccount;
    }

    public static Id getActiveDemoTargetAccountId() {
        List<Account> activeTargets = [
            SELECT Id
            FROM Account
            WHERE CM_Is_Demo_Target__c = true
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return activeTargets.isEmpty() ? null : activeTargets[0].Id;
    }
}
