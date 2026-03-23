@IsTest
private class CM_EmailToOpptyCreatorTest {

    private static Id activateStandardPricebook() {
        Id pbId = Test.getStandardPricebookId();
        update new Pricebook2(
            Id = pbId,
            IsActive = true
        );
        return pbId;
    }

    private static Account createAccount() {
        Account acc = new Account(
            Name = 'Omega Auto Opp Test',
            Website = 'https://omega.com'
        );
        insert acc;
        return acc;
    }

    private static EmailMessage createEmail(Id relatedToId, String fromAddress) {
        EmailMessage em = new EmailMessage(
            RelatedToId = relatedToId,
            Subject = 'MH241T quotation request',
            TextBody = 'Need quotation for MH241T',
            FromAddress = fromAddress,
            FromName = 'Procurement Manager',
            ToAddress = 'sales@cm-demo.test',
            MessageDate = System.now(),
            Incoming = true,
            Status = '3',
            IsTracked = true
        );
        insert em;
        return em;
    }

    private static String buildLineItemJson(Integer itemCount, String partNumber, Decimal qty, Decimal unitPrice) {
        List<Object> lineItems = new List<Object>();
        for (Integer i = 1; i <= itemCount; i++) {
            lineItems.add(new Map<String, Object>{
                'manufacturer' => 'Omega',
                'part_number' => partNumber + '-' + String.valueOf(i),
                'opportunity_name' => 'Auto Opp ' + String.valueOf(i),
                'quantity' => qty,
                'target_price' => new Map<String, Object>{
                    'value' => unitPrice,
                    'currency' => 'USD'
                },
                'close_date' => String.valueOf(Date.today().addDays(10))
            });
        }
        Map<String, Object> payload = new Map<String, Object>{
            'customer_info' => new Map<String, Object>{
                'name' => 'Buyer',
                'company_context' => 'Omega'
            },
            'general_requirements' => new Map<String, Object>{
                'special_terms' => 'N/A'
            },
            'line_items' => lineItems
        };
        return JSON.serialize(payload);
    }

    @IsTest
    static void createsOpportunityAndLineItemWhenProductMatches() {
        Id stdPbId = activateStandardPricebook();
        Account acc = createAccount();

        Product2 prod = new Product2(
            Name = 'MH241T-1 Industrial Printer',
            IsActive = true
        );
        insert prod;

        insert new PricebookEntry(
            Pricebook2Id = stdPbId,
            Product2Id = prod.Id,
            UnitPrice = 10,
            IsActive = true
        );

        EmailMessage em = createEmail(acc.Id, 'buyer@omega.com');

        CM_EmailToOpptyCreator.Request req = new CM_EmailToOpptyCreator.Request();
        req.emailMessageId = em.Id;
        req.rawJson = buildLineItemJson(1, 'MH241T', 15, 20);

        Test.startTest();
        List<CM_EmailToOpptyCreator.Result> results =
            CM_EmailToOpptyCreator.run(new List<CM_EmailToOpptyCreator.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result.');
        System.assertEquals(1, results[0].createdCount, 'Should create one opportunity.');
        System.assertEquals(0, results[0].failedCount, 'Should have no failed item.');
        System.assert(results[0].message.contains('Created:'), 'Should include created message.');

        List<Opportunity> opps = [
            SELECT Id, AccountId, Amount, Pricebook2Id, SourceEmailId__c, StageName, IsClosed
            FROM Opportunity
            WHERE SourceEmailId__c = :String.valueOf(em.Id)
        ];
        System.assertEquals(1, opps.size(), 'Should create one opportunity record.');
        System.assertEquals(acc.Id, opps[0].AccountId, 'Should map account from email domain.');
        System.assertEquals(300, opps[0].Amount, 'Amount should be qty * unit price.');
        System.assertEquals(stdPbId, opps[0].Pricebook2Id, 'Should use standard pricebook.');
        System.assertEquals(false, opps[0].IsClosed, 'Default stage should not be a closed stage.');

        List<OpportunityLineItem> olis = [
            SELECT Id
            FROM OpportunityLineItem
            WHERE OpportunityId = :opps[0].Id
        ];
        System.assertEquals(1, olis.size(), 'Should create one line item when product matches.');
    }

    @IsTest
    static void createsOnlyFirstFiveItemsToMatchUiLimit() {
        activateStandardPricebook();
        Account acc = createAccount();
        EmailMessage em = createEmail(acc.Id, 'buyer@omega.com');

        CM_EmailToOpptyCreator.Request req = new CM_EmailToOpptyCreator.Request();
        req.emailMessageId = em.Id;
        req.rawJson = buildLineItemJson(6, 'PART', 1, 1);

        Test.startTest();
        List<CM_EmailToOpptyCreator.Result> results =
            CM_EmailToOpptyCreator.run(new List<CM_EmailToOpptyCreator.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result.');
        System.assertEquals(5, results[0].createdCount, 'Should only create first five items.');
        System.assert(results[0].message.contains('Only first 5 items'), 'Should include cap warning.');

        Integer oppCount = [
            SELECT COUNT()
            FROM Opportunity
            WHERE SourceEmailId__c = :String.valueOf(em.Id)
        ];
        System.assertEquals(5, oppCount, 'Only five opportunities should be inserted.');
    }

    @IsTest
    static void throwsWhenLineItemsMissing() {
        CM_EmailToOpptyCreator.Request req = new CM_EmailToOpptyCreator.Request();
        req.rawJson = '{"customer_info":{}}';

        Boolean threw = false;
        try {
            CM_EmailToOpptyCreator.run(new List<CM_EmailToOpptyCreator.Request>{ req });
        } catch (Exception ex) {
            threw = true;
            System.assert(
                ex.getMessage().contains('line_items'),
                'Exception should mention missing line_items.'
            );
        }
        System.assertEquals(true, threw, 'Expected exception for payload without line_items.');
    }
}
