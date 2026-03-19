public without sharing class CMQBRAsyncEmailDraftService {
    private static final String PROMPT_NAME = 'CM_QBR_Follow_Up_Email_Draft';
    private static final Integer MAX_SNIPPET_LENGTH = 500;

    public class StartRequest {
        @InvocableVariable(required=true)
        public Id accountId;

        @InvocableVariable(required=true)
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

        List<CM_QBR_Email_Draft_Buffer__c> inserts = new List<CM_QBR_Email_Draft_Buffer__c>();
        for (StartRequest req : requests) {
            CM_QBR_Email_Draft_Buffer__c bufferRecord = new CM_QBR_Email_Draft_Buffer__c();
            bufferRecord.Account__c = req.accountId;
            bufferRecord.MeetingNotes__c = req.meetingNotes;
            bufferRecord.Status__c = 'Queued';
            inserts.add(bufferRecord);
        }

        if (!inserts.isEmpty()) {
            insert inserts;
        }

        List<CM_QBR_Email_Draft_Buffer__c> updates = new List<CM_QBR_Email_Draft_Buffer__c>();
        for (Integer index = 0; index < requests.size(); index++) {
            StartRequest req = requests[index];
            CM_QBR_Email_Draft_Buffer__c bufferRecord = inserts[index];
            StartResponse response = new StartResponse();
            response.bufferId = bufferRecord.Id;

            if (String.isBlank(req.meetingNotes)) {
                bufferRecord.Status__c = 'Failed';
                bufferRecord.ErrorMessage__c = 'Meeting notes are required.';
                updates.add(bufferRecord);
                response.status = 'Failed';
                response.message = 'Meeting notes are required.';
                results.add(response);
                continue;
            }

            Id jobId = System.enqueueJob(new DraftGenerationJob(bufferRecord.Id));
            bufferRecord.AsyncJobId__c = String.valueOf(jobId);
            updates.add(bufferRecord);

            response.status = 'Queued';
            response.message = 'Draft generation started.';
            results.add(response);
        }

        if (!updates.isEmpty()) {
            update updates;
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

            try {
                String promptText = invokePrompt(bufferRecord.MeetingNotes__c);
                ParsedDraft parsedDraft = parsePromptResponse(promptText, bufferRecord.MeetingNotes__c);

                bufferRecord.PromptResponse__c = promptText;
                bufferRecord.DraftSubject__c = parsedDraft.subject;
                bufferRecord.DraftBody__c = parsedDraft.body;
                bufferRecord.SuggestedRecipients__c = parsedDraft.suggestedRecipients;
                bufferRecord.ErrorMessage__c = null;
                bufferRecord.Status__c = 'Completed';
            } catch (Exception ex) {
                ParsedDraft fallbackDraft = buildFallbackDraft(bufferRecord.MeetingNotes__c);
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

    private static ParsedDraft parsePromptResponse(String rawPromptResponse, String meetingNotes) {
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
        draft.suggestedRecipients = joinList(draftMap.get('recipients'));
        draft.body = buildDraftBody(draftMap);

        if (String.isBlank(draft.subject)) {
            draft.subject = buildFallbackSubject();
        }
        if (String.isBlank(draft.body)) {
            draft.body = buildFallbackDraft(meetingNotes).body;
        }
        return draft;
    }

    private static String buildDraftBody(Map<String, Object> draftMap) {
        String html = '';
        String doubleBreak = '<p><br/></p><p><br/></p>';

        String greeting = normalizeGreeting(asString(draftMap.get('greeting')));
        if (!String.isBlank(greeting)) {
            html += '<p>' + escapeHtml(greeting.trim()) + '</p>';
            html += doubleBreak;
        }

        List<Object> agreements = asList(draftMap.get('key_agreements'));
        if (!agreements.isEmpty()) {
            html += '<p><b>以下為本次 QBR 會議對齊重點：</b></p><ul>';
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
            html += '<p><b>請依下列事項進行後續 follow-up：</b></p><ul>';
            for (Object actionItem : actionItems) {
                if (!(actionItem instanceof Map<String, Object>)) {
                    continue;
                }
                Map<String, Object> actionMap = (Map<String, Object>) actionItem;
                String owner = normalizeOwner(asString(actionMap.get('owner')));
                String action = asString(actionMap.get('action'));
                String targetDate = normalizeTargetDate(asString(actionMap.get('target_date')));
                if (String.isBlank(action)) {
                    continue;
                }
                String line = '';
                if (!String.isBlank(owner)) {
                    line += owner + ': ';
                }
                line += action.trim();
                if (!String.isBlank(targetDate)) {
                    line += '（目標：' + targetDate + '）';
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

    private static ParsedDraft buildFallbackDraft(String meetingNotes) {
        ParsedDraft draft = new ParsedDraft();
        draft.subject = buildFallbackSubject();
        draft.body =
            '<p>各位夥伴您好，</p>' +
            '<p><br/></p><p><br/></p>' +
            '<p>感謝參與本次 QBR 會議。以下先整理會後跟進草稿，請協助確認內容是否與會議結論一致。</p>' +
            '<p><b>會議重點摘要：</b></p>' +
            '<ul><li>' + escapeHtml(buildMeetingNoteSnippet(meetingNotes)) + '</li></ul>' +
            '<p>如上內容有需補充或調整之處，請直接回覆本信確認對齊。期待雙方後續合作順利推進。</p>';
        draft.suggestedRecipients = null;
        return draft;
    }

    private static String buildFallbackSubject() {
        return 'QBR 會議後續跟進 - ' + String.valueOf(Date.today());
    }

    private static String buildMeetingNoteSnippet(String meetingNotes) {
        if (String.isBlank(meetingNotes)) {
            return '本次會議涵蓋價格、交付、缺料與物流協調等議題。';
        }
        String normalized = meetingNotes.replace('\n', ' ').trim();
        if (normalized.length() <= MAX_SNIPPET_LENGTH) {
            return normalized;
        }
        return normalized.substring(0, MAX_SNIPPET_LENGTH) + '...';
    }

    private static String invokePrompt(String meetingNotes) {
        ConnectApi.EinsteinPromptTemplateGenerationsInput input = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        input.isPreview = false;
        input.inputParams = new Map<String, ConnectApi.WrappedValue>();

        ConnectApi.WrappedValue meetingNoteInput = new ConnectApi.WrappedValue();
        meetingNoteInput.value = meetingNotes;
        input.inputParams.put('Input:MeetingNote', meetingNoteInput);

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

    private static String joinList(Object value) {
        List<Object> items = asList(value);
        List<String> labels = new List<String>();
        for (Object item : items) {
            String label = asString(item);
            if (!String.isBlank(label)) {
                labels.add(label.trim());
            }
        }
        return labels.isEmpty() ? null : String.join(labels, '、');
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

    private static String normalizeTargetDate(String rawTargetDate) {
        if (String.isBlank(rawTargetDate)) {
            return null;
        }

        String normalized = rawTargetDate.trim().toUpperCase();
        if (normalized == 'ASAP') {
            return '儘速';
        }
        if (normalized == 'NEXT_WEEK') {
            return '下週';
        }
        if (normalized == 'END_OF_MONTH') {
            return '月底前';
        }
        if (normalized == 'PLUS_7_DAYS') {
            return '7 天內';
        }
        return rawTargetDate.trim();
    }

    private static String normalizeGreeting(String rawGreeting) {
        if (String.isBlank(rawGreeting)) {
            return rawGreeting;
        }
        return rawGreeting
            .replace('您好：', '您好，')
            .replace('您好:', '您好，');
    }

    private static String escapeHtml(String value) {
        return value == null ? '' : value.escapeHtml4();
    }
}