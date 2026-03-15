@IsTest
private class CMAccountRoleSetupControllerTest {
    @IsTest
    static void searchAccountsReturnsRoleValues() {
        Account customerSupplier = new Account(
            Name = 'Role Search Alpha',
            Industry = 'Technology',
            CM_Account_Roles__c = 'Customer;Supplier'
        );
        Account partnerOnly = new Account(
            Name = 'Role Search Beta',
            Industry = 'Electronics',
            CM_Account_Roles__c = 'Partner'
        );
        insert new List<Account>{ customerSupplier, partnerOnly };

        Test.startTest();
        List<CMAccountRoleSetupController.AccountRoleOption> rows =
            CMAccountRoleSetupController.searchAccounts('Role Search');
        Test.stopTest();

        System.assertEquals(2, rows.size());
        System.assertEquals('Role Search Alpha', rows[0].name);
        System.assertEquals(
            new List<String>{ 'Customer', 'Supplier' },
            rows[0].roleValues
        );
        System.assertEquals('Customer, Supplier', rows[0].roleSummary);
    }

    @IsTest
    static void saveAccountRolesUpdatesMultipleAccounts() {
        Account firstAccount = new Account(Name = 'Role Batch One');
        Account secondAccount = new Account(Name = 'Role Batch Two');
        insert new List<Account>{ firstAccount, secondAccount };

        Test.startTest();
        List<CMAccountRoleSetupController.AccountRoleOption> updated =
            CMAccountRoleSetupController.saveAccountRoles(
                new List<Id>{ firstAccount.Id, secondAccount.Id },
                new List<String>{ 'Supplier', 'Customer' }
            );
        Test.stopTest();

        System.assertEquals(2, updated.size());
        for (CMAccountRoleSetupController.AccountRoleOption row : updated) {
            System.assertEquals(
                new List<String>{ 'Customer', 'Supplier' },
                row.roleValues
            );
        }

        Map<Id, Account> refreshed = new Map<Id, Account>([
            SELECT Id, CM_Account_Roles__c
            FROM Account
            WHERE Id IN :new Set<Id>{ firstAccount.Id, secondAccount.Id }
        ]);
        System.assertEquals('Customer;Supplier', refreshed.get(firstAccount.Id).CM_Account_Roles__c);
        System.assertEquals('Customer;Supplier', refreshed.get(secondAccount.Id).CM_Account_Roles__c);
    }

    @IsTest
    static void saveAccountRolesClearsRolesWhenEmpty() {
        Account accountRecord = new Account(
            Name = 'Role Clear',
            CM_Account_Roles__c = 'Customer;Partner'
        );
        insert accountRecord;

        Test.startTest();
        CMAccountRoleSetupController.saveAccountRoles(
            new List<Id>{ accountRecord.Id },
            new List<String>()
        );
        Test.stopTest();

        Account refreshed = [
            SELECT CM_Account_Roles__c
            FROM Account
            WHERE Id = :accountRecord.Id
        ];
        System.assertEquals(null, refreshed.CM_Account_Roles__c);
    }

    @IsTest
    static void saveAccountRolesThrowsOnInvalidRole() {
        Account accountRecord = new Account(Name = 'Role Invalid');
        insert accountRecord;

        Boolean failed = false;
        try {
            CMAccountRoleSetupController.saveAccountRoles(
                new List<Id>{ accountRecord.Id },
                new List<String>{ 'Vendor' }
            );
        } catch (AuraHandledException ex) {
            failed = true;
            System.assert(ex.getMessage().contains('Unsupported role'));
        }

        System.assertEquals(true, failed, 'Method should fail when role value is invalid.');
    }
}
