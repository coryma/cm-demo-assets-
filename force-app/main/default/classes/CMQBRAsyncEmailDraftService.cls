public without sharing class CMQBRAsyncEmailDraftService {
    private static final String PROMPT_NAME = 'CM_QBR_Follow_Up_Email_Draft';
    private static final Integer MAX_SNIPPET_LENGTH = 500;

    public class StartRequest {
        @InvocableVariable(required=true)
        public Id accountId;

        @InvocableVariable
        public String meetingNotes;
    }

    public class StartResponse {
        @InvocableVariable
        public Id bufferId;

        @InvocableVariable
        public String status;

        @InvocableVariable
        public String message;
    }

    public class DraftState {
        @AuraEnabled public Id bufferId;
        @AuraEnabled public String status;
        @AuraEnabled public String subject;
        @AuraEnabled public String body;
        @AuraEnabled public String suggestedRecipients;
        @AuraEnabled public String errorMessage;
    }

    @InvocableMethod(label='Start QBR Email Draft Generation')
    public static List<StartResponse> startGeneration(List<StartRequest> requests) {
        List<StartResponse> results = new List<StartResponse>();
        if (requests == null) {
            return results;
        }

        Boolean useChinese = isChineseLanguage();
        Set<Id> accountIds = new Set<Id>();
        for (StartRequest req : requests) {
            if (req != null && req.accountId != null) {
                accountIds.add(req.accountId);
            }
        }

        Id focusCompanyId = getActiveDemoTargetAccountId();
        Map<Id, String> transcriptByAccount = resolveTranscriptByAccount(accountIds, focusCompanyId);

        List<CM_QBR_Email_Draft_Buffer__c> inserts = new List<CM_QBR_Email_Draft_Buffer__c>();
        List<Integer> queuedIndexes = new List<Integer>();

        for (Integer index = 0; index < requests.size(); index++) {
            StartRequest req = requests[index];
            CM_QBR_Email_Draft_Buffer__c bufferRecord = new CM_QBR_Email_Draft_Buffer__c();
            StartResponse response = new StartResponse();

            Id requestAccountId = req == null ? null : req.accountId;
            String requestMeetingNotes = req == null ? null : req.meetingNotes;
            String transcriptMeetingNotes = requestAccountId == null
                ? null
                : transcriptByAccount.get(requestAccountId);
            String resolvedMeetingNotes = String.isBlank(transcriptMeetingNotes)
                ? requestMeetingNotes
                : transcriptMeetingNotes;

            bufferRecord.Account__c = requestAccountId;
            bufferRecord.MeetingNotes__c = resolvedMeetingNotes;

            if (requestAccountId == null) {
                String message = useChinese
                    ? 'Account Id 為必填。'
                    : 'Account Id is required.';
                bufferRecord.Status__c = 'Failed';
                bufferRecord.ErrorMessage__c = message;
                response.status = 'Failed';
                response.message = message;
                inserts.add(bufferRecord);
                results.add(response);
                continue;
            }

            if (String.isBlank(resolvedMeetingNotes)) {
                String message = useChinese
                    ? '找不到可用會議逐字稿；請先在 CM Demo Assets Setup 產生會議記錄，或提供 meetingNotes。'
                    : 'No meeting transcript found for this account. Generate one in CM Demo Assets Setup, or provide meetingNotes.';
                bufferRecord.Status__c = 'Failed';
                bufferRecord.ErrorMessage__c = message;
                response.status = 'Failed';
                response.message = message;
                inserts.add(bufferRecord);
                results.add(response);
                continue;
            }

            bufferRecord.Status__c = 'Queued';
            response.status = 'Queued';
            response.message = useChinese
                ? '草稿背景產生已啟動。'
                : 'Background draft generation started.';

            inserts.add(bufferRecord);
            results.add(response);
            queuedIndexes.add(index);
        }

        if (!inserts.isEmpty()) {
            insert inserts;
        }

        List<CM_QBR_Email_Draft_Buffer__c> asyncUpdates = new List<CM_QBR_Email_Draft_Buffer__c>();
        for (Integer index = 0; index < inserts.size(); index++) {
            results[index].bufferId = inserts[index].Id;
        }

        for (Integer requestIndex : queuedIndexes) {
            CM_QBR_Email_Draft_Buffer__c bufferRecord = inserts[requestIndex];
            Id jobId = System.enqueueJob(new DraftGenerationJob(bufferRecord.Id));
            bufferRecord.AsyncJobId__c = String.valueOf(jobId);
            asyncUpdates.add(bufferRecord);
        }

        if (!asyncUpdates.isEmpty()) {
            update asyncUpdates;
        }

        return results;
    }

    @AuraEnabled(cacheable=false)
    public static DraftState getDraftState(Id bufferId) {
        if (bufferId == null) {
            return null;
        }

        CM_QBR_Email_Draft_Buffer__c bufferRecord = [
            SELECT Id, Status__c, DraftSubject__c, DraftBody__c, SuggestedRecipients__c, ErrorMessage__c
            FROM CM_QBR_Email_Draft_Buffer__c
            WHERE Id = :bufferId
            LIMIT 1
        ];

        DraftState state = new DraftState();
        state.bufferId = bufferRecord.Id;
        state.status = bufferRecord.Status__c;
        state.subject = bufferRecord.DraftSubject__c;
        state.body = bufferRecord.DraftBody__c;
        state.suggestedRecipients = bufferRecord.SuggestedRecipients__c;
        state.errorMessage = bufferRecord.ErrorMessage__c;
        return state;
    }

    public class DraftGenerationJob implements Queueable, Database.AllowsCallouts {
        private final Id bufferId;

        public DraftGenerationJob(Id bufferId) {
            this.bufferId = bufferId;
        }

        public void execute(QueueableContext context) {
            CM_QBR_Email_Draft_Buffer__c bufferRecord = [
                SELECT Id, MeetingNotes__c
                FROM CM_QBR_Email_Draft_Buffer__c
                WHERE Id = :bufferId
                LIMIT 1
            ];

            bufferRecord.Status__c = 'Processing';
            update bufferRecord;

            Boolean useChinese = isChineseLanguage();
            try {
                String promptText = invokePrompt(bufferRecord.MeetingNotes__c, useChinese);
                ParsedDraft parsedDraft = parsePromptResponse(promptText, bufferRecord.MeetingNotes__c, useChinese);

                bufferRecord.PromptResponse__c = promptText;
                bufferRecord.DraftSubject__c = parsedDraft.subject;
                bufferRecord.DraftBody__c = parsedDraft.body;
                bufferRecord.SuggestedRecipients__c = parsedDraft.suggestedRecipients;
                bufferRecord.ErrorMessage__c = null;
                bufferRecord.Status__c = 'Completed';
            } catch (Exception ex) {
                ParsedDraft fallbackDraft = buildFallbackDraft(bufferRecord.MeetingNotes__c, useChinese);
                bufferRecord.DraftSubject__c = fallbackDraft.subject;
                bufferRecord.DraftBody__c = fallbackDraft.body;
                bufferRecord.ErrorMessage__c = String.valueOf(ex);
                bufferRecord.Status__c = 'Completed';
            }

            update bufferRecord;
        }
    }

    private class ParsedDraft {
        public String subject;
        public String body;
        public String suggestedRecipients;
    }

    private static ParsedDraft parsePromptResponse(
        String rawPromptResponse,
        String meetingNotes,
        Boolean useChinese
    ) {
        Map<String, Object> parsed = parseJsonObject(rawPromptResponse);
        if (parsed == null) {
            throw new AuraHandledException('Prompt response is not valid JSON.');
        }

        Object nestedDraft = parsed.get('email_draft');
        if (!(nestedDraft instanceof Map<String, Object>)) {
            throw new AuraHandledException('email_draft node is missing.');
        }

        Map<String, Object> draftMap = (Map<String, Object>) nestedDraft;
        ParsedDraft draft = new ParsedDraft();
        draft.subject = asString(draftMap.get('subject'));
        draft.suggestedRecipients = joinList(draftMap.get('recipients'), useChinese);
        draft.body = buildDraftBody(draftMap, useChinese);

        if (String.isBlank(draft.subject)) {
            draft.subject = buildFallbackSubject(useChinese);
        }
        if (String.isBlank(draft.body)) {
            draft.body = buildFallbackDraft(meetingNotes, useChinese).body;
        }
        return draft;
    }

    private static String buildDraftBody(Map<String, Object> draftMap, Boolean useChinese) {
        String html = '';
        String doubleBreak = '<p><br/></p><p><br/></p>';

        String greeting = normalizeGreeting(asString(draftMap.get('greeting')), useChinese);
        if (!String.isBlank(greeting)) {
            html += '<p>' + escapeHtml(greeting.trim()) + '</p>';
            html += doubleBreak;
        }

        List<Object> agreements = asList(draftMap.get('key_agreements'));
        if (!agreements.isEmpty()) {
            html += useChinese
                ? '<p><b>以下為本次 QBR 會議對齊重點：</b></p><ul>'
                : '<p><b>Aligned outcomes from this QBR:</b></p><ul>';
            for (Object agreement : agreements) {
                String line = asString(agreement);
                if (!String.isBlank(line)) {
                    html += '<li>' + escapeHtml(line.trim()) + '</li>';
                }
            }
            html += '</ul>';
        }

        List<Object> actionItems = asList(draftMap.get('action_items'));
        if (!actionItems.isEmpty()) {
            html += useChinese
                ? '<p><b>請依下列事項進行後續 follow-up：</b></p><ul>'
                : '<p><b>Follow-up action items:</b></p><ul>';
            for (Object actionItem : actionItems) {
                if (!(actionItem instanceof Map<String, Object>)) {
                    continue;
                }
                Map<String, Object> actionMap = (Map<String, Object>) actionItem;
                String owner = normalizeOwner(asString(actionMap.get('owner')));
                String action = asString(actionMap.get('action'));
                String targetDate = normalizeTargetDate(asString(actionMap.get('target_date')), useChinese);
                if (String.isBlank(action)) {
                    continue;
                }

                String line = '';
                if (!String.isBlank(owner)) {
                    line += owner + ': ';
                }
                line += action.trim();
                if (!String.isBlank(targetDate)) {
                    line += useChinese
                        ? '（目標：' + targetDate + '）'
                        : ' (Target: ' + targetDate + ')';
                }
                html += '<li>' + escapeHtml(line) + '</li>';
            }
            html += '</ul>';
        }

        String closing = asString(draftMap.get('closing'));
        if (!String.isBlank(closing)) {
            if (!String.isBlank(html)) {
                html += doubleBreak;
            }
            html += '<p>' + escapeHtml(closing.trim()).replace('\n', '<br/>') + '</p>';
        }

        return String.isBlank(html) ? null : html;
    }

    private static ParsedDraft buildFallbackDraft(String meetingNotes, Boolean useChinese) {
        ParsedDraft draft = new ParsedDraft();
        draft.subject = buildFallbackSubject(useChinese);
        if (useChinese) {
            draft.body =
                '<p>各位夥伴您好，</p>' +
                '<p><br/></p><p><br/></p>' +
                '<p>感謝參與本次 QBR 會議。以下先整理會後跟進草稿，請協助確認內容是否與會議結論一致。</p>' +
                '<p><b>會議重點摘要：</b></p>' +
                '<ul><li>' + escapeHtml(buildMeetingNoteSnippet(meetingNotes, true)) + '</li></ul>' +
                '<p>如上內容有需補充或調整之處，請直接回覆本信確認對齊。期待雙方後續合作順利推進。</p>';
        } else {
            draft.body =
                '<p>Team,</p>' +
                '<p><br/></p><p><br/></p>' +
                '<p>Thank you for joining the QBR session. Please review this follow-up draft and confirm alignment.</p>' +
                '<p><b>Meeting summary:</b></p>' +
                '<ul><li>' + escapeHtml(buildMeetingNoteSnippet(meetingNotes, false)) + '</li></ul>' +
                '<p>If any point needs adjustment, please reply to confirm. Looking forward to the next steps together.</p>';
        }
        draft.suggestedRecipients = null;
        return draft;
    }

    private static String buildFallbackSubject(Boolean useChinese) {
        return useChinese
            ? 'QBR 會議後續跟進 - ' + String.valueOf(Date.today())
            : 'QBR Follow-up Actions - ' + String.valueOf(Date.today());
    }

    private static String buildMeetingNoteSnippet(String meetingNotes, Boolean useChinese) {
        if (String.isBlank(meetingNotes)) {
            return useChinese
                ? '本次會議涵蓋價格、交付、缺料與物流協調等議題。'
                : 'This meeting covered pricing, delivery, shortages, and logistics alignment.';
        }

        String normalized = meetingNotes.replace('\n', ' ').trim();
        if (normalized.length() <= MAX_SNIPPET_LENGTH) {
            return normalized;
        }
        return normalized.substring(0, MAX_SNIPPET_LENGTH) + '...';
    }

    private static String invokePrompt(String meetingNotes, Boolean useChinese) {
        ConnectApi.EinsteinPromptTemplateGenerationsInput input =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        input.isPreview = false;
        input.inputParams = new Map<String, ConnectApi.WrappedValue>();

        ConnectApi.WrappedValue meetingNoteInput = new ConnectApi.WrappedValue();
        meetingNoteInput.value = meetingNotes;
        input.inputParams.put('Input:MeetingNote', meetingNoteInput);

        ConnectApi.WrappedValue outputLanguageInput = new ConnectApi.WrappedValue();
        outputLanguageInput.value = useChinese ? 'zh-TW' : 'en-US';
        input.inputParams.put('Input:OutputLanguage', outputLanguageInput);

        ConnectApi.EinsteinLlmAdditionalConfigInput additionalConfig =
            new ConnectApi.EinsteinLlmAdditionalConfigInput();
        additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
        input.additionalConfig = additionalConfig;

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation response =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(PROMPT_NAME, input);

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
        Object parsed = JSON.deserializeUntyped(jsonText);
        return parsed instanceof Map<String, Object> ? (Map<String, Object>) parsed : null;
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

    private static String asString(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static List<Object> asList(Object value) {
        return value instanceof List<Object> ? (List<Object>) value : new List<Object>();
    }

    private static String joinList(Object value, Boolean useChinese) {
        List<Object> items = asList(value);
        List<String> labels = new List<String>();
        for (Object item : items) {
            String label = asString(item);
            if (!String.isBlank(label)) {
                labels.add(label.trim());
            }
        }

        if (labels.isEmpty()) {
            return null;
        }
        return useChinese
            ? String.join(labels, '、')
            : String.join(labels, ', ');
    }

    private static String normalizeOwner(String owner) {
        if (String.isBlank(owner)) {
            return owner;
        }

        String normalized = owner.trim();
        List<String> duplicates = new List<String>{
            'WNC WNC ',
            'Qualcomm Qualcomm ',
            'WNC 資材處 WNC ',
            'WNC R&D WNC '
        };
        for (String duplicate : duplicates) {
            while (normalized.startsWith(duplicate)) {
                normalized = normalized.substring(duplicate.length());
                if (!normalized.startsWith('WNC ') && duplicate.startsWith('WNC ')) {
                    normalized = 'WNC ' + normalized;
                } else if (!normalized.startsWith('Qualcomm ') && duplicate.startsWith('Qualcomm ')) {
                    normalized = 'Qualcomm ' + normalized;
                }
            }
        }
        return normalized;
    }

    private static String normalizeTargetDate(String rawTargetDate, Boolean useChinese) {
        if (String.isBlank(rawTargetDate)) {
            return null;
        }

        String normalized = rawTargetDate.trim().toUpperCase();
        if (normalized == 'ASAP') {
            return useChinese ? '儘速' : 'ASAP';
        }
        if (normalized == 'NEXT_WEEK') {
            return useChinese ? '下週' : 'Next week';
        }
        if (normalized == 'END_OF_MONTH') {
            return useChinese ? '月底前' : 'End of month';
        }
        if (normalized == 'PLUS_7_DAYS') {
            return useChinese ? '7 天內' : 'Within 7 days';
        }
        return rawTargetDate.trim();
    }

    private static String normalizeGreeting(String rawGreeting, Boolean useChinese) {
        if (String.isBlank(rawGreeting) || !useChinese) {
            return rawGreeting;
        }

        return rawGreeting
            .replace('您好：', '您好，')
            .replace('您好:', '您好，');
    }

    private static Id getActiveDemoTargetAccountId() {
        List<Account> activeTargets = [
            SELECT Id
            FROM Account
            WHERE CM_Is_Demo_Target__c = true
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return activeTargets.isEmpty() ? null : activeTargets[0].Id;
    }

    private static Map<Id, String> resolveTranscriptByAccount(Set<Id> accountIds, Id focusCompanyId) {
        Map<Id, String> transcriptByAccount = new Map<Id, String>();
        if (accountIds == null || accountIds.isEmpty() || focusCompanyId == null) {
            return transcriptByAccount;
        }

        for (CM_Meeting_Transcript__c transcript : [
            SELECT Counterparty_Account__c, Transcript__c, Generated_At__c, LastModifiedDate
            FROM CM_Meeting_Transcript__c
            WHERE Focus_Company__c = :focusCompanyId
              AND Counterparty_Account__c IN :accountIds
              AND Status__c = 'Completed'
            ORDER BY Counterparty_Account__c, Generated_At__c DESC, LastModifiedDate DESC
            LIMIT 2000
        ]) {
            Id counterpartyId = transcript.Counterparty_Account__c;
            if (
                counterpartyId != null &&
                !String.isBlank(transcript.Transcript__c) &&
                !transcriptByAccount.containsKey(counterpartyId)
            ) {
                transcriptByAccount.put(counterpartyId, transcript.Transcript__c);
            }
        }
        return transcriptByAccount;
    }

    private static Boolean isChineseLanguage() {
        String language = UserInfo.getLanguage();
        return !String.isBlank(language) && language.toLowerCase().startsWith('zh');
    }

    private static String escapeHtml(String value) {
        return value == null ? '' : value.escapeHtml4();
    }
}
