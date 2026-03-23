public with sharing class CM_AccountPlanSWOTInvoker {

    public class Request {
        @InvocableVariable(required=true)
        public Id accountPlanId;
    }

    public class Result {
        @InvocableVariable
        public Boolean success;

        @InvocableVariable
        public String message;
    }

    @InvocableMethod(label='Generate SWOT from Prompt' description='Generate SWOT and write back to AccountPlan')
    public static List<Result> generate(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) {
            Result r = new Result();
            r.success = false;
            r.message = 'No request payload.';
            results.add(r);
            return results;
        }

        Set<Id> planIds = new Set<Id>();
        for (Request req : requests) {
            if (req != null && req.accountPlanId != null) {
                planIds.add(req.accountPlanId);
            }
        }

        Map<Id, AccountPlan> plans = new Map<Id, AccountPlan>([
            SELECT Id, Name, AccountId, Account.Name, Account.Industry, Account.Website, Account.Description,
                   Status, Notes, AccountVision,
                   RelationshipStrengths, RelationshipWeaknesses, RelationshipOpportunities, RelationshipThreats
            FROM AccountPlan
            WHERE Id IN :planIds
        ]);

        for (Request req : requests) {
            Result res = new Result();
            if (req == null || req.accountPlanId == null || !plans.containsKey(req.accountPlanId)) {
                res.success = false;
                res.message = 'AccountPlan not found.';
                results.add(res);
                continue;
            }

            AccountPlan plan = plans.get(req.accountPlanId);
            if (plan.AccountId == null) {
                res.success = false;
                res.message = 'AccountPlan missing AccountId.';
                results.add(res);
                continue;
            }

            try {
                Map<String, Object> swotMap;
                String statusMessage;
                try {
                    String promptOutput = invokePrompt(plan.AccountId);
                    Map<String, Object> parsed = parseJsonObject(promptOutput);
                    if (parsed == null) {
                        // Retry once in case the first generation returns malformed JSON.
                        promptOutput = invokePrompt(plan.AccountId);
                        parsed = parseJsonObject(promptOutput);
                    }
                    if (parsed == null) {
                        throw new AuraHandledException('PROMPT_OUTPUT_INVALID_JSON');
                    }
                    swotMap = extractSwotMap(parsed);
                    if (swotMap == null) {
                        throw new AuraHandledException('PROMPT_OUTPUT_MISSING_SWOT');
                    }
                    statusMessage = 'SWOT generated and updated.';
                } catch (Exception promptException) {
                    Boolean unavailable = isEinsteinGenerationUnavailable(promptException);
                    Boolean invalidOutput = isPromptOutputInvalid(promptException);
                    if (!unavailable && !invalidOutput) {
                        throw promptException;
                    }
                    swotMap = buildFallbackSwot(plan);
                    statusMessage = unavailable
                        ? 'Einstein 服務目前無法回應，已使用 fallback SWOT 內容回填。'
                        : 'AI 回傳格式異常，已使用 fallback SWOT 內容回填。';
                }

                AccountPlan p = new AccountPlan(Id = req.accountPlanId);
                String strengths = normalizeSwotSection(swotMap.get('strengths_html'));
                String weaknesses = normalizeSwotSection(swotMap.get('weaknesses_html'));
                String opportunities = normalizeSwotSection(swotMap.get('opportunities_html'));
                String threats = normalizeSwotSection(swotMap.get('threats_html'));
                if (hasMissingSwotSections(strengths, weaknesses, opportunities, threats)) {
                    Map<String, Object> completeFallback = buildFallbackSwot(plan);
                    strengths = normalizeSwotSection(completeFallback.get('strengths_html'));
                    weaknesses = normalizeSwotSection(completeFallback.get('weaknesses_html'));
                    opportunities = normalizeSwotSection(completeFallback.get('opportunities_html'));
                    threats = normalizeSwotSection(completeFallback.get('threats_html'));
                    statusMessage = 'AI 回傳 SWOT 欄位不完整，已使用 fallback SWOT 內容回填。';
                }
                // Overwrite all four sections to keep the SWOT snapshot consistent.
                p.RelationshipStrengths = strengths;
                p.RelationshipWeaknesses = weaknesses;
                p.RelationshipOpportunities = opportunities;
                p.RelationshipThreats = threats;

                Database.SaveResult saveResult = Database.update(p, false);
                if (!saveResult.isSuccess()) {
                    res.success = false;
                    res.message = 'Generate SWOT failed during save: ' + formatDmlErrors(saveResult.getErrors());
                } else {
                    res.success = true;
                    res.message = statusMessage;
                }
            } catch (Exception e) {
                res.success = false;
                res.message = 'Generate SWOT failed: ' + String.valueOf(e);
            }
            results.add(res);
        }

        return results;
    }

    private static String invokePrompt(Id accountId) {
        ConnectApi.EinsteinPromptTemplateGenerationsInput input = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        input.isPreview = false;
        input.inputParams = new Map<String, ConnectApi.WrappedValue>();

        ConnectApi.WrappedValue relatedEntity = new ConnectApi.WrappedValue();
        relatedEntity.value = new Map<String, String>{ 'id' => String.valueOf(accountId) };
        input.inputParams.put('Input:Account', relatedEntity);

        ConnectApi.EinsteinLlmAdditionalConfigInput additionalConfig =
            new ConnectApi.EinsteinLlmAdditionalConfigInput();
        additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
        input.additionalConfig = additionalConfig;

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation response =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate('CM_SWOT_Analysis', input);

        if (response == null || response.generations == null || response.generations.isEmpty()) {
            throw new AuraHandledException('Prompt response is empty.');
        }
        return response.generations[0].text;
    }

    private static Map<String, Object> parseJsonObject(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String content = raw.trim();
        Integer firstBrace = content.indexOf('{');
        Integer lastBrace = content.lastIndexOf('}');
        if (firstBrace < 0 || lastBrace < 0 || lastBrace <= firstBrace) {
            return null;
        }
        String jsonText = normalizeJsonText(content.substring(firstBrace, lastBrace + 1));
        try {
            Object parsed = JSON.deserializeUntyped(jsonText);
            if (parsed instanceof Map<String, Object>) {
                return (Map<String, Object>) parsed;
            }
        } catch (Exception ex) {
            return null;
        }
        return null;
    }

    private static String normalizeJsonText(String jsonText) {
        if (jsonText == null) {
            return null;
        }
        return jsonText
            .replace('\u00A0', ' ')
            .replace('\u2007', ' ')
            .replace('\u202F', ' ')
            .replace('\u200B', '')
            .replace('\u200C', '')
            .replace('\u200D', '')
            .replace('\uFEFF', '');
    }

    private static Map<String, Object> extractSwotMap(Map<String, Object> parsed) {
        if (parsed == null) {
            return null;
        }
        Object swot = parsed.get('account_plan_swot');
        if (swot instanceof Map<String, Object>) {
            return (Map<String, Object>) swot;
        }

        // Backward compatibility for v1 prompt output without account_plan_swot.
        Map<String, Object> fallback = new Map<String, Object>();
        fallback.put('strengths_html', toHtmlList(asStringList(parsed.get('positive_signals'))));
        fallback.put('weaknesses_html', toHtmlList(extractRiskLines(parsed, false)));
        fallback.put('opportunities_html', toHtmlList(asStringList(parsed.get('recommended_actions'))));
        fallback.put('threats_html', toHtmlList(extractRiskLines(parsed, true)));
        return fallback;
    }

    private static Boolean isEinsteinGenerationUnavailable(Exception e) {
        if (!(e instanceof ConnectApi.ConnectApiException)) {
            return false;
        }
        String message = String.valueOf(e);
        return message.contains('Failed to generate Einstein LLM generations response')
            || message.contains('errorCode=INTERNAL_ERROR');
    }

    private static Boolean isPromptOutputInvalid(Exception e) {
        if (e == null) {
            return false;
        }
        String typeName = e.getTypeName();
        String message = String.valueOf(e);
        return typeName == 'System.JSONException'
            || message.contains('PROMPT_OUTPUT_INVALID_JSON')
            || message.contains('PROMPT_OUTPUT_MISSING_SWOT')
            || message.contains('Unexpected character');
    }

    private static Map<String, Object> buildFallbackSwot(AccountPlan plan) {
        String accountName = (plan != null && plan.Account != null) ? plan.Account.Name : '此供應商';
        String industry = (plan != null && plan.Account != null) ? plan.Account.Industry : null;
        String website = (plan != null && plan.Account != null) ? plan.Account.Website : null;
        String accountDescription = (plan != null && plan.Account != null) ? plan.Account.Description : null;

        List<String> strengths = new List<String>();
        strengths.add(accountName + ' 已納入 Account Plan 管理，可直接納入年度供應策略討論。');
        if (!String.isBlank(industry)) {
            strengths.add('供應商所屬產業為「' + industry + '」，可依產業特性提前規劃備料與交期策略。');
        }
        if (!String.isBlank(website)) {
            strengths.add('具備公開官方資訊與窗口（' + website + '），有利於跨部門協作與異常升級溝通。');
        }

        List<String> weaknesses = new List<String>();
        if (String.isBlank(accountDescription)) {
            weaknesses.add('目前供應商描述資料不足，缺少產能、良率與交期穩定性等關鍵資訊。');
        } else {
            weaknesses.add('現有供應商描述偏摘要，仍需補齊可量化的產能/交期/成本指標。');
        }
        weaknesses.add('尚未明確建立跨廠區備援與異地生產可切換方案，供應韌性可見度不足。');
        weaknesses.add('缺少可直接支援 allocation 決策的週期性 forecast 機制與風險預警指標。');

        List<String> opportunities = new List<String>();
        opportunities.add('啟動 12 個月滾動 forecast 與季度 QBR（Quarterly Business Review）機制，提升需求可見度。');
        opportunities.add('就關鍵料號評估長約（LTA）與最低產能承諾（Capacity Commitment），降低高峰期斷料風險。');
        opportunities.add('推動 VMI 或 Hub 倉合作，降低在製與在途庫存壓力並縮短緊急拉貨反應時間。');
        opportunities.add('建立 Second Source 驗證路線圖，降低單一供應來源風險。');

        List<String> threats = new List<String>();
        threats.add('地緣政治與出口管制政策可能影響跨區供應連續性與合規成本。');
        threats.add('若終端需求快速回升，可能發生產能排擠與 allocation 優先級下降。');
        threats.add('匯率與原物料價格波動將直接放大採購成本不確定性。');

        Map<String, Object> swot = new Map<String, Object>();
        swot.put('strengths_html', toHtmlList(strengths));
        swot.put('weaknesses_html', toHtmlList(weaknesses));
        swot.put('opportunities_html', toHtmlList(opportunities));
        swot.put('threats_html', toHtmlList(threats));
        return swot;
    }

    private static List<String> asStringList(Object value) {
        List<String> items = new List<String>();
        if (!(value instanceof List<Object>)) {
            return items;
        }
        for (Object item : (List<Object>) value) {
            if (item != null) {
                String text = String.valueOf(item).trim();
                if (!String.isBlank(text)) {
                    items.add(text);
                }
            }
        }
        return items;
    }

    private static List<String> extractRiskLines(Map<String, Object> parsed, Boolean includeImpact) {
        List<String> lines = new List<String>();
        Object raw = parsed.get('key_risks');
        if (!(raw instanceof List<Object>)) {
            return lines;
        }
        for (Object item : (List<Object>) raw) {
            if (!(item instanceof Map<String, Object>)) {
                if (item != null) {
                    lines.add(String.valueOf(item));
                }
                continue;
            }
            Map<String, Object> risk = (Map<String, Object>) item;
            List<String> parts = new List<String>();
            String title = asString(risk.get('title'));
            String reason = asString(risk.get('reason'));
            String impact = asString(risk.get('impact'));
            if (!String.isBlank(title)) {
                parts.add(title);
            }
            if (includeImpact && !String.isBlank(impact)) {
                parts.add('Impact: ' + impact);
            }
            if (!String.isBlank(reason)) {
                parts.add(reason);
            }
            String line = String.join(parts, ' - ');
            if (!String.isBlank(line)) {
                lines.add(line);
            }
        }
        return lines;
    }

    private static String toHtmlList(List<String> items) {
        if (items == null || items.isEmpty()) {
            return null;
        }
        String html = '<ul>';
        for (String item : items) {
            html += '<li>' + escapeHtml(item) + '</li>';
        }
        html += '</ul>';
        return html;
    }

    private static String asString(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static String normalizeSwotSection(Object rawValue) {
        if (rawValue == null) {
            return null;
        }
        String normalized = String.valueOf(rawValue).trim();
        return String.isBlank(normalized) ? null : normalized;
    }

    private static Boolean hasMissingSwotSections(
        String strengths,
        String weaknesses,
        String opportunities,
        String threats
    ) {
        return String.isBlank(strengths)
            || String.isBlank(weaknesses)
            || String.isBlank(opportunities)
            || String.isBlank(threats);
    }

    private static String formatDmlErrors(Database.Error[] errors) {
        if (errors == null || errors.isEmpty()) {
            return 'Unknown save error.';
        }
        List<String> messages = new List<String>();
        for (Database.Error errorRecord : errors) {
            if (errorRecord != null && !String.isBlank(errorRecord.getMessage())) {
                messages.add(errorRecord.getMessage());
            }
        }
        return messages.isEmpty() ? 'Unknown save error.' : String.join(messages, ' | ');
    }

    private static String escapeHtml(String input) {
        if (input == null) {
            return null;
        }
        return input
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;');
    }
}