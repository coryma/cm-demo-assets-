@IsTest
private class CMQBRTranscriptResolverTest {
    @IsTest
    static void resolveByAccountReturnsLatestCompletedTranscript() {
        Account focusCompany = new Account(
            Name = 'Focus Company',
            CM_Is_Demo_Target__c = true
        );
        Account supplier = new Account(Name = 'Supplier One');
        insert new List<Account>{ focusCompany, supplier };

        insert new CM_Meeting_Transcript__c(
            Focus_Company__c = focusCompany.Id,
            Counterparty_Account__c = supplier.Id,
            Status__c = 'Completed',
            Transcript__c = 'Older transcript',
            Generated_At__c = System.now().addHours(-2)
        );

        insert new CM_Meeting_Transcript__c(
            Focus_Company__c = focusCompany.Id,
            Counterparty_Account__c = supplier.Id,
            Status__c = 'Failed',
            Transcript__c = 'Failed transcript should be ignored',
            Generated_At__c = System.now().addHours(-1)
        );

        insert new CM_Meeting_Transcript__c(
            Focus_Company__c = focusCompany.Id,
            Counterparty_Account__c = supplier.Id,
            Status__c = 'Completed',
            Transcript__c = 'Latest completed transcript',
            Generated_At__c = System.now()
        );

        Map<Id, String> transcriptByAccount =
            CMQBRTranscriptResolver.resolveByAccount(new Set<Id>{ supplier.Id });

        System.assertEquals('Latest completed transcript', transcriptByAccount.get(supplier.Id));
        System.assertEquals('Latest completed transcript', CMQBRTranscriptResolver.resolveForAccount(supplier.Id));
    }

    @IsTest
    static void resolveForFlowReturnsFoundMissingAndFailedStates() {
        Account focusCompany = new Account(
            Name = 'Focus Company 2',
            CM_Is_Demo_Target__c = true
        );
        Account supplierFound = new Account(Name = 'Supplier Found');
        Account supplierMissing = new Account(Name = 'Supplier Missing');
        insert new List<Account>{ focusCompany, supplierFound, supplierMissing };

        insert new CM_Meeting_Transcript__c(
            Focus_Company__c = focusCompany.Id,
            Counterparty_Account__c = supplierFound.Id,
            Status__c = 'Completed',
            Transcript__c = 'Transcript for found supplier',
            Generated_At__c = System.now()
        );

        CMQBRTranscriptResolver.Request reqFound = new CMQBRTranscriptResolver.Request();
        reqFound.accountId = supplierFound.Id;

        CMQBRTranscriptResolver.Request reqMissing = new CMQBRTranscriptResolver.Request();
        reqMissing.accountId = supplierMissing.Id;

        CMQBRTranscriptResolver.Request reqInvalid = new CMQBRTranscriptResolver.Request();

        List<CMQBRTranscriptResolver.Response> responses =
            CMQBRTranscriptResolver.resolveForFlow(
                new List<CMQBRTranscriptResolver.Request>{ reqFound, reqMissing, reqInvalid }
            );

        System.assertEquals(3, responses.size());

        System.assertEquals('Found', responses[0].status);
        System.assertEquals('Transcript for found supplier', responses[0].transcript);

        System.assertEquals('Missing', responses[1].status);
        System.assertEquals(null, responses[1].transcript);

        System.assertEquals('Failed', responses[2].status);
        System.assertEquals('Account Id is required.', responses[2].message);
    }
}
