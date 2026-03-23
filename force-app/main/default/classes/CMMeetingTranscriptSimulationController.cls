public with sharing class CMMeetingTranscriptSimulationController {
    private static final Integer DEFAULT_SEARCH_LIMIT = 50;
    private static final Integer MAX_SEARCH_LIMIT = 100;
    private static final Integer MAX_ACCOUNTS_PER_RUN = 30;
    private static final Integer DEFAULT_DURATION_MINUTES = 45;
    private static final String PROMPT_TEMPLATE_NAME = 'CM_Meeting_Transcript_Simulation_Gen';

    private static final List<String> WNC_SPEAKERS = new List<String>{
        'WNC 供應鏈經理',
        'WNC 採購主管',
        'WNC 產品經理',
        'WNC 品質主管'
    };

    @TestVisible
    static String testPromptResponse;

    public class FocusContextPayload {
        @AuraEnabled public Id focusCompanyId;
        @AuraEnabled public String focusCompanyName;
        @AuraEnabled public Boolean hasFocusCompany;
    }

    public class AccountRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Boolean hasMeetingRecord;
    }

    public class StartSimulationResult {
        @AuraEnabled public String batchId;
        @AuraEnabled public Integer createdCount;
        @AuraEnabled public String message;
    }

    public class TranscriptRow {
        @AuraEnabled public Id transcriptId;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String status;
        @AuraEnabled public String summary;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public Datetime generatedAt;
        @AuraEnabled public String recordUrl;
    }

    public class BatchStatusPayload {
        @AuraEnabled public String batchId;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Integer queuedCount;
        @AuraEnabled public Integer processingCount;
        @AuraEnabled public Integer completedCount;
        @AuraEnabled public Integer failedCount;
        @AuraEnabled public Boolean done;
        @AuraEnabled public List<TranscriptRow> rows;
    }

    private class TranscriptPackage {
        public String summary;
        public String transcript;
        public String actionItems;
        public String promptResponse;
    }

    @AuraEnabled(cacheable=true)
    public static FocusContextPayload getFocusContext() {
        FocusContextPayload payload = new FocusContextPayload();
        Account focusCompany = getActiveDemoTargetAccount(false);
        payload.focusCompanyId = focusCompany == null ? null : focusCompany.Id;
        payload.focusCompanyName = focusCompany == null ? null : focusCompany.Name;
        payload.hasFocusCompany = focusCompany != null;
        return payload;
    }

    @AuraEnabled(cacheable=true)
    public static List<AccountRow> searchAccounts(String searchTerm, Integer limitSize) {
        Integer safeLimit = limitSize == null ? DEFAULT_SEARCH_LIMIT : limitSize;
        if (safeLimit < 1) {
            safeLimit = DEFAULT_SEARCH_LIMIT;
        }
        if (safeLimit > MAX_SEARCH_LIMIT) {
            safeLimit = MAX_SEARCH_LIMIT;
        }

        String normalizedSearchTerm = normalizeText(searchTerm);
        String likeTerm = '%' + normalizedSearchTerm + '%';

        Account focusCompany = getActiveDemoTargetAccount(false);
        Id focusCompanyId = focusCompany == null ? null : focusCompany.Id;

        List<Account> rows;
        if (String.isBlank(normalizedSearchTerm)) {
            rows = focusCompanyId == null
                ? [
                    SELECT Id, Name
                    FROM Account
                    ORDER BY LastModifiedDate DESC
                    LIMIT :safeLimit
                ]
                : [
                    SELECT Id, Name
                    FROM Account
                    WHERE Id != :focusCompanyId
                    ORDER BY LastModifiedDate DESC
                    LIMIT :safeLimit
                ];
        } else {
            rows = focusCompanyId == null
                ? [
                    SELECT Id, Name
                    FROM Account
                    WHERE Name LIKE :likeTerm
                    ORDER BY Name
                    LIMIT :safeLimit
                ]
                : [
                    SELECT Id, Name
                    FROM Account
                    WHERE Name LIKE :likeTerm
                      AND Id != :focusCompanyId
                    ORDER BY Name
                    LIMIT :safeLimit
                ];
        }

        Set<Id> accountIds = new Set<Id>();
        for (Account accountRow : rows) {
            accountIds.add(accountRow.Id);
        }

        Set<Id> accountsWithRecords = new Set<Id>();
        if (!accountIds.isEmpty() && focusCompanyId != null) {
            for (AggregateResult item : [
                SELECT Counterparty_Account__c accountId, COUNT(Id) totalCount
                FROM CM_Meeting_Transcript__c
                WHERE Focus_Company__c = :focusCompanyId
                  AND Counterparty_Account__c IN :accountIds
                GROUP BY Counterparty_Account__c
            ]) {
                accountsWithRecords.add((Id) item.get('accountId'));
            }
        }

        List<AccountRow> results = new List<AccountRow>();
        for (Account accountRow : rows) {
            AccountRow output = new AccountRow();
            output.id = accountRow.Id;
            output.name = accountRow.Name;
            output.hasMeetingRecord = accountsWithRecords.contains(accountRow.Id);
            results.add(output);
        }
        return results;
    }

    @AuraEnabled
    public static StartSimulationResult startSimulation(List<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            throw new AuraHandledException('Please select at least one Account.');
        }

        Set<Id> normalizedIds = new Set<Id>();
        for (Id accountId : accountIds) {
            if (accountId != null) {
                normalizedIds.add(accountId);
            }
        }

        if (normalizedIds.isEmpty()) {
            throw new AuraHandledException('Please select at least one Account.');
        }
        if (normalizedIds.size() > MAX_ACCOUNTS_PER_RUN) {
            throw new AuraHandledException('You can generate up to 30 Accounts per run.');
        }

        Account focusCompany = getActiveDemoTargetAccount(true);
        if (normalizedIds.contains(focusCompany.Id)) {
            normalizedIds.remove(focusCompany.Id);
        }
        if (normalizedIds.isEmpty()) {
            throw new AuraHandledException('Selected Accounts only contain the focus company. Choose at least one other Account.');
        }

        Map<Id, Account> accountMap = new Map<Id, Account>([
            SELECT Id, Name, Industry
            FROM Account
            WHERE Id IN :normalizedIds
        ]);
        if (accountMap.isEmpty()) {
            throw new AuraHandledException('No valid Account found in selection.');
        }

        String batchId = buildBatchId();
        List<CM_Meeting_Transcript__c> inserts = new List<CM_Meeting_Transcript__c>();

        for (Id accountId : normalizedIds) {
            Account counterpart = accountMap.get(accountId);
            if (counterpart == null) {
                continue;
            }

            CM_Meeting_Transcript__c record = new CM_Meeting_Transcript__c();
            record.Focus_Company__c = focusCompany.Id;
            record.Counterparty_Account__c = counterpart.Id;
            record.Duration_Minutes__c = DEFAULT_DURATION_MINUTES;
            record.Batch_Id__c = batchId;
            record.Status__c = 'Queued';
            record.Summary__c = null;
            record.Transcript__c = null;
            record.Action_Items__c = null;
            record.Prompt_Response__c = null;
            record.Error_Message__c = null;
            record.Generated_At__c = null;
            inserts.add(record);
        }

        if (inserts.isEmpty()) {
            throw new AuraHandledException('No valid Account found in selection.');
        }

        insert inserts;
        System.enqueueJob(new TranscriptGenerationQueueable(batchId));

        StartSimulationResult result = new StartSimulationResult();
        result.batchId = batchId;
        result.createdCount = inserts.size();
        result.message =
            'Queued '
            + String.valueOf(inserts.size())
            + ' meeting transcript generation job(s) for '
            + focusCompany.Name
            + '.';
        return result;
    }

    @AuraEnabled
    public static BatchStatusPayload getBatchStatus(String batchId) {
        if (String.isBlank(batchId)) {
            throw new AuraHandledException('Batch Id is required.');
        }

        List<CM_Meeting_Transcript__c> records = [
            SELECT
                Id,
                Counterparty_Account__c,
                Counterparty_Account__r.Name,
                Status__c,
                Summary__c,
                Error_Message__c,
                Generated_At__c
            FROM CM_Meeting_Transcript__c
            WHERE Batch_Id__c = :batchId
            ORDER BY Generated_At__c DESC, CreatedDate DESC
            LIMIT 500
        ];

        BatchStatusPayload payload = new BatchStatusPayload();
        payload.batchId = batchId;
        payload.totalCount = records.size();
        payload.queuedCount = 0;
        payload.processingCount = 0;
        payload.completedCount = 0;
        payload.failedCount = 0;
        payload.rows = new List<TranscriptRow>();

        for (CM_Meeting_Transcript__c record : records) {
            String status = normalizeStatus(record.Status__c);
            if (status == 'Queued') {
                payload.queuedCount++;
            } else if (status == 'Processing') {
                payload.processingCount++;
            } else if (status == 'Failed') {
                payload.failedCount++;
            } else {
                payload.completedCount++;
            }

            TranscriptRow row = new TranscriptRow();
            row.transcriptId = record.Id;
            row.accountId = record.Counterparty_Account__c;
            row.accountName = record.Counterparty_Account__r == null ? null : record.Counterparty_Account__r.Name;
            row.status = status;
            row.summary = record.Summary__c;
            row.errorMessage = record.Error_Message__c;
            row.generatedAt = record.Generated_At__c;
            row.recordUrl = '/lightning/r/CM_Meeting_Transcript__c/' + String.valueOf(record.Id) + '/view';
            payload.rows.add(row);
        }

        payload.done = payload.queuedCount == 0 && payload.processingCount == 0;
        return payload;
    }

    private class TranscriptGenerationQueueable implements Queueable, Database.AllowsCallouts {
        private final String batchId;

        TranscriptGenerationQueueable(String batchId) {
            this.batchId = batchId;
        }

        public void execute(QueueableContext context) {
            if (String.isBlank(batchId)) {
                return;
            }

            List<CM_Meeting_Transcript__c> pendingRecords = [
                SELECT
                    Id,
                    Focus_Company__c,
                    Focus_Company__r.Name,
                    Counterparty_Account__c,
                    Counterparty_Account__r.Name,
                    Counterparty_Account__r.Industry,
                    Duration_Minutes__c
                FROM CM_Meeting_Transcript__c
                WHERE Batch_Id__c = :batchId
                  AND Status__c = 'Queued'
                ORDER BY CreatedDate ASC
                LIMIT 200
            ];

            if (pendingRecords.isEmpty()) {
                return;
            }

            Datetime generatedAt = System.now();
            for (CM_Meeting_Transcript__c record : pendingRecords) {
                try {
                    TranscriptPackage transcript = buildTranscriptPackageFromPrompt(
                        record.Focus_Company__r == null ? null : record.Focus_Company__r.Name,
                        record.Counterparty_Account__c,
                        record.Counterparty_Account__r == null ? null : record.Counterparty_Account__r.Name,
                        record.Counterparty_Account__r == null ? null : record.Counterparty_Account__r.Industry,
                        record.Duration_Minutes__c == null
                            ? DEFAULT_DURATION_MINUTES
                            : Integer.valueOf(String.valueOf(record.Duration_Minutes__c))
                    );

                    record.Status__c = 'Completed';
                    record.Summary__c = transcript.summary;
                    record.Transcript__c = transcript.transcript;
                    record.Action_Items__c = transcript.actionItems;
                    record.Prompt_Response__c = transcript.promptResponse;
                    record.Error_Message__c = null;
                    record.Generated_At__c = generatedAt;
                } catch (Exception ex) {
                    record.Status__c = 'Failed';
                    record.Error_Message__c = truncateForLongText(ex.getMessage());
                    record.Generated_At__c = generatedAt;
                }
            }

            update pendingRecords;
        }
    }

    private static Account getActiveDemoTargetAccount(Boolean required) {
        List<Account> focusCompanies = [
            SELECT Id, Name
            FROM Account
            WHERE CM_Is_Demo_Target__c = true
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];

        if (focusCompanies.isEmpty()) {
            if (required) {
                throw new AuraHandledException(
                    'Demo target Account is not configured. Please set FocusCompany in Demo Setup first.'
                );
            }
            return null;
        }
        return focusCompanies[0];
    }

    private static TranscriptPackage buildTranscriptPackageFromPrompt(
        String focusCompanyName,
        Id counterpartyAccountId,
        String counterpartyName,
        String counterpartyIndustry,
        Integer durationMinutes
    ) {
        TranscriptPackage fallbackPackage = buildTranscriptPackage(
            focusCompanyName,
            counterpartyName,
            counterpartyIndustry,
            durationMinutes
        );

        String safeFocusCompanyName = String.isBlank(focusCompanyName) ? 'Focus Company' : focusCompanyName;
        String safeCounterpartyName = String.isBlank(counterpartyName) ? 'Account' : counterpartyName;
        String safeIndustry = String.isBlank(counterpartyIndustry) ? '電子產業' : counterpartyIndustry;
        Integer safeDuration = durationMinutes == null || durationMinutes <= 0
            ? DEFAULT_DURATION_MINUTES
            : durationMinutes;

        String rawPromptResponse = callTranscriptPromptTemplate(
            safeFocusCompanyName,
            counterpartyAccountId,
            safeCounterpartyName,
            safeIndustry,
            safeDuration
        );
        Map<String, Object> parsed = parsePromptOutput(rawPromptResponse);
        if (parsed == null) {
            throw new AuraHandledException('Prompt template output is not valid JSON.');
        }

        String transcript = asString(parsed.get('transcript'));
        if (String.isBlank(transcript)) {
            throw new AuraHandledException('Prompt template output must include a non-empty "transcript".');
        }

        String summary = asString(parsed.get('summary'));
        String actionItems = normalizeActionItems(
            parsed.containsKey('action_items')
                ? parsed.get('action_items')
                : parsed.get('actionItems')
        );

        TranscriptPackage promptPackage = new TranscriptPackage();
        promptPackage.summary = truncateForLongText(
            String.isBlank(summary) ? fallbackPackage.summary : summary
        );
        promptPackage.transcript = truncateForLongText(transcript);
        promptPackage.actionItems = truncateForLongText(
            String.isBlank(actionItems) ? fallbackPackage.actionItems : actionItems
        );
        promptPackage.promptResponse = truncateForLongText(rawPromptResponse);
        return promptPackage;
    }

    private static String callTranscriptPromptTemplate(
        String focusCompanyName,
        Id counterpartyAccountId,
        String counterpartyName,
        String counterpartyIndustry,
        Integer durationMinutes
    ) {
        if (counterpartyAccountId == null) {
            throw new AuraHandledException('Counterparty Account is required for transcript prompt generation.');
        }
        if (Test.isRunningTest()) {
            if (testPromptResponse != null) {
                return testPromptResponse;
            }
            return JSON.serialize(
                new Map<String, Object>{
                    'summary' => '測試用模擬會議摘要',
                    'transcript' =>
                        '[00:00] WNC 供應鏈經理：會議開場與目標確認。'
                        + '\n'
                        + '[00:05] ' + counterpartyName + ' 業務總監：確認交期與需求視窗。',
                    'action_items' => new List<String>{
                        '下週提供 12 週 forecast',
                        '月底前回覆 OTD 改善計畫',
                        '兩週後召開 checkpoint'
                    }
                }
            );
        }

        try {
            Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
            inputParams.put('Input:FocusCompany', toPrimitiveInput(focusCompanyName));
            inputParams.put('Input:RootAccount', toSObjectInput(counterpartyAccountId));
            inputParams.put('Input:CounterpartyName', toPrimitiveInput(counterpartyName));
            inputParams.put('Input:CounterpartyIndustry', toPrimitiveInput(counterpartyIndustry));
            inputParams.put('Input:MeetingDurationMinutes', toPrimitiveInput(String.valueOf(durationMinutes)));

            ConnectApi.EinsteinPromptTemplateGenerationsInput promptInput =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            promptInput.inputParams = inputParams;
            promptInput.isPreview = false;

            ConnectApi.EinsteinLlmAdditionalConfigInput additionalConfig =
                new ConnectApi.EinsteinLlmAdditionalConfigInput();
            additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
            promptInput.additionalConfig = additionalConfig;

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation promptResult =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(PROMPT_TEMPLATE_NAME, promptInput);

            if (promptResult == null || promptResult.generations == null || promptResult.generations.isEmpty()) {
                throw new AuraHandledException('Prompt template returned no generation text.');
            }
            String generatedText = promptResult.generations[0].text;
            if (String.isBlank(generatedText)) {
                throw new AuraHandledException('Prompt template returned empty text.');
            }
            return generatedText;
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Prompt generation failed: ' + ex.getMessage());
        }
    }

    private static Map<String, Object> parsePromptOutput(String rawText) {
        if (String.isBlank(rawText)) {
            return null;
        }

        String normalized = normalizePromptOutput(rawText);
        Integer firstBrace = normalized.indexOf('{');
        Integer lastBrace = normalized.lastIndexOf('}');
        if (firstBrace < 0 || lastBrace < 0 || lastBrace <= firstBrace) {
            return null;
        }

        String jsonText = normalized.substring(firstBrace, lastBrace + 1);
        try {
            Object parsed = JSON.deserializeUntyped(jsonText);
            return parsed instanceof Map<String, Object> ? (Map<String, Object>) parsed : null;
        } catch (Exception ex) {
            throw new AuraHandledException('Prompt template output is not valid JSON: ' + ex.getMessage());
        }
    }

    private static String normalizePromptOutput(String rawText) {
        if (rawText == null) {
            return '';
        }
        return rawText
            .replace('```json', '')
            .replace('```', '')
            .trim();
    }

    private static String normalizeActionItems(Object rawValue) {
        if (rawValue == null) {
            return null;
        }
        if (rawValue instanceof List<Object>) {
            List<String> lines = new List<String>();
            for (Object item : (List<Object>) rawValue) {
                String text = asString(item);
                if (!String.isBlank(text)) {
                    lines.add('- ' + text);
                }
            }
            return lines.isEmpty() ? null : String.join(lines, '\n');
        }
        return asString(rawValue);
    }

    private static String asString(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }

    private static ConnectApi.WrappedValue toSObjectInput(Id recordId) {
        Map<String, String> recordRef = new Map<String, String>{ 'id' => String.valueOf(recordId) };
        ConnectApi.WrappedValue wrappedValue = new ConnectApi.WrappedValue();
        wrappedValue.value = recordRef;
        return wrappedValue;
    }

    private static ConnectApi.WrappedValue toPrimitiveInput(String value) {
        ConnectApi.WrappedValue wrappedValue = new ConnectApi.WrappedValue();
        wrappedValue.value = value;
        return wrappedValue;
    }

    private static TranscriptPackage buildTranscriptPackage(
        String focusCompanyName,
        String counterpartyName,
        String counterpartyIndustry,
        Integer durationMinutes
    ) {
        String safeFocusCompanyName = String.isBlank(focusCompanyName) ? 'Focus Company' : focusCompanyName;
        String safeCounterpartyName = String.isBlank(counterpartyName) ? 'Account' : counterpartyName;
        String safeIndustry = String.isBlank(counterpartyIndustry) ? '電子產業' : counterpartyIndustry;
        Integer safeDuration = durationMinutes == null || durationMinutes <= 0
            ? DEFAULT_DURATION_MINUTES
            : durationMinutes;

        List<String> lines = new List<String>();
        Integer turnCount = 16;
        Integer interval = Math.max(1, safeDuration / (turnCount - 1));

        for (Integer index = 0; index < turnCount; index++) {
            Integer minute = index == turnCount - 1
                ? safeDuration
                : Math.min(safeDuration, index * interval);
            String timestamp = formatTimestamp(minute);
            Boolean isWncTurn = Math.mod(index, 2) == 0;
            String speaker = isWncTurn
                ? WNC_SPEAKERS[Math.mod(index / 2, WNC_SPEAKERS.size())]
                : safeCounterpartyName + ' ' + getCounterpartyRole(index);
            String line = isWncTurn
                ? buildWncLine(index, safeFocusCompanyName, safeCounterpartyName, safeIndustry)
                : buildCounterpartyLine(index, safeFocusCompanyName, safeCounterpartyName, safeIndustry);
            lines.add('[' + timestamp + '] ' + speaker + '：' + line);
        }

        TranscriptPackage pack = new TranscriptPackage();
        pack.transcript = String.join(lines, '\n');
        pack.summary =
            '45 分鐘模擬會議已完成，重點包含：\n'
            + '1. 對齊 ' + safeCounterpartyName + ' 與 ' + safeFocusCompanyName + ' 的下季需求與產能配置。\n'
            + '2. 聚焦交期穩定度、價格機制與風險升級節點。\n'
            + '3. 雙方確認 owner 與 checkpoint 時程，避免會後追蹤失焦。';
        pack.actionItems =
            '- WNC 採購：下週三前提供 12 週 rolling forecast 與優先料號清單。\n'
            + '- ' + safeCounterpartyName + ' 供應計畫：月底前回覆 OTD 改善計畫與責任分工。\n'
            + '- 雙方業務窗口：兩週後召開 checkpoint，確認價格與備援方案狀態。';
        Map<String, Object> promptPayload = new Map<String, Object>{
            'generator' => 'deterministic-local-simulator',
            'duration_minutes' => safeDuration,
            'focus_company' => safeFocusCompanyName,
            'counterparty' => safeCounterpartyName,
            'industry' => safeIndustry
        };
        pack.promptResponse = truncateForLongText(JSON.serialize(promptPayload));
        return pack;
    }

    private static String buildWncLine(
        Integer turnIndex,
        String focusCompanyName,
        String counterpartyName,
        String counterpartyIndustry
    ) {
        List<String> templates = new List<String>{
            '感謝 ' + counterpartyName + ' 參與，今天希望在 45 分鐘內完成交付、成本與風險三個面向的對齊。',
            '先確認 ' + counterpartyName + ' 在 ' + counterpartyIndustry + ' 需求波動下的產能彈性與優先排產原則。',
            '關於 OTD 爭議，我方希望先對齊計分口徑，再討論改善行動的 owner 與完成時間。',
            '價格議題希望拆成前端 cost down 與後端 rebate 兩段，避免一次談判卡住。',
            '若上游缺料升溫，請先定義替代料與升級條件，確保 ' + focusCompanyName + ' 出貨不受衝擊。',
            '我們傾向將 VMI 覆蓋天數與 forecast 更新節奏一起綁定，以降低急單波動成本。',
            '本次會議希望先鎖定可執行的三件事，會後以週節奏追蹤。',
            '最後請雙方確認下一次 checkpoint 日期與需要升級到高層的議題清單。'
        };
        return templates[Math.mod(turnIndex / 2, templates.size())];
    }

    private static String buildCounterpartyLine(
        Integer turnIndex,
        String focusCompanyName,
        String counterpartyName,
        String counterpartyIndustry
    ) {
        List<String> templates = new List<String>{
            '了解，' + counterpartyName + ' 目前已為 ' + focusCompanyName + ' 預留關鍵料號產能，會優先保障主力機種需求。',
            '以目前 ' + counterpartyIndustry + ' 市況來看，交期風險主要來自上游交貨不穩，我方會提供每週風險名單。',
            'OTD 的計分邏輯我們同意先採單一版本，並由供應計畫窗口每週更新。',
            '價格部分可先提供兩段式方案，包含季度回饋與量能門檻，供 ' + focusCompanyName + ' 內部評估。',
            '若遇到缺料升級，我方可在 24 小時內回覆替代料可行性與交付影響。',
            'VMI 方面建議先從高週轉料號導入，確認流程穩定後再擴大範圍。',
            '會後我們會把 owner、時程與風險條件整理成追蹤表，避免資訊斷點。',
            '下次 checkpoint 我方可由業務與供應計畫共同參與，確保決策可以即時落地。'
        };
        return templates[Math.mod(turnIndex / 2, templates.size())];
    }

    private static String getCounterpartyRole(Integer turnIndex) {
        List<String> roles = new List<String>{
            '業務總監',
            '供應計畫經理',
            '產品經理',
            '營運主管'
        };
        return roles[Math.mod(turnIndex / 2, roles.size())];
    }

    private static String formatTimestamp(Integer minuteMark) {
        Integer safeMinuteMark = minuteMark == null || minuteMark < 0 ? 0 : minuteMark;
        Integer hours = safeMinuteMark / 60;
        Integer minutes = Math.mod(safeMinuteMark, 60);
        return padLeft(hours, 2) + ':' + padLeft(minutes, 2);
    }

    private static String padLeft(Integer value, Integer length) {
        String output = value == null ? '0' : String.valueOf(value);
        while (output.length() < length) {
            output = '0' + output;
        }
        return output;
    }

    private static String buildBatchId() {
        String seed =
            String.valueOf(System.now().getTime())
            + ':'
            + UserInfo.getUserId()
            + ':'
            + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        String digest = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(seed)));
        return 'BATCH-' + digest.substring(0, 16).toUpperCase();
    }

    private static String normalizeStatus(String rawStatus) {
        String normalized = normalizeText(rawStatus);
        if (String.isBlank(normalized)) {
            return 'Completed';
        }
        Set<String> supported = new Set<String>{ 'Queued', 'Processing', 'Completed', 'Failed' };
        return supported.contains(normalized) ? normalized : 'Completed';
    }

    private static String truncateForLongText(String value) {
        if (value == null) {
            return null;
        }
        Integer maxLength = 32000;
        return value.length() <= maxLength ? value : value.substring(0, maxLength);
    }

    private static String normalizeText(String rawValue) {
        return rawValue == null ? null : rawValue.trim();
    }
}