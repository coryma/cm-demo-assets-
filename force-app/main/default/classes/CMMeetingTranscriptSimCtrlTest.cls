@IsTest
private class CMMeetingTranscriptSimCtrlTest {
    @IsTest
    static void getFocusContextAndSearchAccountsExcludeFocus() {
        Account focusAccount = new Account(
            Name = 'WNC Focus Company',
            Industry = 'Electronics',
            CM_Is_Demo_Target__c = true
        );
        Account firstCounterparty = new Account(Name = 'Acme Circuits', Industry = 'Technology');
        Account secondCounterparty = new Account(Name = 'Blue Supply', Industry = 'Manufacturing');
        insert new List<Account>{ focusAccount, firstCounterparty, secondCounterparty };

        Test.startTest();
        CMMeetingTranscriptSimulationController.FocusContextPayload context =
            CMMeetingTranscriptSimulationController.getFocusContext();
        List<CMMeetingTranscriptSimulationController.AccountRow> rows =
            CMMeetingTranscriptSimulationController.searchAccounts('', 999);
        Test.stopTest();

        System.assertEquals(true, context.hasFocusCompany);
        System.assertEquals(focusAccount.Id, context.focusCompanyId);
        System.assertEquals('WNC Focus Company', context.focusCompanyName);
        System.assertEquals(2, rows.size());

        Set<Id> searchedIds = new Set<Id>();
        for (CMMeetingTranscriptSimulationController.AccountRow row : rows) {
            searchedIds.add(row.id);
        }
        System.assertEquals(false, searchedIds.contains(focusAccount.Id));
        System.assertEquals(true, searchedIds.contains(firstCounterparty.Id));
        System.assertEquals(true, searchedIds.contains(secondCounterparty.Id));
        for (CMMeetingTranscriptSimulationController.AccountRow row : rows) {
            System.assertEquals(false, row.hasMeetingRecord);
        }

        insert new CM_Meeting_Transcript__c(
            Focus_Company__c = focusAccount.Id,
            Counterparty_Account__c = firstCounterparty.Id,
            Duration_Minutes__c = 45,
            Batch_Id__c = 'TEST-BATCH-1',
            Status__c = 'Completed',
            Summary__c = 'Existing transcript',
            Transcript__c = 'Existing transcript body',
            Generated_At__c = System.now()
        );

        List<CMMeetingTranscriptSimulationController.AccountRow> refreshedRows =
            CMMeetingTranscriptSimulationController.searchAccounts('Acme', 10);
        System.assertEquals(1, refreshedRows.size());
        System.assertEquals(true, refreshedRows[0].hasMeetingRecord);
    }

    @IsTest
    static void startSimulationCreatesTranscriptRecordsAndBatchStatus() {
        Account focusAccount = new Account(
            Name = 'WNC Focus Company',
            Industry = 'Electronics',
            CM_Is_Demo_Target__c = true
        );
        Account firstCounterparty = new Account(Name = 'Alpha Components', Industry = 'Semiconductor');
        Account secondCounterparty = new Account(Name = 'Zen Assembly', Industry = 'Industrial');
        insert new List<Account>{ focusAccount, firstCounterparty, secondCounterparty };

        Test.startTest();
        CMMeetingTranscriptSimulationController.StartSimulationResult startResult =
            CMMeetingTranscriptSimulationController.startSimulation(
                new List<Id>{ focusAccount.Id, firstCounterparty.Id, secondCounterparty.Id }
            );
        CMMeetingTranscriptSimulationController.BatchStatusPayload queuedStatus =
            CMMeetingTranscriptSimulationController.getBatchStatus(startResult.batchId);
        System.assertEquals(2, queuedStatus.totalCount);
        System.assertEquals(2, queuedStatus.queuedCount);
        System.assertEquals(0, queuedStatus.completedCount);
        System.assertEquals(false, queuedStatus.done);
        Test.stopTest();

        CMMeetingTranscriptSimulationController.BatchStatusPayload batchStatus =
            CMMeetingTranscriptSimulationController.getBatchStatus(startResult.batchId);

        System.assertNotEquals(null, startResult.batchId);
        System.assertEquals(2, startResult.createdCount);
        System.assert(startResult.message.contains('Queued'));

        List<CM_Meeting_Transcript__c> created = [
            SELECT
                Focus_Company__c,
                Counterparty_Account__c,
                Duration_Minutes__c,
                Batch_Id__c,
                Status__c,
                Summary__c,
                Transcript__c,
                Action_Items__c,
                Prompt_Response__c,
                Error_Message__c,
                Generated_At__c
            FROM CM_Meeting_Transcript__c
            WHERE Batch_Id__c = :startResult.batchId
        ];

        System.assertEquals(2, created.size());
        for (CM_Meeting_Transcript__c row : created) {
            System.assertEquals(focusAccount.Id, row.Focus_Company__c);
            System.assertEquals(45, row.Duration_Minutes__c);
            System.assertEquals('Completed', row.Status__c);
            System.assertNotEquals(null, row.Summary__c);
            System.assertNotEquals(null, row.Transcript__c);
            System.assertNotEquals(null, row.Action_Items__c);
            System.assertNotEquals(null, row.Prompt_Response__c);
            System.assertEquals(null, row.Error_Message__c);
            System.assertNotEquals(null, row.Generated_At__c);
            System.assert(row.Prompt_Response__c.contains('"transcript"'));
        }

        System.assertEquals(startResult.batchId, batchStatus.batchId);
        System.assertEquals(2, batchStatus.totalCount);
        System.assertEquals(0, batchStatus.queuedCount);
        System.assertEquals(0, batchStatus.processingCount);
        System.assertEquals(2, batchStatus.completedCount);
        System.assertEquals(0, batchStatus.failedCount);
        System.assertEquals(true, batchStatus.done);
        System.assertEquals(2, batchStatus.rows.size());
        System.assert(batchStatus.rows[0].recordUrl.contains('/lightning/r/CM_Meeting_Transcript__c/'));
    }

    @IsTest
    static void startSimulationValidatesSelectionAndFocusCompany() {
        Account accountOnly = new Account(Name = 'Only Account');
        insert accountOnly;

        Boolean missingFocusThrown = false;
        try {
            CMMeetingTranscriptSimulationController.startSimulation(new List<Id>{ accountOnly.Id });
        } catch (AuraHandledException ex) {
            missingFocusThrown = true;
            System.assert(!String.isBlank(ex.getMessage()));
        }
        System.assertEquals(true, missingFocusThrown, 'Expected missing focus company exception.');

        accountOnly.CM_Is_Demo_Target__c = true;
        update accountOnly;

        Boolean focusOnlyThrown = false;
        try {
            CMMeetingTranscriptSimulationController.startSimulation(new List<Id>{ accountOnly.Id });
        } catch (AuraHandledException ex) {
            focusOnlyThrown = true;
            System.assert(!String.isBlank(ex.getMessage()));
        }
        System.assertEquals(true, focusOnlyThrown, 'Expected focus-only selection exception.');

        Boolean emptySelectionThrown = false;
        try {
            CMMeetingTranscriptSimulationController.startSimulation(new List<Id>());
        } catch (AuraHandledException ex) {
            emptySelectionThrown = true;
            System.assert(!String.isBlank(ex.getMessage()));
        }
        System.assertEquals(true, emptySelectionThrown, 'Expected empty selection exception.');
    }

    @IsTest
    static void getFocusContextWithoutConfiguredTargetAndGetBatchStatusValidation() {
        insert new Account(Name = 'No Focus Account');

        Test.startTest();
        CMMeetingTranscriptSimulationController.FocusContextPayload context =
            CMMeetingTranscriptSimulationController.getFocusContext();
        Test.stopTest();

        System.assertEquals(false, context.hasFocusCompany);
        System.assertEquals(null, context.focusCompanyId);
        System.assertEquals(null, context.focusCompanyName);

        Boolean missingBatchIdThrown = false;
        try {
            CMMeetingTranscriptSimulationController.getBatchStatus('');
        } catch (AuraHandledException ex) {
            missingBatchIdThrown = true;
            System.assert(!String.isBlank(ex.getMessage()));
        }
        System.assertEquals(true, missingBatchIdThrown, 'Expected missing batch id exception.');
    }
}