public with sharing class CMNewsSetupController {
    private static final Integer SEARCH_LIMIT = 20;
    private static final String PROVIDER_GDELT = 'GDELT';
    private static final String PROVIDER_NEWS_API = 'NEWS_API';
    private static final String PROVIDER_GNEWS_API = 'GNEWS_API';
    private static final String PROVIDER_GOOGLE_NEWS_RSS = 'GOOGLE_NEWS_RSS';

    @TestVisible
    static String testNewsPayload;

    @AuraEnabled
    public static List<AccountOption> searchAccounts(String searchTerm) {
        String normalized = searchTerm == null ? '' : searchTerm.trim();
        List<Account> accounts;

        if (String.isBlank(normalized)) {
            accounts = [
                SELECT Id, Name, Industry, Website, Account_News__c, Account_News_Query__c, Related_News__c, Related_News_Query__c, CM_LatestUpdate__c, LastModifiedDate
                FROM Account
                ORDER BY LastModifiedDate DESC
                LIMIT :SEARCH_LIMIT
            ];
        } else {
            String likeTerm = '%' + normalized + '%';
            accounts = [
                SELECT Id, Name, Industry, Website, Account_News__c, Account_News_Query__c, Related_News__c, Related_News_Query__c, CM_LatestUpdate__c, LastModifiedDate
                FROM Account
                WHERE Name LIKE :likeTerm
                ORDER BY Name
                LIMIT :SEARCH_LIMIT
            ];
        }

        List<AccountOption> results = new List<AccountOption>();
        for (Account accountRecord : accounts) {
            AccountOption option = new AccountOption();
            option.id = accountRecord.Id;
            option.name = accountRecord.Name;
            option.industry = accountRecord.Industry;
            option.website = accountRecord.Website;
            option.hasNews = !String.isBlank(accountRecord.Account_News__c);
            option.accountNewsQuery = accountRecord.Account_News_Query__c;
            option.hasRelatedNews = !String.isBlank(accountRecord.Related_News__c);
            option.relatedNewsQuery = accountRecord.Related_News_Query__c;
            option.latestUpdate = accountRecord.CM_LatestUpdate__c;
            option.lastModifiedDate = accountRecord.LastModifiedDate;
            results.add(option);
        }
        return results;
    }

    @AuraEnabled
    public static List<QueryConfigSavedItem> saveQueryConfigs(String configsJson) {
        return saveQueryConfigsInternal(parseQueryConfigs(configsJson));
    }

    public static List<QueryConfigSavedItem> saveQueryConfigs(List<QueryConfigInput> configs) {
        return saveQueryConfigsInternal(configs);
    }

    private static List<QueryConfigInput> parseQueryConfigs(String configsJson) {
        List<QueryConfigInput> configs = new List<QueryConfigInput>();
        if (String.isBlank(configsJson)) {
            return configs;
        }

        Object payload = JSON.deserializeUntyped(configsJson);
        if (!(payload instanceof List<Object>)) {
            throw new AuraHandledException('Save failed: payload format is invalid.');
        }

        for (Object entry : (List<Object>)payload) {
            if (!(entry instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> raw = (Map<String, Object>)entry;
            QueryConfigInput item = new QueryConfigInput();
            item.accountId = toStringOrNull(raw.get('accountId'));
            item.accountNewsQuery = toStringOrNull(raw.get('accountNewsQuery'));
            item.relatedNewsQuery = toStringOrNull(raw.get('relatedNewsQuery'));
            configs.add(item);
        }
        return configs;
    }

    private static List<QueryConfigSavedItem> saveQueryConfigsInternal(List<QueryConfigInput> configs) {
        if (configs == null || configs.isEmpty()) {
            return new List<QueryConfigSavedItem>();
        }
        List<Account> updates = new List<Account>();
        Set<Id> accountIds = new Set<Id>();
        Integer missingIdCount = 0;
        for (QueryConfigInput item : configs) {
            if (item == null) {
                continue;
            }
            if (String.isBlank(item.accountId)) {
                missingIdCount++;
                continue;
            }
            Id parsedId;
            try {
                parsedId = (Id)item.accountId;
            } catch (Exception ex) {
                throw new AuraHandledException('Save failed: invalid accountId in payload. Value=' + item.accountId);
            }
            accountIds.add(parsedId);
            updates.add(new Account(
                Id = parsedId,
                Account_News_Query__c = trimToNull(item.accountNewsQuery),
                Related_News_Query__c = trimToNull(item.relatedNewsQuery)
            ));
        }
        if (missingIdCount > 0) {
            throw new AuraHandledException('Save failed: accountId is missing in payload. Count=' + missingIdCount);
        }
        if (!updates.isEmpty()) {
            update updates;
        }

        if (accountIds.isEmpty()) {
            return new List<QueryConfigSavedItem>();
        }

        Map<Id, Account> savedById = new Map<Id, Account>([
            SELECT Id, Account_News_Query__c, Related_News_Query__c, Account_News__c, Related_News__c, CM_LatestUpdate__c, LastModifiedDate
            FROM Account
            WHERE Id IN :accountIds
        ]);

        List<QueryConfigSavedItem> results = new List<QueryConfigSavedItem>();
        for (Id accountId : accountIds) {
            Account saved = savedById.get(accountId);
            if (saved == null) {
                continue;
            }
            QueryConfigSavedItem item = new QueryConfigSavedItem();
            item.accountId = saved.Id;
            item.accountNewsQuery = saved.Account_News_Query__c;
            item.relatedNewsQuery = saved.Related_News_Query__c;
            item.hasNews = !String.isBlank(saved.Account_News__c);
            item.hasRelatedNews = !String.isBlank(saved.Related_News__c);
            item.latestUpdate = saved.CM_LatestUpdate__c;
            item.lastModifiedDate = saved.LastModifiedDate;
            results.add(item);
        }
        return results;
    }

    @AuraEnabled
    public static NewsGenerationResult generateNews(List<Id> accountIds, String apiProvider, String apiAuth, String language) {
        if (accountIds == null || accountIds.isEmpty()) {
            throw new AuraHandledException('Please select at least one Account.');
        }
        String normalizedProvider = normalizeApiProvider(apiProvider);
        String normalizedAuth = apiAuth == null ? null : apiAuth.trim();
        String normalizedLanguage = String.isBlank(language) ? 'ANY' : language.trim().toUpperCase();
        if (requiresApiAuth(normalizedProvider) && String.isBlank(normalizedAuth)) {
            throw new AuraHandledException('Auth is required when provider is NEWS API or GNews API.');
        }

        List<Account> selectedAccounts = [
            SELECT Id, Name, Account_News_Query__c, Related_News_Query__c
            FROM Account
            WHERE Id IN :accountIds
        ];

        Map<Id, Account> accountById = new Map<Id, Account>(selectedAccounts);
        List<Account> updates = new List<Account>();
        List<NewsGenerationItem> items = new List<NewsGenerationItem>();
        Integer accountNewsSuccessCount = 0;
        Integer relatedNewsSuccessCount = 0;

        for (Id accountId : accountIds) {
            Account accountRecord = accountById.get(accountId);
            if (accountRecord == null) {
                continue;
            }
            Account updateRecord = new Account(Id = accountRecord.Id);

            String accountNewsQuery = trimToNull(accountRecord.Account_News_Query__c);
            if (String.isBlank(accountNewsQuery)) {
                accountNewsQuery = accountRecord.Name;
            }
            String relatedNewsQuery = trimToNull(accountRecord.Related_News_Query__c);
            String accountPayload = fetchNewsPayload(accountNewsQuery, normalizedLanguage, normalizedProvider, normalizedAuth);
            updateRecord.Account_News__c = accountPayload;
            accountNewsSuccessCount++;

            Boolean hasRelatedNewsQuery = !String.isBlank(relatedNewsQuery);
            if (hasRelatedNewsQuery) {
                String relatedPayload = fetchNewsPayload(relatedNewsQuery, normalizedLanguage, normalizedProvider, normalizedAuth);
                updateRecord.Related_News__c = relatedPayload;
                relatedNewsSuccessCount++;
            }

            updateRecord.CM_LatestUpdate__c = buildLatestUpdateText(
                accountNewsQuery,
                relatedNewsQuery,
                normalizedProvider,
                normalizedLanguage,
                hasRelatedNewsQuery
            );
            updates.add(updateRecord);

            NewsGenerationItem item = new NewsGenerationItem();
            item.accountId = accountRecord.Id;
            item.accountName = accountRecord.Name;
            item.accountNewsQuery = accountNewsQuery;
            item.relatedNewsQuery = relatedNewsQuery;
            item.success = true;
            item.message = 'Prepared';
            items.add(item);
        }

        Database.SaveResult[] saveResults = Database.update(updates, false);
        Integer successCount = 0;
        Integer failureCount = 0;

        for (Integer i = 0; i < saveResults.size(); i++) {
            if (saveResults[i].isSuccess()) {
                successCount++;
                items[i].message = 'Updated';
            } else {
                failureCount++;
                items[i].success = false;
                items[i].message = saveResults[i].getErrors()[0].getMessage();
            }
        }

        NewsGenerationResult result = new NewsGenerationResult();
        result.successCount = successCount;
        result.failureCount = failureCount;
        result.accountNewsSuccessCount = accountNewsSuccessCount;
        result.relatedNewsSuccessCount = relatedNewsSuccessCount;
        result.items = items;
        return result;
    }

    @AuraEnabled
    public static QueryTestResult testNewsQuery(
        String queryString,
        String language,
        String apiProvider,
        String apiAuth
    ) {
        String normalized = queryString == null ? '' : queryString.trim();
        if (String.isBlank(normalized)) {
            throw new AuraHandledException('Query string is required.');
        }
        String normalizedProvider = normalizeApiProvider(apiProvider);
        String normalizedAuth = apiAuth == null ? null : apiAuth.trim();
        if (requiresApiAuth(normalizedProvider) && String.isBlank(normalizedAuth)) {
            throw new AuraHandledException('Auth is required when provider is NEWS API or GNews API.');
        }

        String payload = fetchNewsPayload(normalized, language, normalizedProvider, normalizedAuth);
        QueryTestResult result = new QueryTestResult();
        result.query = normalized;
        result.language = String.isBlank(language) ? 'ANY' : language.trim().toUpperCase();
        result.apiProvider = normalizedProvider;
        result.rawPayload = payload;
        result.entries = parseEntries(payload);
        result.entryCount = result.entries.size();
        return result;
    }

    private static String fetchNewsPayload(String query) {
        if (Test.isRunningTest() && testNewsPayload != null) {
            return testNewsPayload;
        }
        return CM_Get_News_BY_API.getCompanyInfo(query);
    }

    private static String fetchNewsPayload(String query, String language) {
        if (Test.isRunningTest() && testNewsPayload != null) {
            return testNewsPayload;
        }
        return CM_Get_News_BY_API.getCompanyInfoByLanguage(query, language);
    }

    private static String fetchNewsPayload(String query, String language, String apiProvider, String apiAuth) {
        if (Test.isRunningTest() && testNewsPayload != null) {
            return testNewsPayload;
        }
        return CM_Get_News_BY_API.getCompanyInfoByApi(query, language, apiProvider, apiAuth);
    }

    private static String normalizeApiProvider(String apiProvider) {
        String normalized = String.isBlank(apiProvider) ? PROVIDER_GOOGLE_NEWS_RSS : apiProvider.trim().toUpperCase();
        if (normalized == PROVIDER_NEWS_API) {
            return PROVIDER_NEWS_API;
        }
        if (normalized == PROVIDER_GNEWS_API) {
            return PROVIDER_GNEWS_API;
        }
        if (normalized == PROVIDER_GOOGLE_NEWS_RSS) {
            return PROVIDER_GOOGLE_NEWS_RSS;
        }
        return PROVIDER_GDELT;
    }

    private static Boolean requiresApiAuth(String apiProvider) {
        return apiProvider == PROVIDER_NEWS_API || apiProvider == PROVIDER_GNEWS_API;
    }

    private static String buildLatestUpdateText(
        String accountNewsQuery,
        String relatedNewsQuery,
        String apiProvider,
        String language,
        Boolean includeRelatedQuery
    ) {
        List<String> segments = new List<String>();
        segments.add('Updated At (UTC): ' + Datetime.now().formatGmt('yyyy-MM-dd HH:mm:ss'));
        segments.add('Provider: ' + apiProvider);
        segments.add('Language: ' + (String.isBlank(language) ? 'ANY' : language));
        segments.add('Account Query: ' + (String.isBlank(accountNewsQuery) ? '' : accountNewsQuery));
        if (includeRelatedQuery && !String.isBlank(relatedNewsQuery)) {
            segments.add('Related Query: ' + relatedNewsQuery);
        }
        return String.join(segments, ' | ');
    }

    private static String trimToNull(String value) {
        String trimmed = value == null ? null : value.trim();
        return String.isBlank(trimmed) ? null : trimmed;
    }

    private static String toStringOrNull(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static List<NewsEntry> parseEntries(String payload) {
        List<NewsEntry> entries = new List<NewsEntry>();
        if (String.isBlank(payload)) {
            return entries;
        }

        String[] lines = payload.split('\\n');
        NewsEntry current = null;

        for (String rawLine : lines) {
            String line = rawLine == null ? '' : rawLine.trim();
            if (line.startsWith('Title:')) {
                if (current != null && !String.isBlank(current.title)) {
                    entries.add(current);
                }
                current = new NewsEntry();
                current.title = line.substringAfter('Title:').trim();
            } else if (line.startsWith('URL:')) {
                if (current == null) {
                    current = new NewsEntry();
                }
                current.url = line.substringAfter('URL:').trim();
            } else if (line.startsWith('Date:')) {
                if (current == null) {
                    current = new NewsEntry();
                }
                current.publishedDate = line.substringAfter('Date:').trim();
            }
        }

        if (current != null && !String.isBlank(current.title)) {
            entries.add(current);
        }

        return entries;
    }

    public class AccountOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String industry;
        @AuraEnabled public String website;
        @AuraEnabled public Boolean hasNews;
        @AuraEnabled public String accountNewsQuery;
        @AuraEnabled public Boolean hasRelatedNews;
        @AuraEnabled public String relatedNewsQuery;
        @AuraEnabled public String latestUpdate;
        @AuraEnabled public Datetime lastModifiedDate;
    }

    public class NewsGenerationItem {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String accountNewsQuery;
        @AuraEnabled public String relatedNewsQuery;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
    }

    public class NewsGenerationResult {
        @AuraEnabled public Integer successCount;
        @AuraEnabled public Integer failureCount;
        @AuraEnabled public Integer accountNewsSuccessCount;
        @AuraEnabled public Integer relatedNewsSuccessCount;
        @AuraEnabled public List<NewsGenerationItem> items;
    }

    public class QueryConfigInput {
        @AuraEnabled public String accountId;
        @AuraEnabled public String accountNewsQuery;
        @AuraEnabled public String relatedNewsQuery;
    }

    public class QueryConfigSavedItem {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountNewsQuery;
        @AuraEnabled public String relatedNewsQuery;
        @AuraEnabled public Boolean hasNews;
        @AuraEnabled public Boolean hasRelatedNews;
        @AuraEnabled public String latestUpdate;
        @AuraEnabled public Datetime lastModifiedDate;
    }

    public class NewsEntry {
        @AuraEnabled public String title;
        @AuraEnabled public String url;
        @AuraEnabled public String publishedDate;
    }

    public class QueryTestResult {
        @AuraEnabled public String query;
        @AuraEnabled public String language;
        @AuraEnabled public String apiProvider;
        @AuraEnabled public String rawPayload;
        @AuraEnabled public Integer entryCount;
        @AuraEnabled public List<NewsEntry> entries;
    }
}
