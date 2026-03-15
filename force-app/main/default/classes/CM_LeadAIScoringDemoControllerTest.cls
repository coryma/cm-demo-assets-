@IsTest
private class CM_LeadAIScoringDemoControllerTest {
    private static List<CM_LeadAIScoringDemoController.LeadGenerationInput> toInputs(
        List<Lead> leads,
        List<String> qualityTiers
    ) {
        List<CM_LeadAIScoringDemoController.LeadGenerationInput> inputs =
            new List<CM_LeadAIScoringDemoController.LeadGenerationInput>();

        for (Integer i = 0; i < leads.size(); i++) {
            CM_LeadAIScoringDemoController.LeadGenerationInput inputRow =
                new CM_LeadAIScoringDemoController.LeadGenerationInput();
            inputRow.leadId = leads[i].Id;
            inputRow.qualityTier = qualityTiers == null || i >= qualityTiers.size()
                ? null
                : qualityTiers[i];
            inputs.add(inputRow);
        }
        return inputs;
    }

    @IsTest
    static void generateDescriptionsAndScoresWithConfigurableTiers() {
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

        List<String> configuredTiers = new List<String>{
            'Low', 'Very High', 'Medium', 'Very Low', 'High'
        };
        List<Id> orderedIds = new List<Id>();
        for (Lead leadRecord : leads) {
            orderedIds.add(leadRecord.Id);
        }

        Test.startTest();
        List<CM_LeadAIScoringDemoController.LeadGenerationResult> results =
            CM_LeadAIScoringDemoController.generateDescriptionsAndScore(
                toInputs(leads, configuredTiers),
                null
            );
        Test.stopTest();

        System.assertEquals(5, results.size(), 'Should return exactly 5 rows.');
        System.assertEquals('Low', results[0].qualityTier);
        System.assertEquals('Very High', results[1].qualityTier);
        System.assertEquals('High', results[4].qualityTier);
        System.assertEquals('Low description', results[0].generatedDescription);
        System.assertEquals('Very High description', results[1].generatedDescription);
        System.assertEquals(86, Integer.valueOf(String.valueOf(results[0].aiScore)));
        System.assertEquals('Open', results[0].aiClassification);

        Map<Id, Lead> updatedById = new Map<Id, Lead>([
            SELECT Id, Description, AI_Score__c, AI_Classification__c
            FROM Lead
            WHERE Id IN :orderedIds
        ]);

        System.assertEquals('Low description', updatedById.get(leads[0].Id).Description);
        System.assertEquals(86, Integer.valueOf(String.valueOf(updatedById.get(leads[0].Id).AI_Score__c)));
        System.assertEquals('Open', updatedById.get(leads[0].Id).AI_Classification__c);
    }

    @IsTest
    static void throwsWhenSelectedCountExceedsTen() {
        Account demoTarget = new Account(
            Name = 'Limit Demo',
            CM_Is_Demo_Target__c = true
        );
        insert demoTarget;

        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < 11; i++) {
            leads.add(new Lead(
                LastName = 'Few ' + i,
                Company = 'Small Co ' + i
            ));
        }
        insert leads;

        Boolean failed = false;
        try {
            CM_LeadAIScoringDemoController.generateDescriptionsAndScore(
                toInputs(leads, null),
                null
            );
        } catch (AuraHandledException ex) {
            failed = true;
        }
        System.assertEquals(true, failed, 'Method should fail when selecting more than 10 leads.');
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
                toInputs(leads, null),
                null
            );
        } catch (AuraHandledException ex) {
            failed = true;
        }
        System.assertEquals(true, failed, 'Method should fail when demo target is not configured.');
    }

    @IsTest
    static void throwsWhenQualityTierInvalid() {
        Account demoTarget = new Account(
            Name = 'Quality Demo',
            CM_Is_Demo_Target__c = true
        );
        insert demoTarget;

        Lead leadRecord = new Lead(
            LastName = 'Invalid Tier',
            Company = 'Invalid Co'
        );
        insert leadRecord;

        CM_LeadAIScoringDemoController.LeadGenerationInput inputRow =
            new CM_LeadAIScoringDemoController.LeadGenerationInput();
        inputRow.leadId = leadRecord.Id;
        inputRow.qualityTier = 'Ultra High';

        Boolean failed = false;
        try {
            CM_LeadAIScoringDemoController.generateDescriptionsAndScore(
                new List<CM_LeadAIScoringDemoController.LeadGenerationInput>{ inputRow },
                null
            );
        } catch (AuraHandledException ex) {
            failed = true;
        }
        System.assertEquals(true, failed, 'Method should fail when tier is outside allowed values.');
    }

    @IsTest
    static void supportsLegacyLeadIdsPayload() {
        Account demoTarget = new Account(
            Name = 'Legacy Payload Demo',
            CM_Is_Demo_Target__c = true
        );
        insert demoTarget;

        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < 2; i++) {
            leads.add(new Lead(
                LastName = 'Legacy ' + i,
                Company = 'Legacy Co ' + i
            ));
        }
        insert leads;

        CM_LeadAIScoringDemoController.testDescriptionByTier = new Map<String, String>{
            'Very High' => 'Legacy VH',
            'High' => 'Legacy H',
            'Medium' => 'Legacy M',
            'Low' => 'Legacy L',
            'Very Low' => 'Legacy VL'
        };
        CM_LeadAIScoringInvoker.testPromptResponse =
            '{"classification":"Review","score":55,"reason":"Legacy payload ok.","key_topics":["Legacy"],"reply_recommendation":"Follow up."}';

        Test.startTest();
        List<CM_LeadAIScoringDemoController.LeadGenerationResult> results =
            CM_LeadAIScoringDemoController.generateDescriptionsAndScore(
                null,
                new List<Id>{ leads[0].Id, leads[1].Id }
            );
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assertEquals('Very High', results[0].qualityTier);
        System.assertEquals('High', results[1].qualityTier);
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
