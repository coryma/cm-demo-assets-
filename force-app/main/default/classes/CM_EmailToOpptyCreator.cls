public with sharing class CM_EmailToOpptyCreator {
    private static final Integer MAX_REVIEWABLE_LINE_ITEMS = 5;

    public class Request {
        @InvocableVariable(required=true label='Prompt JSON')
        public String rawJson;

        @InvocableVariable(label='EmailMessage Id')
        public Id emailMessageId;
    }

    public class Result {
        @InvocableVariable(label='Created Count')
        public Integer createdCount;

        @InvocableVariable(label='Failed Count')
        public Integer failedCount;

        @InvocableVariable(label='Message')
        public String message;
    }

    private class EmailContext {
        Id accountId;
        Id contactId;
        String subject;
        String fromAddress;
        String body;
    }

    @InvocableMethod(label='Create Opportunities from Email JSON')
    public static List<Result> run(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            throw new FlowException('Missing prompt JSON.');
        }

        List<Result> outputs = new List<Result>();
        for (Request req : requests) {
            if (req == null || String.isBlank(req.rawJson)) {
                throw new FlowException('Missing prompt JSON.');
            }
            outputs.add(process(req));
        }
        return outputs;
    }

    private static Result process(Request req) {
        Map<String, Object> parsed;
        try {
            parsed = (Map<String, Object>) JSON.deserializeUntyped(req.rawJson);
        } catch (Exception ex) {
            throw new FlowException('JSON 解析失敗：' + ex.getMessage());
        }

        List<Object> lineItems = new List<Object>();
        if (parsed.get('line_items') instanceof List<Object>) {
            lineItems = (List<Object>) parsed.get('line_items');
        }
        if (lineItems.isEmpty()) {
            throw new FlowException('Prompt JSON 不包含 line_items，無法建立 Opportunity。');
        }

        EmailContext ctx = resolveEmailContext(req.emailMessageId);
        Id pricebookId = getStandardPricebookId();
        String defaultStage = getDefaultStageName();

        Integer successCount = 0;
        Integer failureCount = 0;
        List<String> messages = new List<String>();
        Integer totalLineItems = lineItems.size();
        Integer idx = 0;
        Integer maxItemsToCreate = Math.min(totalLineItems, MAX_REVIEWABLE_LINE_ITEMS);

        for (Integer i = 0; i < maxItemsToCreate; i++) {
            Object item = lineItems[i];
            idx = i + 1;
            if (!(item instanceof Map<String, Object>)) {
                failureCount++;
                messages.add('第 ' + String.valueOf(idx) + ' 筆：line_item 不是有效的物件');
                continue;
            }
            Map<String, Object> line = (Map<String, Object>) item;
            try {
                Decimal qty = safeDecimal(line.get('quantity'));
                if (qty == null || qty <= 0) {
                    qty = 1;
                }
                Decimal targetPrice = extractTargetPrice(line);

                Opportunity opp = new Opportunity();
                String userName = cleanStr(line.get('opportunity_name'));
                opp.Name = String.isNotBlank(userName) ? userName : buildOppName(line, ctx);
                opp.StageName = defaultStage;
                Date perLineCloseDate = parseCloseDate(line.get('close_date'));
                opp.CloseDate = perLineCloseDate != null ? perLineCloseDate : Date.today().addDays(30);
                opp.AccountId = ctx.accountId;
                if (pricebookId != null) {
                    opp.Pricebook2Id = pricebookId;
                }
                if (req.emailMessageId != null) {
                    opp.SourceEmailId__c = String.valueOf(req.emailMessageId);
                }
                opp.Description = buildOpportunityDescription(parsed, line, ctx, req.rawJson);
                if (targetPrice != null && qty != null) {
                    opp.Amount = targetPrice * qty;
                }

                insert opp;

                if (ctx.contactId != null) {
                    OpportunityContactRole ocr = new OpportunityContactRole(
                        OpportunityId = opp.Id,
                        ContactId = ctx.contactId,
                        Role = 'Decision Maker',
                        IsPrimary = true
                    );
                    insert ocr;
                }

                Boolean oliCreated = false;
                if (pricebookId != null) {
                    PricebookEntry pbe = findPricebookEntry(line, pricebookId);
                    if (pbe != null) {
                        OpportunityLineItem oli = new OpportunityLineItem();
                        oli.OpportunityId = opp.Id;
                        oli.PricebookEntryId = pbe.Id;
                        oli.Quantity = qty;
                        oli.UnitPrice = targetPrice != null ? targetPrice : pbe.UnitPrice;
                        oli.Description = buildLineDescription(line);
                        insert oli;
                        oliCreated = true;
                    }
                }

                String oppUrl = URL.getOrgDomainUrl().toExternalForm() + '/' + opp.Id;
                successCount++;
                messages.add('Created: ' +
                    '<a href=\'' + oppUrl + '\' target="_blank">' + opp.Name + '</a>' +
                    (oliCreated ? '' : ' (no matching product)')
                );
            } catch (Exception ex) {
                failureCount++;
                messages.add('Failed at item ' + String.valueOf(idx) + ': ' + ex.getMessage());
            }
        }

        if (totalLineItems > MAX_REVIEWABLE_LINE_ITEMS) {
            messages.add(
                'Only first ' + String.valueOf(MAX_REVIEWABLE_LINE_ITEMS) +
                ' items were created to match screen preview limit.'
            );
        }

        Result res = new Result();
        res.createdCount = successCount;
        res.failedCount = failureCount;
        res.message = String.join(messages, '<br/>');
        return res;
    }

    private static String buildLineDescription(Map<String, Object> line) {
        List<String> parts = new List<String>();
        String appNotes = cleanStr(line.get('application_notes'));
        if (String.isNotBlank(appNotes)) {
            parts.add('Application: ' + appNotes);
        }
        String delivery = cleanStr(line.get('delivery_requirement'));
        if (String.isNotBlank(delivery)) {
            parts.add('Delivery: ' + delivery);
        }
        return parts.isEmpty() ? null : String.join(parts, ' | ');
    }

    private static String buildOpportunityDescription(Map<String, Object> parsed, Map<String, Object> line, EmailContext ctx, String rawJson) {
        List<String> sections = new List<String>();

        if (parsed.get('customer_info') instanceof Map<String, Object>) {
            Map<String, Object> ci = (Map<String, Object>) parsed.get('customer_info');
            String customerSummary = joinNonBlank(
                new List<String>{
                    cleanStr(ci.get('name')),
                    cleanStr(ci.get('title')),
                    cleanStr(ci.get('company_context'))
                },
                ' | '
            );
            if (String.isNotBlank(customerSummary)) {
                sections.add('Customer: ' + customerSummary);
            }
            String deadline = cleanStr(ci.get('request_deadline'));
            if (String.isNotBlank(deadline)) {
                sections.add('Deadline: ' + deadline);
            }
        }

        if (parsed.get('general_requirements') instanceof Map<String, Object>) {
            Map<String, Object> gr = (Map<String, Object>) parsed.get('general_requirements');
            String production = cleanStr(gr.get('production_schedule'));
            if (String.isNotBlank(production)) {
                sections.add('Production Schedule: ' + production);
            }
            String terms = cleanStr(gr.get('special_terms'));
            if (String.isNotBlank(terms)) {
                sections.add('Special Terms: ' + terms);
            }
        }

        Decimal qty = safeDecimal(line.get('quantity'));
        String qtyLabel = qty != null ? 'Qty ' + String.valueOf(qty) : 'Qty N/A';
        String lineSummary = joinNonBlank(
            new List<String>{
                cleanStr(line.get('manufacturer')),
                cleanStr(line.get('part_number')),
                qtyLabel
            },
            ' | '
        );
        if (String.isNotBlank(lineSummary)) {
            sections.add('Line: ' + lineSummary);
        } else {
            sections.add('Line item from prompt');
        }

        if (String.isNotBlank(ctx.body)) {
            sections.add('Email snippet:\n' + ctx.body.left(1000));
        }

        if (String.isNotBlank(rawJson)) {
            sections.add('Prompt JSON:\n' + rawJson.left(8000));
        }
        return String.join(sections, '\n\n');
    }

    private static String buildOppName(Map<String, Object> line, EmailContext ctx) {
        String manufacturer = cleanStr(line.get('manufacturer'));
        String partNumber = cleanStr(line.get('part_number'));
        String base = joinNonBlank(
            new List<String>{ manufacturer, partNumber },
            ' '
        );
        if (String.isBlank(base)) {
            base = String.isNotBlank(ctx.subject) ? ctx.subject : 'Opportunity from Email';
        } else if (String.isNotBlank(ctx.subject)) {
            base = base + ' - ' + ctx.subject;
        }
        return base;
    }

    private static PricebookEntry findPricebookEntry(Map<String, Object> line, Id pricebookId) {
        Product2 product = findProduct(line);
        if (product == null) {
            return null;
        }

        List<PricebookEntry> entries = [
            SELECT Id, UnitPrice
            FROM PricebookEntry
            WHERE Pricebook2Id = :pricebookId
              AND Product2Id = :product.Id
              AND IsActive = true
            LIMIT 1
        ];
        return entries.isEmpty() ? null : entries[0];
    }

    private static Product2 findProduct(Map<String, Object> line) {
        String[] candidates = new String[] {
            cleanStr(line.get('part_number')),
            cleanStr(line.get('manufacturer'))
        };

        for (String key : candidates) {
            if (String.isBlank(key)) {
                continue;
            }
            String pattern = '%' + escapeLike(key) + '%';
            List<Product2> products = [
                SELECT Id, Name
                FROM Product2
                WHERE IsActive = true
                  AND Name LIKE :pattern
                LIMIT 1
            ];
            if (!products.isEmpty()) {
                return products[0];
            }
        }
        return null;
    }

    private static EmailContext resolveEmailContext(Id emailId) {
        EmailContext ctx = new EmailContext();
        if (emailId == null) {
            return ctx;
        }

        try {
            EmailMessage em = [
                SELECT Id, Subject, TextBody, HtmlBody, FromAddress
                FROM EmailMessage
                WHERE Id = :emailId
                LIMIT 1
            ];
            ctx.subject = em.Subject;
            ctx.fromAddress = em.FromAddress;
            ctx.body = String.isNotBlank(em.TextBody) ? em.TextBody : stripHtml(em.HtmlBody);

            if (String.isNotBlank(em.FromAddress)) {
                List<Contact> contacts = [
                    SELECT Id, AccountId
                    FROM Contact
                    WHERE Email = :em.FromAddress
                    LIMIT 1
                ];
                if (!contacts.isEmpty()) {
                    ctx.contactId = contacts[0].Id;
                    ctx.accountId = contacts[0].AccountId;
                }
            }

            if (ctx.accountId == null && String.isNotBlank(em.FromAddress)) {
                String domain;
                Integer atPos = em.FromAddress.indexOf('@');
                if (atPos > -1) {
                    domain = em.FromAddress.substring(atPos + 1).trim().toLowerCase();
                }
                if (domain != null) {
                    if (domain.contains('>')) domain = domain.substring(0, domain.indexOf('>'));
                    if (domain.contains(';')) domain = domain.substring(0, domain.indexOf(';'));

                    List<Account> accounts = [
                        SELECT Id
                        FROM Account
                        WHERE Website LIKE :('%' + domain + '%')
                        LIMIT 1
                    ];
                    if (!accounts.isEmpty()) {
                        ctx.accountId = accounts[0].Id;
                    }
                }
            }
        } catch (QueryException qex) {
            throw new FlowException('找不到指定的 EmailMessage：' + qex.getMessage());
        }

        return ctx;
    }

    private static Id getStandardPricebookId() {
        List<Pricebook2> pbs = [
            SELECT Id
            FROM Pricebook2
            WHERE IsStandard = true
            LIMIT 1
        ];
        return pbs.isEmpty() ? null : pbs[0].Id;
    }

    private static String getDefaultStageName() {
        List<OpportunityStage> stages = [
            SELECT MasterLabel, SortOrder
            FROM OpportunityStage
            WHERE IsActive = true
            ORDER BY SortOrder ASC
        ];

        // Prefer open quote/proposal stages across common org variants.
        for (OpportunityStage os : stages) {
            if (os.MasterLabel == 'Proposal/Quote') {
                return os.MasterLabel;
            }
        }
        for (OpportunityStage os : stages) {
            if (os.MasterLabel == 'Proposal/Price Quote') {
                return os.MasterLabel;
            }
        }

        // Fall back to the first active non-closed stage.
        Map<String, OpportunityStage> stageByLabel = new Map<String, OpportunityStage>();
        for (OpportunityStage os : stages) {
            stageByLabel.put(os.MasterLabel, os);
        }
        Set<String> closedStageLabels = new Set<String>();
        for (OpportunityStage closedStage : [
            SELECT MasterLabel
            FROM OpportunityStage
            WHERE IsActive = true
              AND IsClosed = true
        ]) {
            closedStageLabels.add(closedStage.MasterLabel);
        }
        for (OpportunityStage os : stages) {
            if (!closedStageLabels.contains(os.MasterLabel)) {
                return os.MasterLabel;
            }
        }

        if (!stages.isEmpty()) {
            return stages[0].MasterLabel;
        }
        return 'Prospecting';
    }

    private static Decimal extractTargetPrice(Map<String, Object> line) {
        if (line == null) return null;
        Object raw = line.get('target_price');
        if (raw instanceof Map<String, Object>) {
            Map<String, Object> tp = (Map<String, Object>) raw;
            return safeDecimal(tp.get('value'));
        }
        return safeDecimal(raw);
    }

    private static Date parseCloseDate(Object raw) {
        if (raw == null) return null;
        try {
            return Date.valueOf(String.valueOf(raw));
        } catch (Exception ex) {
            return null;
        }
    }

    private static String joinNonBlank(List<String> values, String separator) {
        List<String> cleaned = new List<String>();
        for (String v : values) {
            if (String.isNotBlank(v)) cleaned.add(v);
        }
        return cleaned.isEmpty() ? '' : String.join(cleaned, separator);
    }

    private static String cleanStr(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }

    private static Decimal safeDecimal(Object input) {
        if (input == null) return null;
        try {
            if (input instanceof Decimal) return (Decimal) input;
            if (input instanceof Integer) return Decimal.valueOf((Integer) input);
            if (input instanceof Long) return Decimal.valueOf((Long) input);
            if (input instanceof Double) return Decimal.valueOf((Double) input);
            return Decimal.valueOf(String.valueOf(input));
        } catch (Exception ex) {
            return null;
        }
    }

    private static String escapeLike(String value) {
        if (value == null) return null;
        String escaped = value.replace('\\', '\\\\');
        escaped = escaped.replace('%', '\\%');
        escaped = escaped.replace('_', '\\_');
        return escaped;
    }

    private static String stripHtml(String html) {
        if (String.isBlank(html)) return null;
        return Pattern.compile('<[^>]+>').matcher(html).replaceAll('');
    }
}