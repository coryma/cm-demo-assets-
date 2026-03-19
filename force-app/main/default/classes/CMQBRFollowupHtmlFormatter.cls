public with sharing class CMQBRFollowupHtmlFormatter {
    public static String formatJsonToHtml(String rawJson) {
        return formatSingle(rawJson);
    }

    public static String normalizeJson(String rawJson) {
        if (String.isBlank(rawJson)) {
            return rawJson;
        }

        String cleaned = sanitizeJson(rawJson);
        Map<String, Object> payload = parsePayloadWithRepair(cleaned);
        return payload.isEmpty() ? cleaned : JSON.serialize(payload);
    }

    @InvocableMethod(
        label='CM Format QBR Follow-up HTML'
        description='Formats QBR follow-up JSON into deterministic HTML'
    )
    public static List<Response> formatHtml(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            try {
                res.formattedHtml = formatSingle(req == null ? null : req.jsonString);
            } catch (Exception ex) {
                res.formattedHtml =
                    '<h2>會議決議總覽</h2><p>無法解析會議分析資料。</p>' +
                    '<h2>關鍵風險與待確認</h2><p>請檢查 JSON 輸出格式是否正確。</p>' +
                    '<h2>會後行動清單</h2><p>目前無法產生行動清單。</p>';
            }
            responses.add(res);
        }
        return responses;
    }

    private static String formatSingle(String rawJson) {
        if (String.isBlank(rawJson)) {
            return emptyStateHtml();
        }

        Map<String, Object> payload = parsePayloadWithRepair(rawJson);
        if (payload.isEmpty()) {
            return emptyStateHtml();
        }
        if (isNewSchema(payload)) {
            return formatNewSchema(payload);
        }
        return formatLegacySchema(payload);
    }

    private static Map<String, Object> parsePayloadWithRepair(String rawJson) {
        String cleaned = sanitizeJson(rawJson);
        Map<String, Object> payload = tryParseMap(cleaned);
        if (!payload.isEmpty()) {
            return payload;
        }

        String repaired = repairJsonText(cleaned);
        if (String.isBlank(repaired) || repaired == cleaned) {
            return payload;
        }
        return tryParseMap(repaired);
    }

    private static Boolean isNewSchema(Map<String, Object> payload) {
        return payload.containsKey('meeting_decision_overview')
            || payload.containsKey('key_risks_and_pending_items')
            || payload.containsKey('follow_up_actions');
    }

    private static String formatNewSchema(Map<String, Object> payload) {
        String html = '';

        Map<String, Object> overview = asMap(payload.get('meeting_decision_overview'));
        List<Object> decisions = asList(overview.get('confirmed_decisions'));
        List<Object> risks = asList(payload.get('key_risks_and_pending_items'));
        List<Object> actions = asList(payload.get('follow_up_actions'));

        html += '<h2>會議決議總覽</h2>';
        if (!String.isBlank(getString(overview, 'vendorName'))) {
            html += '<p><strong>供應商：</strong>' +
                escape(getString(overview, 'vendorName')) +
                '</p>';
        }
        if (!String.isBlank(getString(overview, 'summary'))) {
            html += '<p>' +
                escape(getString(overview, 'summary')) +
                '</p>';
        }
        if (decisions.isEmpty()) {
            html += '<p>目前無明確資料</p>';
        } else {
            html += '<ul>';
            for (Object item : decisions) {
                Map<String, Object> decision = asMap(item);
                String typeLabel = valueOrFallback(getString(decision, 'type'), '決議');
                String description = valueOrFallback(getString(decision, 'description'), '目前無明確資料');
                List<String> suffixParts = new List<String>();
                if (!String.isBlank(getString(decision, 'value'))) {
                    suffixParts.add(getString(decision, 'value'));
                }
                if (!String.isBlank(getString(decision, 'status'))) {
                    suffixParts.add(translateStatus(getString(decision, 'status')));
                }
                String detail = description;
                if (!suffixParts.isEmpty()) {
                    detail += '（' + String.join(suffixParts, '；') + '）';
                }
                html += '<li><strong>' +
                    escape(typeLabel) +
                    '：</strong>' +
                    escape(detail) +
                    '</li>';
            }
            html += '</ul>';
        }

        html += '<h2>關鍵風險與待確認</h2>';
        if (risks.isEmpty()) {
            html += '<p>目前無明確資料</p>';
        } else {
            html += '<ul>';
            for (Object item : risks) {
                Map<String, Object> risk = asMap(item);
                html += '<li>';
                html += '<p><strong>' +
                    escape(valueOrFallback(getString(risk, 'topic'), '待確認事項')) +
                    '：</strong>' +
                    escape(valueOrFallback(getString(risk, 'riskOrPending'), '目前無明確資料')) +
                    '</p>';
                if (!String.isBlank(getString(risk, 'impact'))) {
                    html += '<p><strong>影響：</strong>' +
                        escape(getString(risk, 'impact')) +
                        '</p>';
                }
                html += '<p><strong>責任窗口：</strong>' +
                    escape(normalizeOwner(valueOrFallback(getString(risk, 'owner'), '待確認'))) +
                    '</p>';
                html += '</li>';
            }
            html += '</ul>';
        }

        html += '<h2>會後行動清單</h2>';
        html = appendActions(html, actions, false);

        return html;
    }

    private static String formatLegacySchema(Map<String, Object> payload) {
        String html = '';

        Map<String, Object> interaction = asMap(payload.get('interaction'));
        Map<String, Object> lead = asMap(payload.get('lead'));
        Map<String, Object> opportunity = asMap(payload.get('opportunity'));
        List<Object> tasks = asList(payload.get('tasks'));

        html += '<h2>會議決議總覽</h2>';
        Boolean hasOverview = false;
        if (!String.isBlank(getString(lead, 'companyName'))) {
            html += '<p><strong>關聯對象：</strong>' +
                escape(getString(lead, 'companyName')) +
                '</p>';
            hasOverview = true;
        }
        if (!String.isBlank(getString(interaction, 'subject'))) {
            html += '<p><strong>會議主題：</strong>' +
                escape(getString(interaction, 'subject')) +
                '</p>';
            hasOverview = true;
        }
        List<String> legacyItems = new List<String>();
        if (!String.isBlank(getString(lead, 'description'))) {
            legacyItems.add('企業需求：' + getString(lead, 'description'));
        }
        if (!String.isBlank(getString(opportunity, 'name'))) {
            String oppLine = '商務機會：' + getString(opportunity, 'name');
            if (!String.isBlank(getString(opportunity, 'amount'))) {
                oppLine += '（金額：' + getString(opportunity, 'amount') + '）';
            }
            if (!String.isBlank(getString(opportunity, 'closeDate'))) {
                oppLine += '（預計結案：' + getString(opportunity, 'closeDate') + '）';
            }
            legacyItems.add(oppLine);
        }
        if (legacyItems.isEmpty() && !hasOverview) {
            html += '<p>目前無明確資料</p>';
        } else if (!legacyItems.isEmpty()) {
            html += '<ul>';
            for (String item : legacyItems) {
                html += '<li>' +
                    escape(item) +
                    '</li>';
            }
            html += '</ul>';
        }

        html += '<h2>關鍵風險與待確認</h2>';
        List<String> riskLines = new List<String>();
        if (!String.isBlank(getString(lead, 'description'))) {
            riskLines.add(getString(lead, 'description'));
        }
        String summaryBody = getString(interaction, 'summaryBody');
        if (!String.isBlank(summaryBody)) {
            riskLines.add('此筆分析來自舊版會議 JSON，若要更精準顯示 QBR 風險與待確認，請改用新版 QBR JSON schema。');
        }
        if (riskLines.isEmpty()) {
            html += '<p>目前無明確資料</p>';
        } else {
            html += '<ul>';
            for (String line : riskLines) {
                html += '<li><p>' +
                    escape(line) +
                    '</p></li>';
            }
            html += '</ul>';
        }

        html += '<h2>會後行動清單</h2>';
        html = appendActions(html, tasks, true);

        return html;
    }

    private static String appendActions(String html, List<Object> actions, Boolean legacyMode) {
        if (actions.isEmpty()) {
            return html + '<p>目前無明確資料</p>';
        }

        Set<String> seen = new Set<String>();
        html += '<ul>';
        for (Object item : actions) {
            Map<String, Object> action = asMap(item);
            String actionText = legacyMode
                ? valueOrFallback(getString(action, 'subject'), '待確認')
                : valueOrFallback(getString(action, 'action'), '待確認');
            String owner = legacyMode
                ? normalizeOwner(valueOrFallback(getString(action, 'OwnerName'), '待確認'))
                : normalizeOwner(valueOrFallback(getString(action, 'owner'), '待確認'));
            String timeframe = legacyMode
                ? translateTimeframe(valueOrFallback(getString(action, 'DueDate'), '待確認'))
                : translateTimeframe(valueOrFallback(getString(action, 'timeframe'), '待確認'));
            String status = legacyMode
                ? '待開始'
                : translateActionStatus(valueOrFallback(getString(action, 'status'), '待開始'));

            String key = actionText + '|' + owner + '|' + timeframe + '|' + status;
            if (seen.contains(key)) {
                continue;
            }
            seen.add(key);

            html += '<li>';
            html += '<p><strong>' +
                escape(actionText) +
                '</strong></p>';
            html += '<p><strong>負責人：</strong>' +
                escape(owner) +
                ' ｜ <strong>時程：</strong>' +
                escape(timeframe) +
                ' ｜ <strong>狀態：</strong>' +
                escape(status) +
                '</p>';
            html += '</li>';
        }
        html += '</ul>';
        return html;
    }

    private static String sanitizeJson(String rawJson) {
        if (String.isBlank(rawJson)) {
            return rawJson;
        }
        String cleaned = rawJson
            .replace('```json', '')
            .replace('```', '')
            .replace('\u00A0', ' ')
            .replace('\uFEFF', ' ')
            .trim();
        Integer start = cleaned.indexOf('{');
        Integer endIdx = cleaned.lastIndexOf('}');
        if (start >= 0 && endIdx >= start) {
            cleaned = cleaned.substring(start, endIdx + 1);
        }
        return cleaned;
    }

    private static String repairJsonText(String jsonText) {
        if (String.isBlank(jsonText)) {
            return jsonText;
        }

        String repaired = jsonText
            .replace('“', '"')
            .replace('”', '"')
            .replace('„', '"')
            .replace('‟', '"')
            .replace('’', '\'')
            .replace('‘', '\'')
            .replace('‚', '\'')
            .replace('‛', '\'')
            .trim();

        Integer firstBrace = repaired.indexOf('{');
        if (firstBrace > 0) {
            repaired = repaired.substring(firstBrace);
        }

        Integer lastBrace = repaired.lastIndexOf('}');
        Integer lastBracket = repaired.lastIndexOf(']');
        Integer clipIndex = Math.max(lastBrace, lastBracket);
        if (clipIndex > -1 && clipIndex < repaired.length() - 1) {
            repaired = repaired.substring(0, clipIndex + 1);
        }

        while (repaired.contains(',}')) {
            repaired = repaired.replace(',}', '}');
        }
        while (repaired.contains(',]')) {
            repaired = repaired.replace(',]', ']');
        }

        Integer openBraces = countChar(repaired, '{');
        Integer closeBraces = countChar(repaired, '}');
        while (closeBraces < openBraces) {
            repaired += '}';
            closeBraces++;
        }

        Integer openBrackets = countChar(repaired, '[');
        Integer closeBrackets = countChar(repaired, ']');
        while (closeBrackets < openBrackets) {
            repaired += ']';
            closeBrackets++;
        }

        return repaired;
    }

    private static Map<String, Object> tryParseMap(String jsonText) {
        if (String.isBlank(jsonText)) {
            return new Map<String, Object>();
        }
        try {
            Object parsed = JSON.deserializeUntyped(jsonText);
            return asMap(parsed);
        } catch (Exception ex) {
            return new Map<String, Object>();
        }
    }

    private static Integer countChar(String source, String needle) {
        if (String.isBlank(source) || String.isBlank(needle)) {
            return 0;
        }
        Integer count = 0;
        for (Integer index = 0; index < source.length(); index++) {
            if (source.substring(index, index + 1) == needle) {
                count++;
            }
        }
        return count;
    }

    private static Map<String, Object> asMap(Object value) {
        try {
            return (Map<String, Object>) value;
        } catch (Exception ex) {
            return new Map<String, Object>();
        }
    }

    private static List<Object> asList(Object value) {
        try {
            return (List<Object>) value;
        } catch (Exception ex) {
            return new List<Object>();
        }
    }

    private static String getString(Map<String, Object> valueMap, String key) {
        if (valueMap == null || !valueMap.containsKey(key) || valueMap.get(key) == null) {
            return null;
        }
        return String.valueOf(valueMap.get(key)).trim();
    }

    private static String valueOrFallback(String value, String fallback) {
        return String.isBlank(value) ? fallback : value;
    }

    private static String translateStatus(String status) {
        Map<String, String> labels = new Map<String, String>{
            'Confirmed' => '已確認',
            'In Principle' => '原則同意',
            'Pending Approval' => '待核准',
            'Pending Review' => '待審查',
            'In Progress' => '進行中',
            'Not Started' => '待開始'
        };
        return labels.containsKey(status) ? labels.get(status) : status;
    }

    private static String translateActionStatus(String status) {
        String normalized = translateStatus(status);
        if (normalized == 'Confirmed') {
            return '已確認';
        }
        return normalized;
    }

    private static String translateTimeframe(String timeframe) {
        Map<String, String> labels = new Map<String, String>{
            'ASAP' => '儘速',
            'NEXT_WEEK' => '下週',
            'PLUS_7_DAYS' => '7 天內',
            'END_OF_MONTH' => '月底前'
        };
        return labels.containsKey(timeframe) ? labels.get(timeframe) : timeframe;
    }

    private static String normalizeOwner(String owner) {
        if (String.isBlank(owner)) {
            return '待確認';
        }
        String normalized = owner.trim().replaceAll('\\s+', ' ');
        normalized = normalized.replace('WNC WNC ', 'WNC ');
        normalized = normalized.replace('Qualcomm Qualcomm ', 'Qualcomm ');
        return normalized;
    }

    private static String escape(String value) {
        return value == null ? '' : value.escapeHtml4();
    }

    private static String emptyStateHtml() {
        return '<h2>會議決議總覽</h2><p>目前無明確資料</p>' +
            '<h2>關鍵風險與待確認</h2><p>目前無明確資料</p>' +
            '<h2>會後行動清單</h2><p>目前無明確資料</p>';
    }

    public class Request {
        @InvocableVariable(required=true)
        public String jsonString;
    }

    public class Response {
        @InvocableVariable
        public String formattedHtml;
    }
}