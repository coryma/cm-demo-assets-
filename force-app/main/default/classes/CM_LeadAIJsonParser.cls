public class CM_LeadAIJsonParser {
    @InvocableMethod(label='Parse Lead AI JSON')
    public static List<Results> parseJson(List<String> jsonInput) {
        List<Results> output = new List<Results>();
        for (String s : jsonInput) {
            Results r = new Results();
            try {
                // Step 1: 清理掉 BOM/nbsp/開頭非 '{' 字元
                if (String.isBlank(s)) continue;
                String cleaned = s.trim().replace('\u00A0', '');
                Integer firstBrace = cleaned.indexOf('{');
                if (firstBrace >= 0) {
                    cleaned = cleaned.substring(firstBrace);
                }
                // Step 2: parse JSON
                Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(cleaned);

                r.classification = (String)m.get('classification');
                r.score = ((Decimal)m.get('score')).intValue();
                r.reason = (String)m.get('reason');
                // key_topics 轉為逗號分隔
                if (m.containsKey('key_topics')) {
                    List<Object> keys = (List<Object>)m.get('key_topics');
                    List<String> keyStrs = new List<String>();
                    for (Object o : keys) keyStrs.add(String.valueOf(o));
                    r.key_topics = String.join(keyStrs, ', ');
                }
                r.reply_recommendation = (String)m.get('reply_recommendation');
            } catch (Exception ex) {
                // 可記錄 error 訊息到 Flow 或加在某個欄位協助 debug
                r.reason = 'JSON Parse Error: ' + ex.getMessage();
                r.classification = 'Error';
                r.score = 0;
                r.key_topics = '';
                r.reply_recommendation = '';
            }
            output.add(r);
        }
        return output;
    }
    public class Results {
        @InvocableVariable public String classification;
        @InvocableVariable public Integer score;
        @InvocableVariable public String reason;
        @InvocableVariable public String key_topics;
        @InvocableVariable public String reply_recommendation;
    }
}