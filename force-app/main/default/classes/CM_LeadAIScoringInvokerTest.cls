@IsTest
private class CM_LeadAIScoringInvokerTest {
    @IsTest
    static void returnsExistingValuesWhenNoDemoTarget() {
        Lead leadRecord = new Lead(
            LastName = 'Existing',
            Company = 'Example Corp',
            AI_Classification__c = 'Review',
            AI_KeyTopics__c = 'Storage, RFQ',
            AI_Reason__c = 'Existing reason',
            AI_ReplyRecommendation__c = 'Existing recommendation',
            AI_Score__c = 44
        );
        insert leadRecord;

        CM_LeadAIScoringInvoker.Requests request = new CM_LeadAIScoringInvoker.Requests();
        request.leadId = leadRecord.Id;

        Test.startTest();
        List<CM_LeadAIScoringInvoker.Results> results =
            CM_LeadAIScoringInvoker.generate(new List<CM_LeadAIScoringInvoker.Requests>{ request });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Review', results[0].classification);
        System.assertEquals(44, results[0].score);
        System.assertEquals('Existing reason', results[0].reason);
    }

    @IsTest
    static void usesPromptResponseWhenDemoTargetExists() {
        Account demoTarget = new Account(
            Name = 'Tufier Demo',
            Industry = 'Semiconductors',
            Description = 'Automotive and communications ICs.',
            CM_Is_Demo_Target__c = true
        );
        insert demoTarget;

        Lead leadRecord = new Lead(
            LastName = 'Prospect',
            Company = 'Micron',
            Description = 'Looking for an automotive AI processor quote.'
        );
        insert leadRecord;

        CM_LeadAIScoringInvoker.testPromptResponse =
            '{"classification":"Open","score":88,"reason":"High intent for a relevant product.","key_topics":["Automotive AI","Quote"],"reply_recommendation":"Assign to sales now."}';

        CM_LeadAIScoringInvoker.Requests request = new CM_LeadAIScoringInvoker.Requests();
        request.leadId = leadRecord.Id;

        Test.startTest();
        List<CM_LeadAIScoringInvoker.Results> results =
            CM_LeadAIScoringInvoker.generate(new List<CM_LeadAIScoringInvoker.Requests>{ request });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Open', results[0].classification);
        System.assertEquals(88, results[0].score);
        System.assertEquals('Automotive AI, Quote', results[0].key_topics);
        System.assertEquals('Assign to sales now.', results[0].reply_recommendation);
    }
}