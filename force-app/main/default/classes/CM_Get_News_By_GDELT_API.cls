public with sharing class CM_Get_News_By_GDELT_API {
    // --- GDELT Doc API 端點 ---
    private static final String GDELT_DOC_ENDPOINT = 'https://api.gdeltproject.org/api/v2/doc/doc';

    @InvocableMethod(
        label='Get Company Info and News'
        description='Fetches company profile and latest news using GDELT API'
    )
    public static List<Output> getCompanyInfoAction(List<Input> inputParams) {
        List<Output> outputList = new List<Output>();
        for (Input input : inputParams) {
            Output output = new Output();
            try {
                output.companyInfo = getCompanyInfo(input.companyName);
            } catch (Exception e) {
                output.companyInfo = 'Error: ' + e.getMessage();
            }
            outputList.add(output);
        }
        return outputList;
    }

    public static String getCompanyInfo(String companyName) {
        if (String.isEmpty(companyName)) {
            return 'Error: Company name is required';
        }
        String responseText = gdeltSearch(companyName);
        System.debug('Raw GDELT response: ' + responseText);
        return responseText;
    }

    private static String gdeltSearch(String query) {
        if (String.isEmpty(query)) {
            return 'Error: Query is required';
        }
        String timespan = '7d';
        String endpoint = GDELT_DOC_ENDPOINT
            + '?query=' + EncodingUtil.urlEncode(query, 'UTF-8')
            + '&mode=ArtList'
            + '&format=json'
            + '&maxrecords=20'
            + '&timespan=' + timespan;
        HttpRequest req = new HttpRequest();
        req.setHeader('Content-Type', 'application/json');
        req.setEndpoint(endpoint);
        req.setMethod('GET');

        try {
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() == 200) {
                return processGdeltResults(res.getBody(), query);
            } else {
                return 'Error: HTTP ' + res.getStatus();
            }
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }

    private static String processGdeltResults(String responseBody, String companyName) {
        try {
            // 動態解析 JSON
            Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            List<Object> items = (List<Object>) jsonMap.get('articles');
            if (items == null) {
                items = (List<Object>) jsonMap.get('artlist');
            }
            if (items == null) {
                return 'Unexpected JSON structure: ' + responseBody;
            }

            // 使用 String 串接字串
            String sb = 'Company Profile and Latest News for: ' + companyName + '\n\n';
            sb += 'Latest News:\n';

            Integer count = 0;
            for (Object obj : items) {
                if (count >= 5) break;
                Map<String, Object> art = (Map<String, Object>) obj;
                String lang = art.containsKey('language') ? String.valueOf(art.get('language')).toLowerCase() : '';
                if (!(lang == 'english' || lang == 'chinese')) {
                    continue;
                }
                sb += 'Title: ' + art.get('title') + '\n';
                sb += 'URL: ' + art.get('url') + '\n';
                sb += 'Date: ' + art.get('seendate') + '\n\n';
                count++;
            }
            if (count == 0) {
                return 'No results found in English or Chinese';
            }
            return sb;
        } catch (Exception e) {
            // 無法解析 JSON，回傳原始內容供除錯
            return 'JSON parse error, raw response: ' + responseBody;
        }
    }

    // --- 資料模型 ---
    public class Input {
        @InvocableVariable(required=true description='The company name to search for.')
        public String companyName;
    }

    public class Output {
        @InvocableVariable(description='A string formatted as text that includes company profile and latest news.')
        public String companyInfo;
    }
}
