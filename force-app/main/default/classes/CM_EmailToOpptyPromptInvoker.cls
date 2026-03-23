public with sharing class CM_EmailToOpptyPromptInvoker {

    public class Request {
        @InvocableVariable(required=true label='EmailMessage Id')
        public Id emailMessageId;
    }

    public class Result {
        @InvocableVariable(label='Prompt JSON')
        public String rawJson;

        @InvocableVariable(label='Line Item Preview')
        public String summary;

        @InvocableVariable(label='Email Subject')
        public String subject;

        @InvocableVariable(label='Email Body')
        public String emailBody;
    }

    @InvocableMethod(label='Analyze Email for Opportunities')
    public static List<Result> run(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            throw new FlowException('EmailMessage Id is required.');
        }

        // ===== Bulk-safe 收集 Email Id =====
        Set<Id> emailIds = new Set<Id>();
        for (Request req : requests) {
            if (req == null || req.emailMessageId == null) {
                throw new FlowException('EmailMessage Id is required.');
            }
            emailIds.add(req.emailMessageId);
        }

        // ===== 一次查出所有 EmailMessage =====
        Map<Id, EmailMessage> emById = new Map<Id, EmailMessage>(
            [
                SELECT Id, Subject, TextBody, HtmlBody
                FROM EmailMessage
                WHERE Id IN :emailIds
            ]
        );

        List<Result> outputs = new List<Result>();

        for (Request req : requests) {
            EmailMessage em = emById.get(req.emailMessageId);
            if (em == null) {
                throw new FlowException('找不到對應的 EmailMessage：' + String.valueOf(req.emailMessageId));
            }

            String plainBody   = resolvePlainBody(em);
            String emailContent = normalizeEmailContent(em, plainBody);

            // 呼叫 Prompt
            String llmOutput = callPrompt(emailContent);

            // 擷取 JSON 部分
            String jsonText = extractJson(llmOutput);
            if (String.isBlank(jsonText)) {
                throw new FlowException('Prompt CM_Email_To_Opptys did not return JSON text.');
            }

            // ✅ 這裡先把 non-breaking space 等怪字元處理掉
            String cleanedJson = normalizeJson(jsonText);

            // 產生 Summary
            String summary = buildSummary(cleanedJson);

            Result res = new Result();
            res.rawJson  = cleanedJson;   // 回給 Flow 的是已清洗版本
            res.summary  = summary;
            res.subject  = em.Subject;
            res.emailBody = plainBody;
            outputs.add(res);
        }

        return outputs;
    }

    // ===== Internal Helpers =====

    // Subject + plain text body 合併給 Prompt
    private static String normalizeEmailContent(EmailMessage em, String plainBody) {
        String body = plainBody;

        List<String> parts = new List<String>();
        if (String.isNotBlank(em.Subject)) {
            parts.add('Subject: ' + em.Subject);
        }
        if (String.isNotBlank(body)) {
            parts.add(body);
        }
        return String.join(parts, '\n\n');
    }

    private static String resolvePlainBody(EmailMessage em) {
        String body = em.TextBody;
        if (String.isBlank(body)) {
            body = stripHtml(em.HtmlBody);
        }
        return body;
    }

    // 呼叫 Prompt Builder template CM_Email_To_Opptys
    private static String callPrompt(String emailContent) {
        if (String.isBlank(emailContent)) {
            throw new FlowException('Email content is empty.');
        }

        try {
            ConnectApi.WrappedValue value = new ConnectApi.WrappedValue();
            value.value = emailContent;

            Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();

            // ✅ 最重要：對齊 Prompt 中的 {!$Input:Email}
            inputParams.put('Input:Email', value);

            // 其他 alias（可留可刪）
            inputParams.put('Input:emailContent', value);
            inputParams.put('Input:email_content', value);
            inputParams.put('Input:email_body', value);
            inputParams.put('Input:body', value);
            inputParams.put('Input:email', value);

            ConnectApi.EinsteinPromptTemplateGenerationsInput promptInput =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            promptInput.inputParams = inputParams;
            promptInput.isPreview = false;

            ConnectApi.EinsteinLlmAdditionalConfigInput addCfg =
                new ConnectApi.EinsteinLlmAdditionalConfigInput();
            addCfg.applicationName = 'PromptTemplateGenerationsInvocable';
            promptInput.additionalConfig = addCfg;

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation res =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate('CM_Email_To_Opptys', promptInput);

            if (res != null && res.generations != null && !res.generations.isEmpty()) {
                return res.generations[0].text;
            }
            return null;
        } catch (Exception ex) {
            throw new FlowException('無法呼叫 Prompt CM_Email_To_Opptys：' + ex.getMessage());
        }
    }

    // 擷取第一個 JSON Object
    private static String extractJson(String llmOutput) {
        if (String.isBlank(llmOutput)) {
            return null;
        }

        String trimmed = llmOutput.trim();
        if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
            return trimmed;
        }

        Integer startIndex = llmOutput.indexOf('{');
        Integer endIndex   = llmOutput.lastIndexOf('}');
        if (startIndex > -1 && endIndex > startIndex) {
            return llmOutput.substring(startIndex, endIndex + 1);
        }
        return null;
    }

    // ✅ 清洗 JSON：把 non-breaking space 等怪空白換掉
    private static String normalizeJson(String jsonText) {
        if (String.isBlank(jsonText)) return jsonText;

        String cleaned = jsonText;

        // code 160 = non-breaking space
        String nbsp = String.fromCharArray(new List<Integer>{160});
        cleaned = cleaned.replace(nbsp, ' ');

        // 如果怕有全形空白（\u3000），也可以順便處理：
        String fullWidthSpace = String.fromCharArray(new List<Integer>{12288});
        cleaned = cleaned.replace(fullWidthSpace, ' ');

        // 如果 LLM 不小心在最前面塞 BOM（很少見），順手處理一下
        String bom = String.fromCharArray(new List<Integer>{65279});
        if (cleaned.startsWith(bom)) {
            cleaned = cleaned.substring(bom.length());
        }

        return cleaned;
    }

    // 把 line_items 變成 Flow 畫面上好讀的 summary
    private static String buildSummary(String jsonText) {
        Map<String, Object> parsed;
        try {
            parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonText);
        } catch (Exception ex) {
            throw new FlowException('Prompt JSON 解析失敗：' + ex.getMessage());
        }

        List<String> lines = new List<String>();
        Object rawItems = parsed.get('line_items');
        if (rawItems instanceof List<Object>) {
            Integer position = 0;
            for (Object obj : (List<Object>) rawItems) {
                position++;
                if (!(obj instanceof Map<String, Object>)) {
                    continue;
                }
                Map<String, Object> item = (Map<String, Object>) obj;

                String manufacturer = cleanStr(item.get('manufacturer'));
                String partNumber   = cleanStr(item.get('part_number'));
                Integer qty         = safeInteger(item.get('quantity'));

                Decimal target = null;
                String  currencyCode = null;
                Object rawTarget = item.get('target_price');
                if (rawTarget instanceof Map<String, Object>) {
                    Map<String, Object> targetMap = (Map<String, Object>) rawTarget;
                    target       = safeDecimal(targetMap.get('value'));
                    currencyCode = cleanStr(targetMap.get('currency'));
                } else {
                    target = safeDecimal(rawTarget);
                }

                List<String> segments = new List<String>();

                String namePart = String.join(
                    new List<String>{
                        manufacturer != null ? manufacturer : '',
                        partNumber   != null ? partNumber   : ''
                    },
                    ' '
                ).trim();
                segments.add(String.isNotBlank(namePart) ? namePart : 'Line ' + String.valueOf(position));

                segments.add('Qty: ' + (qty != null ? String.valueOf(qty) : 'N/A'));

                if (target != null) {
                    segments.add(
                        'Target: ' +
                        (String.isNotBlank(currencyCode) ? currencyCode + ' ' : '') +
                        String.valueOf(target)
                    );
                }

                String delivery = cleanStr(item.get('delivery_requirement'));
                if (String.isNotBlank(delivery)) {
                    segments.add('Delivery: ' + delivery);
                }

                String appNotes = cleanStr(item.get('application_notes'));
                if (String.isNotBlank(appNotes)) {
                    segments.add('App: ' + appNotes);
                }

                lines.add('- ' + String.join(segments, ' | '));
            }
        }

        if (lines.isEmpty()) {
            lines.add('No line items detected from prompt output.');
        }
        return String.join(lines, '\n');
    }

    private static String cleanStr(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }

    private static Integer safeInteger(Object input) {
        if (input == null) return null;
        try {
            if (input instanceof Integer) return (Integer) input;
            return Integer.valueOf(String.valueOf(input));
        } catch (Exception ex) {
            return null;
        }
    }

    private static Decimal safeDecimal(Object input) {
        if (input == null) return null;
        try {
            if (input instanceof Decimal) return (Decimal) input;
            return Decimal.valueOf(String.valueOf(input));
        } catch (Exception ex) {
            return null;
        }
    }

    private static String stripHtml(String html) {
        if (String.isBlank(html)) return null;
        // Quick and simple tag removal for flow prompt input.
        return Pattern.compile('<[^>]+>').matcher(html).replaceAll('');
    }

    // ===== Debug Helpers (for Execute Anonymous / Test) =====

    @TestVisible
    public static String debugBuildSummary(String jsonText) {
        // debug 時也幫你清理一次
        return buildSummary(normalizeJson(jsonText));
    }

    @TestVisible
    public static String debugCallPrompt(String emailContent) {
        return callPrompt(emailContent);
    }

    @TestVisible
    public static String debugExtractJson(String llmOutput) {
        return extractJson(llmOutput);
    }

    @TestVisible
    public static String debugNormalizeJson(String jsonText) {
        return normalizeJson(jsonText);
    }
}