public with sharing class CM_Get_News_BY_API {
    private static final String GDELT_DOC_ENDPOINT = 'https://api.gdeltproject.org/api/v2/doc/doc';
    private static final String NEWS_API_ENDPOINT = 'https://newsapi.org/v2/everything';
    private static final String GNEWS_API_ENDPOINT = 'https://gnews.io/api/v4/search';
    private static final String GOOGLE_NEWS_RSS_ENDPOINT = 'https://news.google.com/rss/search';

    private static final String PROVIDER_GDELT = 'GDELT';
    private static final String PROVIDER_NEWS_API = 'NEWS_API';
    private static final String PROVIDER_GNEWS_API = 'GNEWS_API';
    private static final String PROVIDER_GOOGLE_NEWS_RSS = 'GOOGLE_NEWS_RSS';

    @InvocableMethod(
        label='Get Company Info and News'
        description='Fetches company profile and latest news using configured API provider'
    )
    public static List<Output> getCompanyInfoAction(List<Input> inputParams) {
        List<Output> outputList = new List<Output>();
        for (Input input : inputParams) {
            Output output = new Output();
            try {
                output.companyInfo = getCompanyInfo(input.companyName);
            } catch (Exception e) {
                output.companyInfo = buildEmptyNewsPayload(input.companyName);
            }
            outputList.add(output);
        }
        return outputList;
    }

    public static String getCompanyInfo(String companyName) {
        return getCompanyInfoByApi(companyName, null, PROVIDER_GDELT, null);
    }

    public static String getCompanyInfoByLanguage(String companyName, String language) {
        return getCompanyInfoByApi(companyName, language, PROVIDER_GDELT, null);
    }

    public static String getCompanyInfoByApi(
        String companyName,
        String language,
        String apiProvider,
        String apiAuth
    ) {
        if (String.isBlank(companyName)) {
            return buildEmptyNewsPayload(companyName);
        }

        String normalizedProvider = normalizeApiProvider(apiProvider);
        String responseText;
        if (normalizedProvider == PROVIDER_NEWS_API) {
            responseText = newsApiSearch(companyName, language, apiAuth);
        } else if (normalizedProvider == PROVIDER_GNEWS_API) {
            responseText = gnewsApiSearch(companyName, language, apiAuth);
        } else if (normalizedProvider == PROVIDER_GOOGLE_NEWS_RSS) {
            responseText = googleNewsRssSearch(companyName, language);
        } else {
            responseText = gdeltSearch(companyName, language);
        }

        System.debug('News response [' + normalizedProvider + ']: ' + responseText);
        return responseText;
    }

    private static String gdeltSearch(String query, String language) {
        String endpoint = GDELT_DOC_ENDPOINT
            + '?query=' + EncodingUtil.urlEncode(query, 'UTF-8')
            + '&mode=ArtList'
            + '&format=json'
            + '&maxrecords=10'
            + '&timespan=7d';

        HttpRequest req = new HttpRequest();
        req.setHeader('Content-Type', 'application/json');
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(120000);

        try {
            Http http = new Http();
            HttpResponse res = http.send(req);
            if (res.getStatusCode() == 200) {
                return processGdeltResults(res.getBody(), query, language);
            }
            if (res.getStatusCode() == 429) {
                HttpResponse retryRes = http.send(req);
                if (retryRes.getStatusCode() == 200) {
                    return processGdeltResults(retryRes.getBody(), query, language);
                }
            }
            return buildEmptyNewsPayload(query);
        } catch (Exception e) {
            return buildEmptyNewsPayload(query);
        }
    }

    private static String newsApiSearch(String query, String language, String apiAuth) {
        if (String.isBlank(apiAuth)) {
            return buildEmptyNewsPayload(query);
        }

        String endpoint = NEWS_API_ENDPOINT
            + '?q=' + EncodingUtil.urlEncode(query, 'UTF-8')
            + '&pageSize=10&sortBy=publishedAt';

        String newsApiLanguage = toNewsApiLanguageCode(language);
        if (!String.isBlank(newsApiLanguage)) {
            endpoint += '&language=' + newsApiLanguage;
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('X-Api-Key', apiAuth.trim());
        req.setTimeout(120000);

        try {
            Http http = new Http();
            HttpResponse res = http.send(req);
            if (res.getStatusCode() == 200) {
                return processNewsApiResults(res.getBody(), query);
            }
            if (res.getStatusCode() == 429) {
                HttpResponse retryRes = http.send(req);
                if (retryRes.getStatusCode() == 200) {
                    return processNewsApiResults(retryRes.getBody(), query);
                }
            }
            return buildEmptyNewsPayload(query);
        } catch (Exception e) {
            return buildEmptyNewsPayload(query);
        }
    }

    private static String processGdeltResults(String responseBody, String companyName, String language) {
        try {
            Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            List<Object> items = (List<Object>) jsonMap.get('articles');
            if (items == null) {
                items = (List<Object>) jsonMap.get('artlist');
            }
            if (items == null) {
                return buildEmptyNewsPayload(companyName);
            }

            String sb = 'Company Profile and Latest News for: ' + companyName + '\n\n';
            sb += 'Latest News:\n';

            String languageKey = normalizeLanguageKey(language);
            Boolean allowFallback = languageKey == 'ANY';
            Integer count = 0;
            Integer fallbackCount = 0;
            String fallbackSb = '';

            for (Object obj : items) {
                if (count >= 5) {
                    break;
                }

                Map<String, Object> art = (Map<String, Object>) obj;
                String lang = art.containsKey('language') ? String.valueOf(art.get('language')).toLowerCase() : '';
                String title = art.get('title') == null ? '' : String.valueOf(art.get('title'));
                String url = art.get('url') == null ? '' : String.valueOf(art.get('url'));
                String seenDate = art.get('seendate') == null ? '' : String.valueOf(art.get('seendate'));

                if (String.isBlank(title) || String.isBlank(url)) {
                    continue;
                }

                Boolean preferredLanguage = matchesLanguage(lang, languageKey);
                if (preferredLanguage) {
                    sb += 'Title: ' + title + '\n';
                    sb += 'URL: ' + url + '\n';
                    sb += 'Date: ' + seenDate + '\n\n';
                    count++;
                } else if (allowFallback && fallbackCount < 5) {
                    fallbackSb += 'Title: ' + title + '\n';
                    fallbackSb += 'URL: ' + url + '\n';
                    fallbackSb += 'Date: ' + seenDate + '\n\n';
                    fallbackCount++;
                }
            }

            if (count == 0 && fallbackCount > 0) {
                sb += fallbackSb;
                count = fallbackCount;
            }
            return count == 0 ? buildEmptyNewsPayload(companyName) : sb;
        } catch (Exception e) {
            return buildEmptyNewsPayload(companyName);
        }
    }

    private static String processNewsApiResults(String responseBody, String companyName) {
        try {
            Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            List<Object> items = (List<Object>) jsonMap.get('articles');
            if (items == null || items.isEmpty()) {
                return buildEmptyNewsPayload(companyName);
            }

            String sb = 'Company Profile and Latest News for: ' + companyName + '\n\n';
            sb += 'Latest News:\n';

            Integer count = 0;
            for (Object obj : items) {
                if (count >= 5) {
                    break;
                }
                Map<String, Object> article = (Map<String, Object>) obj;
                String title = article.get('title') == null ? '' : String.valueOf(article.get('title'));
                String url = article.get('url') == null ? '' : String.valueOf(article.get('url'));
                String publishedAt = article.get('publishedAt') == null ? '' : String.valueOf(article.get('publishedAt'));

                if (String.isBlank(title) || String.isBlank(url)) {
                    continue;
                }

                sb += 'Title: ' + title + '\n';
                sb += 'URL: ' + url + '\n';
                sb += 'Date: ' + publishedAt + '\n\n';
                count++;
            }

            return count == 0 ? buildEmptyNewsPayload(companyName) : sb;
        } catch (Exception e) {
            return buildEmptyNewsPayload(companyName);
        }
    }

    private static String gnewsApiSearch(String query, String language, String apiAuth) {
        if (String.isBlank(apiAuth)) {
            return buildEmptyNewsPayload(query);
        }

        String endpoint = GNEWS_API_ENDPOINT
            + '?q=' + EncodingUtil.urlEncode(query, 'UTF-8')
            + '&max=10';

        String languageCode = toNewsApiLanguageCode(language);
        if (!String.isBlank(languageCode)) {
            endpoint += '&lang=' + languageCode;
        }
        endpoint += '&token=' + EncodingUtil.urlEncode(apiAuth.trim(), 'UTF-8');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(120000);

        try {
            Http http = new Http();
            HttpResponse res = http.send(req);
            if (res.getStatusCode() == 200) {
                return processNewsApiResults(res.getBody(), query);
            }
            if (res.getStatusCode() == 429) {
                HttpResponse retryRes = http.send(req);
                if (retryRes.getStatusCode() == 200) {
                    return processNewsApiResults(retryRes.getBody(), query);
                }
            }
            return buildEmptyNewsPayload(query);
        } catch (Exception e) {
            return buildEmptyNewsPayload(query);
        }
    }

    private static String googleNewsRssSearch(String query, String language) {
        String languageKey = normalizeLanguageKey(language);
        String hl = 'en-US';
        String gl = 'US';
        String ceid = 'US:en';

        if (languageKey == 'CHINESE') {
            hl = 'zh-TW';
            gl = 'TW';
            ceid = 'TW:zh-Hant';
        } else if (languageKey == 'JAPANESE') {
            hl = 'ja';
            gl = 'JP';
            ceid = 'JP:ja';
        }

        String endpoint = GOOGLE_NEWS_RSS_ENDPOINT
            + '?q=' + EncodingUtil.urlEncode(query, 'UTF-8')
            + '&hl=' + EncodingUtil.urlEncode(hl, 'UTF-8')
            + '&gl=' + EncodingUtil.urlEncode(gl, 'UTF-8')
            + '&ceid=' + EncodingUtil.urlEncode(ceid, 'UTF-8');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/xml');
        req.setTimeout(120000);

        try {
            Http http = new Http();
            HttpResponse res = http.send(req);
            if (res.getStatusCode() == 200) {
                return processGoogleNewsRssResults(res.getBody(), query);
            }
            if (res.getStatusCode() == 429) {
                HttpResponse retryRes = http.send(req);
                if (retryRes.getStatusCode() == 200) {
                    return processGoogleNewsRssResults(retryRes.getBody(), query);
                }
            }
            return buildEmptyNewsPayload(query);
        } catch (Exception e) {
            return buildEmptyNewsPayload(query);
        }
    }

    private static String processGoogleNewsRssResults(String responseBody, String companyName) {
        try {
            Dom.Document document = new Dom.Document();
            document.load(responseBody);

            Dom.XmlNode root = document.getRootElement();
            if (root == null) {
                return buildEmptyNewsPayload(companyName);
            }

            Dom.XmlNode channel = root.getChildElement('channel', null);
            if (channel == null) {
                return buildEmptyNewsPayload(companyName);
            }

            List<Dom.XmlNode> items = channel.getChildElements();
            if (items == null || items.isEmpty()) {
                return buildEmptyNewsPayload(companyName);
            }

            String sb = 'Company Profile and Latest News for: ' + companyName + '\n\n';
            sb += 'Latest News:\n';

            Integer count = 0;
            for (Dom.XmlNode child : items) {
                if (count >= 5) {
                    break;
                }
                if (child == null || child.getName() != 'item') {
                    continue;
                }

                String title = '';
                String link = '';
                String pubDate = '';
                for (Dom.XmlNode node : child.getChildElements()) {
                    if (node == null) {
                        continue;
                    }
                    String nodeName = node.getName();
                    if (nodeName == 'title') {
                        title = node.getText();
                    } else if (nodeName == 'link') {
                        link = node.getText();
                    } else if (nodeName == 'pubDate') {
                        pubDate = node.getText();
                    }
                }

                if (String.isBlank(title) || String.isBlank(link)) {
                    continue;
                }
                sb += 'Title: ' + title + '\n';
                sb += 'URL: ' + link + '\n';
                sb += 'Date: ' + pubDate + '\n\n';
                count++;
            }

            return count == 0 ? buildEmptyNewsPayload(companyName) : sb;
        } catch (Exception e) {
            return buildEmptyNewsPayload(companyName);
        }
    }

    private static String buildEmptyNewsPayload(String companyName) {
        String safeName = String.isBlank(companyName) ? 'this company' : companyName;
        return 'Company Profile and Latest News for: ' + safeName + '\n\nLatest News:\n';
    }

    private static String normalizeApiProvider(String apiProvider) {
        String provider = String.isBlank(apiProvider) ? PROVIDER_GDELT : apiProvider.trim().toUpperCase();
        if (provider == PROVIDER_NEWS_API) {
            return PROVIDER_NEWS_API;
        }
        if (provider == PROVIDER_GNEWS_API) {
            return PROVIDER_GNEWS_API;
        }
        if (provider == PROVIDER_GOOGLE_NEWS_RSS) {
            return PROVIDER_GOOGLE_NEWS_RSS;
        }
        return PROVIDER_GDELT;
    }

    private static String normalizeLanguageKey(String language) {
        String normalized = String.isBlank(language) ? 'ANY' : language.trim().toUpperCase();
        if (normalized == 'EN' || normalized == 'ENG') {
            return 'ENGLISH';
        }
        if (normalized == 'ZH' || normalized == 'ZHO' || normalized == 'CMN') {
            return 'CHINESE';
        }
        if (normalized == 'JA' || normalized == 'JPN') {
            return 'JAPANESE';
        }
        if (normalized != 'ENGLISH' && normalized != 'CHINESE' && normalized != 'JAPANESE') {
            return 'ANY';
        }
        return normalized;
    }

    private static String toNewsApiLanguageCode(String language) {
        String key = normalizeLanguageKey(language);
        if (key == 'ENGLISH') {
            return 'en';
        }
        if (key == 'CHINESE') {
            return 'zh';
        }
        if (key == 'JAPANESE') {
            return 'ja';
        }
        return null;
    }

    private static Boolean matchesLanguage(String rawLanguage, String languageKey) {
        if (languageKey == 'ANY') {
            return true;
        }
        if (String.isBlank(rawLanguage)) {
            return false;
        }

        String lang = rawLanguage.toLowerCase();
        if (languageKey == 'ENGLISH') {
            return lang == 'english' || lang == 'en' || lang == 'eng';
        }
        if (languageKey == 'CHINESE') {
            return lang == 'chinese' || lang == 'zh' || lang == 'zho' || lang == 'cmn';
        }
        if (languageKey == 'JAPANESE') {
            return lang == 'japanese' || lang == 'ja' || lang == 'jpn';
        }
        return true;
    }

    public class Input {
        @InvocableVariable(required=true description='The company name to search for.')
        public String companyName;
    }

    public class Output {
        @InvocableVariable(description='A string formatted as text that includes company profile and latest news.')
        public String companyInfo;
    }
}
