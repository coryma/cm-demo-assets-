public without sharing class CMQBRMeetingAnalysisService {
    private static final String PROMPT_NAME = 'CM_Meeting_Note_Analysis_Service';
    private static final String STATUS_PENDING = 'Pending';
    private static final String STATUS_COMPLETED = 'Completed';
    private static final String STATUS_FAILED = 'Failed';

    public class Request {
        @InvocableVariable(required=true label='Meeting Note')
        public String meetingNote;
    }

    public class Response {
        @InvocableVariable(label='Analysis JSON')
        public String analysisJson;

        @InvocableVariable(label='Formatted HTML')
        public String formattedHtml;

        @InvocableVariable(label='Draft Subject')
        public String draftSubject;

        @InvocableVariable(label='Draft Body')
        public String draftBody;

        @InvocableVariable(label='Suggested Recipients')
        public String suggestedRecipients;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    public class BackgroundStartResult {
        @AuraEnabled public String bufferId;
        @AuraEnabled public String status;
        @AuraEnabled public String errorMessage;
    }

    public class BackgroundStatusResult {
        @AuraEnabled public String bufferId;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean isTerminal;
        @AuraEnabled public String analysisJson;
        @AuraEnabled public String formattedHtml;
        @AuraEnabled public String draftSubject;
        @AuraEnabled public String draftBody;
        @AuraEnabled public String suggestedRecipients;
        @AuraEnabled public String errorMessage;
    }

    private class ParsedDraft {
        public String subject;
        public String body;
        public String suggestedRecipients;
    }

    private class AnalysisPayload {
        public String analysisJson;
        public String formattedHtml;
        public String draftSubject;
        public String draftBody;
        public String suggestedRecipients;
        public String errorMessage;
    }

    private class AnalysisQueueable implements Queueable {
        private final Id bufferId;
        private final String meetingNote;

        private AnalysisQueueable(Id bufferId, String meetingNote) {
            this.bufferId = bufferId;
            this.meetingNote = meetingNote;
        }

        public void execute(QueueableContext context) {
            AnalysisPayload payload = buildAnalysisPayload(this.meetingNote);
            update new CM_QBR_Email_Draft_Buffer__c(
                Id = this.bufferId,
                Status__c = String.isBlank(payload.errorMessage) ? STATUS_COMPLETED : STATUS_FAILED,
                PromptResponse__c = cropLongText(payload.analysisJson),
                DraftSubject__c = cropText(payload.draftSubject, 255),
                DraftBody__c = cropLongText(payload.draftBody),
                SuggestedRecipients__c = cropLongText(payload.suggestedRecipients),
                ErrorMessage__c = cropLongText(payload.errorMessage)
            );
        }
    }

    @InvocableMethod(
        label='CM Analyze Meeting Note'
        description='Runs the meeting-analysis prompt in Apex and returns normalized JSON plus formatted HTML'
    )
    public static List<Response> analyze(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null) {
            return responses;
        }

        for (Request req : requests) {
            AnalysisPayload payload = buildAnalysisPayload(req == null ? null : req.meetingNote);
            Response res = new Response();
            res.analysisJson = payload.analysisJson;
            res.formattedHtml = payload.formattedHtml;
            res.draftSubject = payload.draftSubject;
            res.draftBody = payload.draftBody;
            res.suggestedRecipients = payload.suggestedRecipients;
            res.errorMessage = payload.errorMessage;
            responses.add(res);
        }

        return responses;
    }

    @AuraEnabled(cacheable=false)
    public static BackgroundStartResult startBackgroundAnalysis(String meetingNote, String accountId) {
        BackgroundStartResult result = new BackgroundStartResult();
        if (String.isBlank(meetingNote)) {
            result.status = STATUS_FAILED;
            result.errorMessage = 'Meeting note is required.';
            return result;
        }

        try {
            CM_QBR_Email_Draft_Buffer__c buffer = new CM_QBR_Email_Draft_Buffer__c(
                Status__c = STATUS_PENDING,
                MeetingNotes__c = cropLongText(meetingNote)
            );
            Id parsedAccountId = tryParseId(accountId);
            if (parsedAccountId != null) {
                buffer.Account__c = parsedAccountId;
            }
            insert buffer;

            Id jobId = System.enqueueJob(new AnalysisQueueable(buffer.Id, meetingNote));
            update new CM_QBR_Email_Draft_Buffer__c(
                Id = buffer.Id,
                AsyncJobId__c = String.valueOf(jobId)
            );

            result.bufferId = buffer.Id;
            result.status = STATUS_PENDING;
        } catch (Exception ex) {
            result.status = STATUS_FAILED;
            result.errorMessage = ex.getMessage();
        }
        return result;
    }

    @AuraEnabled(cacheable=false)
    public static BackgroundStatusResult getBackgroundAnalysisStatus(String bufferId) {
        BackgroundStatusResult result = new BackgroundStatusResult();
        Id parsedBufferId = tryParseId(bufferId);
        if (parsedBufferId == null) {
            result.status = STATUS_FAILED;
            result.isTerminal = true;
            result.errorMessage = 'Invalid buffer id.';
            applyFallbackOutputs(result);
            return result;
        }

        CM_QBR_Email_Draft_Buffer__c buffer = [
            SELECT Id, Status__c, PromptResponse__c, DraftSubject__c, DraftBody__c,
                   SuggestedRecipients__c, ErrorMessage__c
            FROM CM_QBR_Email_Draft_Buffer__c
            WHERE Id = :parsedBufferId
            LIMIT 1
        ];

        result.bufferId = buffer.Id;
        result.status = String.isBlank(buffer.Status__c) ? STATUS_PENDING : buffer.Status__c;
        result.isTerminal = result.status == STATUS_COMPLETED || result.status == STATUS_FAILED;
        result.analysisJson = buffer.PromptResponse__c;
        result.errorMessage = buffer.ErrorMessage__c;
        result.suggestedRecipients = buffer.SuggestedRecipients__c;

        if (!String.isBlank(buffer.DraftSubject__c)) {
            result.draftSubject = buffer.DraftSubject__c;
        }
        if (!String.isBlank(buffer.DraftBody__c)) {
            result.draftBody = buffer.DraftBody__c;
        }

        if (result.isTerminal) {
            if (!String.isBlank(buffer.PromptResponse__c)) {
                result.formattedHtml = CMQBRFollowupHtmlFormatter.formatJsonToHtml(buffer.PromptResponse__c);
            }
            if (String.isBlank(result.formattedHtml)) {
                result.formattedHtml = fallbackHtml();
            }
            ParsedDraft fallbackDraft = buildFallbackDraft();
            if (String.isBlank(result.draftSubject)) {
                result.draftSubject = fallbackDraft.subject;
            }
            if (String.isBlank(result.draftBody)) {
                result.draftBody = fallbackDraft.body;
            }
        }

        return result;
    }

    private static AnalysisPayload buildAnalysisPayload(String meetingNote) {
        AnalysisPayload payload = new AnalysisPayload();
        try {
            if (String.isBlank(meetingNote)) {
                throw new AuraHandledException('Meeting note is required.');
            }

            String rawPromptResponse = invokePrompt(meetingNote);
            String normalizedJson = CMQBRFollowupHtmlFormatter.normalizeJson(rawPromptResponse);
            payload.analysisJson = String.isBlank(normalizedJson) ? '{}' : normalizedJson;
            payload.formattedHtml = CMQBRFollowupHtmlFormatter.formatJsonToHtml(payload.analysisJson);

            ParsedDraft draft = parseDraftFromAnalysisJson(payload.analysisJson);
            payload.draftSubject = draft.subject;
            payload.draftBody = draft.body;
            payload.suggestedRecipients = draft.suggestedRecipients;
        } catch (Exception ex) {
            payload.analysisJson = '{}';
            payload.formattedHtml = fallbackHtml();
            ParsedDraft draft = buildFallbackDraft();
            payload.draftSubject = draft.subject;
            payload.draftBody = draft.body;
            payload.suggestedRecipients = draft.suggestedRecipients;
            payload.errorMessage = ex.getMessage();
        }
        return payload;
    }

    private static void applyFallbackOutputs(BackgroundStatusResult result) {
        ParsedDraft draft = buildFallbackDraft();
        result.analysisJson = '{}';
        result.formattedHtml = fallbackHtml();
        result.draftSubject = draft.subject;
        result.draftBody = draft.body;
        result.suggestedRecipients = draft.suggestedRecipients;
    }

    private static String invokePrompt(String meetingNote) {
        ConnectApi.WrappedValue inputValue = new ConnectApi.WrappedValue();
        inputValue.value = meetingNote;

        Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
        inputParams.put('Input:MeetingNote', inputValue);

        ConnectApi.EinsteinPromptTemplateGenerationsInput promptInput =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        promptInput.inputParams = inputParams;
        promptInput.isPreview = false;

        ConnectApi.EinsteinLlmAdditionalConfigInput addcfg =
            new ConnectApi.EinsteinLlmAdditionalConfigInput();
        addcfg.applicationName = 'PromptTemplateGenerationsInvocable';
        promptInput.additionalConfig = addcfg;

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation result =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(PROMPT_NAME, promptInput);

        if (result == null || result.generations == null || result.generations.isEmpty()) {
            throw new AuraHandledException('Failed to generate meeting analysis response.');
        }

        String text = result.generations[0].text;
        if (String.isBlank(text)) {
            throw new AuraHandledException('Meeting analysis response is empty.');
        }
        return text;
    }

    private static ParsedDraft parseDraftFromAnalysisJson(String analysisJson) {
        ParsedDraft draft = buildFallbackDraft();
        if (String.isBlank(analysisJson)) {
            return draft;
        }

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(analysisJson);
        if (payload == null || !(payload.get('email_draft') instanceof Map<String, Object>)) {
            return draft;
        }

        Map<String, Object> emailDraft = (Map<String, Object>) payload.get('email_draft');
        String subject = asString(emailDraft.get('subject'));
        String body = buildDraftBody(emailDraft);
        String suggestedRecipients = joinList(emailDraft.get('recipients'));

        if (!String.isBlank(subject)) {
            draft.subject = subject;
        }
        if (!String.isBlank(body)) {
            draft.body = body;
        }
        if (!String.isBlank(suggestedRecipients)) {
            draft.suggestedRecipients = suggestedRecipients;
        }

        return draft;
    }

    private static ParsedDraft buildFallbackDraft() {
        ParsedDraft draft = new ParsedDraft();
        draft.subject = 'QBR 會議後續跟進 - ' + String.valueOf(Date.today());
        draft.body =
            '<p>各位夥伴您好，</p>' +
            '<p><br/></p><p><br/></p>' +
            '<p>感謝參與本次 QBR 會議。以下為會後跟進草稿，請協助確認內容是否與本次會議結論一致。</p>' +
            '<p>如內容需補充或調整，請直接回覆本信，以利雙方後續執行對齊。</p>';
        draft.suggestedRecipients = null;
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
            html += '<p><b>以下為本次 QBR 會議雙方共識：</b></p><ul>';
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

    private static Id tryParseId(String rawId) {
        if (String.isBlank(rawId)) {
            return null;
        }
        try {
            return Id.valueOf(rawId.trim());
        } catch (Exception ex) {
            return null;
        }
    }

    private static String cropText(String value, Integer maxLen) {
        if (value == null || maxLen == null || maxLen <= 0 || value.length() <= maxLen) {
            return value;
        }
        return value.substring(0, maxLen);
    }

    private static String cropLongText(String value) {
        return cropText(value, 32768);
    }

    private static List<Object> asList(Object value) {
        return value instanceof List<Object> ? (List<Object>) value : new List<Object>();
    }

    private static String asString(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static String escapeHtml(String value) {
        return value == null ? '' : value.escapeHtml4();
    }

    private static String fallbackHtml() {
        return '<h2>會議決議總覽</h2><p>無法取得會議分析資料。</p>' +
            '<h2>關鍵風險與待確認</h2><p>請稍後重試，或檢查逐字稿內容是否完整。</p>' +
            '<h2>會後行動清單</h2><p>目前無法產生行動清單。</p>';
    }
}