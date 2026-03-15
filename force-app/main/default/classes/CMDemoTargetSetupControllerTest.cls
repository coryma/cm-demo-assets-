@IsTest
private class CMDemoTargetSetupControllerTest {
    @IsTest
    static void searchAndSetActiveTarget() {
        Account firstAccount = new Account(
            Name = 'WNC Demo',
            Industry = 'Electronics',
            Website = 'https://wnc.example.com',
            Description = 'Wireless communication and networking products.',
            CM_Is_Demo_Target__c = true
        );
        Account secondAccount = new Account(
            Name = 'WT Technology Demo',
            Industry = 'Semiconductors',
            Description = 'Fabless design house for storage and compute.'
        );
        insert new List<Account>{ firstAccount, secondAccount };

        Test.startTest();
        List<CMDemoTargetSetupController.DemoTargetAccount> results =
            CMDemoTargetSetupController.searchAccounts('WT Technology');
        CMDemoTargetSetupController.DemoTargetAccount activeBefore =
            CMDemoTargetSetupController.getActiveDemoTarget();
        CMDemoTargetSetupController.DemoTargetAccount activeAfter =
            CMDemoTargetSetupController.setActiveDemoTarget(secondAccount.Id);
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(secondAccount.Id, results[0].id);
        System.assertEquals(firstAccount.Id, activeBefore.id);
        System.assertEquals(secondAccount.Id, activeAfter.id);
        System.assertEquals(false, activeAfter.hasContext);
        System.assertEquals('Website', activeAfter.missingContext);

        Map<Id, Account> refreshed = new Map<Id, Account>([
            SELECT Id, CM_Is_Demo_Target__c
            FROM Account
            WHERE Id IN :new Set<Id>{ firstAccount.Id, secondAccount.Id }
        ]);
        System.assertEquals(false, refreshed.get(firstAccount.Id).CM_Is_Demo_Target__c);
        System.assertEquals(true, refreshed.get(secondAccount.Id).CM_Is_Demo_Target__c);
    }
}
