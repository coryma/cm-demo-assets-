@IsTest
private class CMNewsSetupControllerTest {
    @TestSetup
    static void setupData() {
        insert new List<Account>{
            new Account(Name = 'Alpha Manufacturing'),
            new Account(Name = 'Beta Components')
        };
    }

    @IsTest
    static void searchAccountsReturnsRows() {
        Test.startTest();
        List<CMNewsSetupController.AccountOption> rows = CMNewsSetupController.searchAccounts('Alpha');
        Test.stopTest();

        System.assertEquals(1, rows.size());
        System.assertEquals('Alpha Manufacturing', rows[0].name);
    }

    @IsTest
    static void generateNewsUpdatesAccountNews() {
        Account target = [SELECT Id, Name FROM Account WHERE Name = 'Alpha Manufacturing' LIMIT 1];
        CMNewsSetupController.testNewsPayload =
            'Company Profile and Latest News for: Alpha Manufacturing\n\nLatest News:\n'
            + 'Title: Sample title\nURL: https://example.com/1\nDate: 20260315T120000Z\n';

        Test.startTest();
        CMNewsSetupController.NewsGenerationResult result =
            CMNewsSetupController.generateNews(
                new List<Id>{ target.Id },
                'GDELT',
                null,
                'ANY'
            );
        Test.stopTest();

        System.assertEquals(1, result.successCount);
        Account refreshed = [SELECT Account_News__c, CM_LatestUpdate__c FROM Account WHERE Id = :target.Id];
        System.assert(refreshed.Account_News__c.contains('Sample title'));
        System.assert(refreshed.CM_LatestUpdate__c.contains('Provider: GDELT'));
    }

    @IsTest
    static void saveQueryConfigsReturnsSavedRows() {
        Account target = [SELECT Id FROM Account WHERE Name = 'Alpha Manufacturing' LIMIT 1];
        CMNewsSetupController.QueryConfigInput config = new CMNewsSetupController.QueryConfigInput();
        config.accountId = target.Id;
        config.accountNewsQuery = 'Alpha keyword';
        config.relatedNewsQuery = 'Supply chain';

        Test.startTest();
        List<CMNewsSetupController.QueryConfigSavedItem> saved =
            CMNewsSetupController.saveQueryConfigs(new List<CMNewsSetupController.QueryConfigInput>{ config });
        Test.stopTest();

        System.assertEquals(1, saved.size());
        System.assertEquals(target.Id, saved[0].accountId);
        System.assertEquals('Alpha keyword', saved[0].accountNewsQuery);
        System.assertEquals('Supply chain', saved[0].relatedNewsQuery);
        System.assertEquals(false, saved[0].hasNews);
        System.assertEquals(false, saved[0].hasRelatedNews);
        System.assertEquals(null, saved[0].latestUpdate);
        System.assertNotEquals(null, saved[0].lastModifiedDate);
    }

    @IsTest
    static void generateNewsWithStoredQueriesUpdatesBothNewsBlocks() {
        Account target = [SELECT Id, Name FROM Account WHERE Name = 'Beta Components' LIMIT 1];
        CMNewsSetupController.testNewsPayload =
            'Company Profile and Latest News for: SAP\n\nLatest News:\n'
            + 'Title: Related title\nURL: https://example.com/related\nDate: 20260315T120000Z\n';

        Test.startTest();
        CMNewsSetupController.QueryConfigInput config = new CMNewsSetupController.QueryConfigInput();
        config.accountId = target.Id;
        config.accountNewsQuery = 'Beta custom keyword';
        config.relatedNewsQuery = 'SAP';
        CMNewsSetupController.saveQueryConfigs(new List<CMNewsSetupController.QueryConfigInput>{ config });

        CMNewsSetupController.NewsGenerationResult result =
            CMNewsSetupController.generateNews(
                new List<Id>{ target.Id },
                'GDELT',
                null,
                'ANY'
            );
        Test.stopTest();

        System.assertEquals(1, result.successCount);
        System.assertEquals(1, result.accountNewsSuccessCount);
        System.assertEquals(1, result.relatedNewsSuccessCount);
        Account refreshed = [
            SELECT Account_News_Query__c, Account_News__c, Related_News_Query__c, Related_News__c, CM_LatestUpdate__c
            FROM Account
            WHERE Id = :target.Id
        ];
        System.assertEquals('Beta custom keyword', refreshed.Account_News_Query__c);
        System.assert(refreshed.Account_News__c.contains('Related title'));
        System.assertEquals('SAP', refreshed.Related_News_Query__c);
        System.assert(refreshed.Related_News__c.contains('Related title'));
        System.assert(refreshed.CM_LatestUpdate__c.contains('Account Query: Beta custom keyword'));
        System.assert(refreshed.CM_LatestUpdate__c.contains('Related Query: SAP'));
    }

    @IsTest
    static void testGdeltQueryParsesEntries() {
        CMNewsSetupController.testNewsPayload =
            'Company Profile and Latest News for: Tesla\n\nLatest News:\n'
            + 'Title: First\nURL: https://example.com/a\nDate: 20260315T120000Z\n\n'
            + 'Title: Second\nURL: https://example.com/b\nDate: 20260315T130000Z\n';

        Test.startTest();
        CMNewsSetupController.QueryTestResult result =
            CMNewsSetupController.testNewsQuery('Tesla', 'ENGLISH', 'GDELT', null);
        Test.stopTest();

        System.assertEquals(2, result.entryCount);
        System.assertEquals('First', result.entries[0].title);
        System.assertEquals('https://example.com/a', result.entries[0].url);
    }
}