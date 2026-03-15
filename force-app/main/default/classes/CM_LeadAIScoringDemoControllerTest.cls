@IsTest
private class CM_LeadAIScoringDemoControllerTest {
    @IsTest
    static void generateDescriptionsAndScoresFiveLeads() {
        Account demoTarget = new Account(
            Name = 'WNC Demo',
            Industry = 'Electronics',
            Website = 'https://www.wnc.com',
            Description = 'Networking and wireless system design manufacturer.',
            CM_Is_Demo_Target__c = true
        );
        insert demoTarget;

        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < 5; i++) {
            leads.add(new Lead(
                LastName = 'Lead ' + i,
                Company = 'Company ' + i,
                Email = 'lead' + i + '@example.com'
            ));
        }
        insert leads;

        CM_LeadAIScoringDemoController.testDescriptionByTier = new Map<String, String>{
            'Very High' => 'Very High description',
            'High' => 'High description',
            'Medium' => 'Medium description',
            'Low' => 'Low description',
            'Very Low' => 'Very Low description'
        };
        CM_LeadAIScoringInvoker.testPromptResponse =
            '{"classification":"Open","score":86,"reason":"Strong intent.","key_topics":["RFQ","Timeline"],"reply_recommendation":"Follow up now."}';

        List<Id> orderedIds = new List<Id>{
            leads[0].Id, leads[1].Id, leads[2].Id, leads[3].Id, leads[4].Id
        };

        Test.startTest();
        List<CM_LeadAIScoringDemoController.LeadGenerationResult> results =
            CM_LeadAIScoringDemoController.generateDescriptionsAndScore(orderedIds);
        Test.stopTest();

        System.assertEquals(5, results.size(), 'Should return exactly 5 rows.');
        System.assertEquals('Very High', results[0].qualityTier);
        System.assertEquals('Very Low', results[4].qualityTier);
        System.assertEquals('Very High description', results[0].generatedDescription);
        System.assertEquals('Very Low description', results[4].generatedDescription);
        System.assertEquals(86, Integer.valueOf(String.valueOf(results[0].aiScore)));
        System.assertEquals('Open', results[0].aiClassification);

        Map<Id, Lead> updatedById = new Map<Id, Lead>([
            SELECT Id, Description, AI_Score__c, AI_Classification__c
            FROM Lead
            WHERE Id IN :orderedIds
        ]);

        System.assertEquals('Very High description', updatedById.get(leads[0].Id).Description);
        System.assertEquals(86, Integer.valueOf(String.valueOf(updatedById.get(leads[0].Id).AI_Score__c)));
        System.assertEquals('Open', updatedById.get(leads[0].Id).AI_Classification__c);
    }

    @IsTest
    static void throwsWhenSelectedCountIsNotFive() {
        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < 4; i++) {
            leads.add(new Lead(
                LastName = 'Few ' + i,
                Company = 'Small Co ' + i
            ));
        }
        insert leads;

        Boolean failed = false;
        try {
            CM_LeadAIScoringDemoController.generateDescriptionsAndScore(
                new List<Id>{ leads[0].Id, leads[1].Id, leads[2].Id, leads[3].Id }
            );
        } catch (AuraHandledException ex) {
            failed = true;
        }
        System.assertEquals(true, failed, 'Method should fail when not selecting exactly 5 leads.');
    }

    @IsTest
    static void throwsWhenDemoTargetMissing() {
        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < 5; i++) {
            leads.add(new Lead(
                LastName = 'NoTarget ' + i,
                Company = 'NoTarget Co ' + i
            ));
        }
        insert leads;

        CM_LeadAIScoringDemoController.testDescriptionByTier = new Map<String, String>{
            'Very High' => 'VH',
            'High' => 'H',
            'Medium' => 'M',
            'Low' => 'L',
            'Very Low' => 'VL'
        };

        Boolean failed = false;
        try {
            CM_LeadAIScoringDemoController.generateDescriptionsAndScore(
                new List<Id>{ leads[0].Id, leads[1].Id, leads[2].Id, leads[3].Id, leads[4].Id }
            );
        } catch (AuraHandledException ex) {
            failed = true;
        }
        System.assertEquals(true, failed, 'Method should fail when demo target is not configured.');
    }

    @IsTest
    static void searchReturnsLeadRows() {
        insert new Lead(
            LastName = 'Search Case',
            Company = 'Alpha Search Company',
            Email = 'search@example.com'
        );

        Test.startTest();
        List<CM_LeadAIScoringDemoController.LeadOption> rows =
            CM_LeadAIScoringDemoController.searchLeads('Alpha Search');
        Test.stopTest();

        System.assert(!rows.isEmpty(), 'Search should return at least one row.');
        System.assertEquals('Alpha Search Company', rows[0].company);
    }
}
