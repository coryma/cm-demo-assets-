@IsTest
private class CM_EmailToOpptyPromptInvokerTest {

    @IsTest
    static void validatesRequiredEmailMessageId() {
        Boolean threwOnNullList = false;
        try {
            CM_EmailToOpptyPromptInvoker.run(null);
        } catch (Exception ex) {
            threwOnNullList = true;
            System.assert(ex.getMessage().contains('EmailMessage Id is required.'));
        }
        System.assertEquals(true, threwOnNullList, 'Should reject null request list.');

        CM_EmailToOpptyPromptInvoker.Request req = new CM_EmailToOpptyPromptInvoker.Request();
        req.emailMessageId = null;

        Boolean threwOnMissingId = false;
        try {
            CM_EmailToOpptyPromptInvoker.run(new List<CM_EmailToOpptyPromptInvoker.Request>{ req });
        } catch (Exception ex) {
            threwOnMissingId = true;
            System.assert(ex.getMessage().contains('EmailMessage Id is required.'));
        }
        System.assertEquals(true, threwOnMissingId, 'Should reject request without email id.');
    }

    @IsTest
    static void normalizesAndExtractsJson() {
        String nbsp = String.fromCharArray(new List<Integer>{160});
        String bom = String.fromCharArray(new List<Integer>{65279});

        String raw = bom + '{' + nbsp + '"line_items":[] }';
        String normalized = CM_EmailToOpptyPromptInvoker.debugNormalizeJson(raw);

        System.assertEquals(-1, normalized.indexOf(nbsp), 'NBSP should be removed.');
        System.assert(normalized.startsWith('{'), 'BOM should be removed.');

        String wrappedOutput =
            'Result below:' +
            '\n```json\n{"line_items":[{"manufacturer":"ACME"}]}\n```';
        String extracted = CM_EmailToOpptyPromptInvoker.debugExtractJson(wrappedOutput);
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(extracted);

        System.assert(parsed.containsKey('line_items'), 'Should extract JSON object from wrapped text.');
    }

    @IsTest
    static void buildsSummaryFromPromptJson() {
        String jsonText =
            '{"line_items":[{"manufacturer":"ACME","part_number":"X1","quantity":10,' +
            '"target_price":{"value":1.23,"currency":"USD"},' +
            '"delivery_requirement":"May","application_notes":"Industrial"}]}';

        String summary = CM_EmailToOpptyPromptInvoker.debugBuildSummary(jsonText);
        System.assert(summary.contains('ACME X1'), 'Summary should include manufacturer and part.');
        System.assert(summary.contains('Qty: 10'), 'Summary should include quantity.');
        System.assert(summary.contains('Target: USD 1.23'), 'Summary should include target price.');
        System.assert(summary.contains('Delivery: May'), 'Summary should include delivery.');
        System.assert(summary.contains('App: Industrial'), 'Summary should include application notes.');
    }

    @IsTest
    static void rejectsBlankPromptInputBeforeCallout() {
        Boolean threw = false;
        try {
            CM_EmailToOpptyPromptInvoker.debugCallPrompt('   ');
        } catch (Exception ex) {
            threw = true;
            System.assert(ex.getMessage().contains('Email content is empty.'));
        }
        System.assertEquals(true, threw, 'Blank prompt input should throw before any callout.');
    }
}