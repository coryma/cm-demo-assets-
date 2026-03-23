@IsTest
private class CMQBRAsyncEmailDraftServiceTest {
    @IsTest
    static void usesTranscriptFromActiveDemoSetupWhenMeetingNotesMissing() {
        Account focusCompany = new Account(
            Name = 'WNC Focus',
            CM_Is_Demo_Target__c = true
        );
        Account supplier = new Account(Name = 'Supplier A');
        insert new List<Account>{ focusCompany, supplier };

        insert new CM_Meeting_Transcript__c(
            Focus_Company__c = focusCompany.Id,
            Counterparty_Account__c = supplier.Id,
            Status__c = 'Completed',
            Transcript__c = 'Transcript from setup for Supplier A',
            Generated_At__c = System.now()
        );

        CMQBRAsyncEmailDraftService.StartRequest req = new CMQBRAsyncEmailDraftService.StartRequest();
        req.accountId = supplier.Id;
        req.meetingNotes = null;

        List<CMQBRAsyncEmailDraftService.StartResponse> responses;
        Test.startTest();
        responses = CMQBRAsyncEmailDraftService.startGeneration(
            new List<CMQBRAsyncEmailDraftService.StartRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals('Queued', responses[0].status);
        System.assertNotEquals(null, responses[0].bufferId);

        CM_QBR_Email_Draft_Buffer__c buffer = [
            SELECT Status__c, MeetingNotes__c, DraftSubject__c, DraftBody__c
            FROM CM_QBR_Email_Draft_Buffer__c
            WHERE Id = :responses[0].bufferId
            LIMIT 1
        ];

        System.assertEquals('Completed', buffer.Status__c);
        System.assertEquals('Transcript from setup for Supplier A', buffer.MeetingNotes__c);
        System.assertNotEquals(null, buffer.DraftSubject__c);
        System.assertNotEquals(null, buffer.DraftBody__c);
    }

    @IsTest
    static void fallsBackToRequestMeetingNotesWhenTranscriptMissing() {
        Account supplier = new Account(Name = 'Supplier B');
        insert supplier;

        CMQBRAsyncEmailDraftService.StartRequest req = new CMQBRAsyncEmailDraftService.StartRequest();
        req.accountId = supplier.Id;
        req.meetingNotes = 'Manual meeting notes fallback';

        List<CMQBRAsyncEmailDraftService.StartResponse> responses;
        Test.startTest();
        responses = CMQBRAsyncEmailDraftService.startGeneration(
            new List<CMQBRAsyncEmailDraftService.StartRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals('Queued', responses[0].status);

        CM_QBR_Email_Draft_Buffer__c buffer = [
            SELECT Status__c, MeetingNotes__c
            FROM CM_QBR_Email_Draft_Buffer__c
            WHERE Id = :responses[0].bufferId
            LIMIT 1
        ];

        System.assertEquals('Completed', buffer.Status__c);
        System.assertEquals('Manual meeting notes fallback', buffer.MeetingNotes__c);
    }

    @IsTest
    static void marksRequestFailedWhenNoTranscriptAndNoMeetingNotes() {
        Account supplier = new Account(Name = 'Supplier C');
        insert supplier;

        CMQBRAsyncEmailDraftService.StartRequest req = new CMQBRAsyncEmailDraftService.StartRequest();
        req.accountId = supplier.Id;
        req.meetingNotes = null;

        List<CMQBRAsyncEmailDraftService.StartResponse> responses =
            CMQBRAsyncEmailDraftService.startGeneration(
                new List<CMQBRAsyncEmailDraftService.StartRequest>{ req }
            );

        System.assertEquals(1, responses.size());
        System.assertEquals('Failed', responses[0].status);
        System.assertNotEquals(null, responses[0].bufferId);

        CM_QBR_Email_Draft_Buffer__c buffer = [
            SELECT Status__c, ErrorMessage__c
            FROM CM_QBR_Email_Draft_Buffer__c
            WHERE Id = :responses[0].bufferId
            LIMIT 1
        ];
        System.assertEquals('Failed', buffer.Status__c);
        System.assert(!String.isBlank(buffer.ErrorMessage__c));
    }
}