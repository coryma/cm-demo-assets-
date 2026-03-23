public without sharing class CMEmailTimelineSimulationService {
    private static final Integer DEFAULT_EMAIL_COUNT = 3;
    private static final Integer MAX_EMAIL_COUNT = 10;
    private static final String BACKGROUND_PROMPT_API_NAME = 'CM_Mock_Email_Background_Context';
    private static final String DRAFT_PROMPT_API_NAME = 'CM_Draft_Mock_Email';
    private static final String DEFAULT_DEPARTMENT = 'GSCM';
    private static final String DIRECTION_OUTBOUND = 'OUTBOUND_ONLY';
    private static final String DIRECTION_INBOUND = 'INBOUND_ONLY';
    private static final String DIRECTION_MIXED = 'MIXED';

    private class SimulationException extends Exception {}

    public class Request {
        @InvocableVariable(required=true)
        public Id accountId;

        @InvocableVariable(required=true)
        public String backgroundContext;

        @InvocableVariable
        public Integer emailCount;

        @InvocableVariable
        public String simulationDirection;

        @InvocableVariable
        public String department;

        @InvocableVariable
        public String startDate;

        @InvocableVariable
        public String endDate;
    }

    public class Result {
        @InvocableVariable
        public Integer createdCount;

        @InvocableVariable
        public String previewSubject;

        @InvocableVariable
        public String message;

        @InvocableVariable
        public String createdEmailIds;
    }

    private class DraftData {
        String subject;
        String htmlBody;
    }

    @InvocableMethod(label='Generate Simulated Email Timeline Data')
    public static List<Result> generateSimulatedEmailTimelineData(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null) {
            return results;
        }

        for (Request requestItem : requests) {
            results.add(processSingle(requestItem));
        }
        return results;
    }

    private static Result processSingle(Request requestItem) {
        Result result = new Result();
        List<String> createdIds = new List<String>();

        try {
            validateRequest(requestItem);

            Integer emailCount = normalizeCount(requestItem.emailCount);
            String simulationDirection = normalizeDirection(requestItem.simulationDirection);
            String department = normalizeDepartment(requestItem.department);
            Date startDate = normalizeStartDate(requestItem.startDate);
            Date endDate = normalizeEndDate(startDate, requestItem.endDate);

            Account accountRecord = [
                SELECT Id, Name
                FROM Account
                WHERE Id = :requestItem.accountId
                LIMIT 1
            ];
            List<Contact> recipients = [
                SELECT Id, Name, Email
                FROM Contact
                WHERE AccountId = :requestItem.accountId
                AND Email != null
                ORDER BY CreatedDate
                LIMIT 50
            ];
            if (recipients.isEmpty()) {
                throw new SimulationException('此 Account 沒有可用的聯絡人電子郵件，無法建立模擬郵件。');
            }

            User currentUser = [
                SELECT Id, Name, Email
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];
            if (String.isBlank(currentUser.Email)) {
                throw new SimulationException('目前使用者沒有 Email，無法建立模擬郵件。');
            }

            String backgroundContext = resolveBackgroundContext(
                requestItem.backgroundContext,
                accountRecord,
                department,
                simulationDirection
            );

            DraftData outboundDraft =
                simulationDirection == DIRECTION_INBOUND
                ? null
                : generateDraftFromPrompt(accountRecord, department, backgroundContext, DIRECTION_OUTBOUND);
            DraftData inboundDraft =
                simulationDirection == DIRECTION_OUTBOUND
                ? null
                : generateDraftFromPrompt(accountRecord, department, backgroundContext, DIRECTION_INBOUND);

            List<DateTime> messageDates = buildMessageDates(startDate, endDate, emailCount);
            List<EmailMessage> emailsToInsert = new List<EmailMessage>();
            List<Contact> emailRecipients = new List<Contact>();
            List<String> emailDirections = new List<String>();

            for (Integer index = 0; index < emailCount; index++) {
                Integer recipientIndex = Math.mod(index, recipients.size());
                Contact recipient = recipients[recipientIndex];
                Boolean isInbound = isInboundEmail(simulationDirection, index);
                DraftData draft = isInbound ? inboundDraft : outboundDraft;
                if (draft == null) {
                    draft = generateDraftFromPrompt(
                        accountRecord,
                        department,
                        backgroundContext,
                        isInbound ? DIRECTION_INBOUND : DIRECTION_OUTBOUND
                    );
                }
                String subject = variantSubject(draft.subject, index, emailCount, isInbound);
                String htmlBody = variantBody(draft.htmlBody, recipient.Name, currentUser.Name, index, emailCount, messageDates[index], isInbound);

                EmailMessage emailRecord = new EmailMessage();
                emailRecord.RelatedToId = accountRecord.Id;
                emailRecord.Subject = subject;
                emailRecord.HtmlBody = htmlBody;
                emailRecord.TextBody = htmlToPlainText(htmlBody);
                emailRecord.FromAddress = isInbound ? recipient.Email : currentUser.Email;
                emailRecord.FromName = isInbound ? recipient.Name : currentUser.Name;
                emailRecord.ToAddress = isInbound ? currentUser.Email : recipient.Email;
                emailRecord.MessageDate = messageDates[index];
                emailRecord.Incoming = isInbound;
                emailRecord.Status = '3';
                emailRecord.IsTracked = true;
                emailsToInsert.add(emailRecord);
                emailRecipients.add(recipient);
                emailDirections.add(isInbound ? DIRECTION_INBOUND : DIRECTION_OUTBOUND);
            }

            insert emailsToInsert;

            List<EmailMessageRelation> relations = new List<EmailMessageRelation>();
            for (Integer index = 0; index < emailsToInsert.size(); index++) {
                EmailMessage emailRecord = emailsToInsert[index];
                Contact recipient = emailRecipients[index];
                Boolean isInbound = emailDirections[index] == DIRECTION_INBOUND;

                EmailMessageRelation fromRelation = new EmailMessageRelation();
                fromRelation.EmailMessageId = emailRecord.Id;
                fromRelation.RelationId = isInbound ? recipient.Id : currentUser.Id;
                fromRelation.RelationType = 'FromAddress';
                fromRelation.RelationAddress = isInbound ? recipient.Email : currentUser.Email;
                relations.add(fromRelation);

                EmailMessageRelation toRelation = new EmailMessageRelation();
                toRelation.EmailMessageId = emailRecord.Id;
                toRelation.RelationId = isInbound ? currentUser.Id : recipient.Id;
                toRelation.RelationType = 'ToAddress';
                toRelation.RelationAddress = isInbound ? currentUser.Email : recipient.Email;
                relations.add(toRelation);

                createdIds.add((String) emailRecord.Id);
            }

            if (!relations.isEmpty()) {
                insert relations;
            }

            result.createdCount = emailsToInsert.size();
            result.previewSubject = emailsToInsert.isEmpty() ? null : emailsToInsert[0].Subject;
            result.createdEmailIds = String.join(createdIds, ', ');
            result.message =
                '已建立 '
                + String.valueOf(emailsToInsert.size())
                + ' 筆模擬郵件，期間 '
                + String.valueOf(startDate)
                + ' 至 '
                + String.valueOf(endDate)
                + '。';
            if (simulationDirection == DIRECTION_OUTBOUND) {
                result.message += ' 模式：Outbound only。';
            } else if (simulationDirection == DIRECTION_INBOUND) {
                result.message += ' 模式：Inbound only。';
            } else {
                result.message += ' 模式：Inbound + Outbound 混合。';
            }
        } catch (Exception ex) {
            result.createdCount = 0;
            result.previewSubject = null;
            result.createdEmailIds = null;
            result.message = ex.getMessage();
        }

        return result;
    }

    private static void validateRequest(Request requestItem) {
        if (requestItem == null || requestItem.accountId == null) {
            throw new SimulationException('AccountId 為必填。');
        }
    }

    private static Integer normalizeCount(Integer rawCount) {
        Integer safeCount = rawCount == null ? DEFAULT_EMAIL_COUNT : rawCount;
        if (safeCount < 1) {
            safeCount = 1;
        }
        if (safeCount > MAX_EMAIL_COUNT) {
            safeCount = MAX_EMAIL_COUNT;
        }
        return safeCount;
    }

    private static String normalizeDirection(String rawDirection) {
        String value = safeString(rawDirection);
        if (value == DIRECTION_INBOUND || value == DIRECTION_MIXED) {
            return value;
        }
        return DIRECTION_OUTBOUND;
    }

    private static String normalizeDepartment(String rawDepartment) {
        String value = safeString(rawDepartment);
        return String.isBlank(value) ? DEFAULT_DEPARTMENT : value;
    }

    private static Date normalizeStartDate(String startDateText) {
        if (String.isBlank(startDateText)) {
            return Date.today().addDays(-30);
        }
        try {
            return Date.valueOf(startDateText.trim());
        } catch (Exception ex) {
            return Date.today().addDays(-30);
        }
    }

    private static Date normalizeEndDate(Date startDate, String endDateText) {
        Date safeEndDate;
        if (String.isBlank(endDateText)) {
            safeEndDate = Date.today();
        } else {
            try {
                safeEndDate = Date.valueOf(endDateText.trim());
            } catch (Exception ex) {
                safeEndDate = Date.today();
            }
        }
        if (safeEndDate < startDate) {
            return startDate;
        }
        return safeEndDate;
    }

    private static String resolveBackgroundContext(
        String inputBackgroundContext,
        Account accountRecord,
        String department,
        String direction
    ) {
        if (!String.isBlank(inputBackgroundContext)) {
            return inputBackgroundContext.trim();
        }

        String generated = generateBackgroundContextFromPrompt(accountRecord, department, direction);
        if (!String.isBlank(generated)) {
            return generated;
        }

        return '公司：'
            + safeString(accountRecord.Name)
            + '；部門：'
            + safeString(department)
            + '；方向：'
            + directionLabel(direction)
            + '；請產生一封可用於活動時間軸展示的模擬商務郵件。';
    }

    private static String generateBackgroundContextFromPrompt(
        Account accountRecord,
        String department,
        String direction
    ) {
        try {
            Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
            inputParams.put('Input:Company', toSObjectInput(accountRecord.Id));
            inputParams.put('Input:Department', toPrimitiveInput(department));
            inputParams.put('Input:Direction', toPrimitiveInput(promptDirection(direction)));

            ConnectApi.EinsteinPromptTemplateGenerationsInput promptInput =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            promptInput.inputParams = inputParams;
            promptInput.isPreview = false;

            ConnectApi.EinsteinLlmAdditionalConfigInput additionalConfig =
                new ConnectApi.EinsteinLlmAdditionalConfigInput();
            additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
            promptInput.additionalConfig = additionalConfig;

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation response =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(BACKGROUND_PROMPT_API_NAME, promptInput);

            if (response != null && response.generations != null && !response.generations.isEmpty()) {
                return safeString(response.generations[0].text);
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'Background prompt failed: ' + ex.getMessage());
        }
        return null;
    }

    private static DraftData generateDraftFromPrompt(
        Account accountRecord,
        String department,
        String backgroundContext,
        String direction
    ) {
        String normalizedDirection = normalizeDirection(direction);
        String businessAccountName = resolveBusinessAccountName(accountRecord.Name);

        Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
        inputParams.put('Input:Company', toSObjectInput(accountRecord.Id));
        inputParams.put('Input:Department', toPrimitiveInput(department));
        inputParams.put('Input:Direction', toPrimitiveInput(promptDirection(normalizedDirection)));
        inputParams.put('Input:BackgroundContext', toPrimitiveInput(backgroundContext));

        ConnectApi.EinsteinPromptTemplateGenerationsInput promptInput =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        promptInput.inputParams = inputParams;
        promptInput.isPreview = false;

        ConnectApi.EinsteinLlmAdditionalConfigInput additionalConfig =
            new ConnectApi.EinsteinLlmAdditionalConfigInput();
        additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
        promptInput.additionalConfig = additionalConfig;

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation response =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(DRAFT_PROMPT_API_NAME, promptInput);

        if (response == null || response.generations == null || response.generations.isEmpty()) {
            return buildFallbackDraft(businessAccountName, backgroundContext, normalizedDirection);
        }

        String normalized = normalizeJson(response.generations[0].text);
        if (String.isBlank(normalized)) {
            return buildFallbackDraft(businessAccountName, backgroundContext, normalizedDirection);
        }

        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(normalized);
            Map<String, Object> draftMap = parsed == null
                ? null
                : (Map<String, Object>) parsed.get('email_draft');
            if (draftMap == null) {
                return buildFallbackDraft(businessAccountName, backgroundContext, normalizedDirection);
            }

            DraftData draft = new DraftData();
            draft.subject = safeString(draftMap.get('subject'));
            draft.htmlBody = sanitizeHtml(safeString(draftMap.get('htmlBody')));
            if (String.isBlank(draft.subject) || String.isBlank(draft.htmlBody)) {
                return buildFallbackDraft(businessAccountName, backgroundContext, normalizedDirection);
            }
            return draft;
        } catch (Exception ex) {
            return buildFallbackDraft(businessAccountName, backgroundContext, normalizedDirection);
        }
    }

    private static String promptDirection(String direction) {
        String normalized = normalizeDirection(direction);
        if (normalized == DIRECTION_INBOUND) {
            return 'Inbound';
        }
        if (normalized == DIRECTION_MIXED) {
            return 'Mixed';
        }
        return 'Outbound';
    }

    private static ConnectApi.WrappedValue toPrimitiveInput(String value) {
        ConnectApi.WrappedValue wrapped = new ConnectApi.WrappedValue();
        wrapped.value = value;
        return wrapped;
    }

    private static ConnectApi.WrappedValue toSObjectInput(Id recordId) {
        Map<String, String> recordRef = new Map<String, String>{ 'id' => String.valueOf(recordId) };
        ConnectApi.WrappedValue wrappedValue = new ConnectApi.WrappedValue();
        wrappedValue.value = recordRef;
        return wrappedValue;
    }

    private static String normalizeJson(String rawJson) {
        if (String.isBlank(rawJson)) {
            return null;
        }

        String cleaned = rawJson
            .replace('```json', '')
            .replace('```', '')
            .replace('\u00A0', ' ')
            .replace('\u201C', '"')
            .replace('\u201D', '"')
            .replace('\u2018', '\'')
            .replace('\u2019', '\'')
            .trim();

        Integer startIndex = cleaned.indexOf('{');
        Integer endIndex = cleaned.lastIndexOf('}');
        if (startIndex >= 0 && endIndex > startIndex) {
            cleaned = cleaned.substring(startIndex, endIndex + 1);
        }

        cleaned = cleaned.replaceAll(',\\s*}', '}').replaceAll(',\\s*]', ']');
        return cleaned;
    }

    private static DraftData buildFallbackDraft(String accountName, String backgroundContext, String direction) {
        DraftData draft = new DraftData();
        Boolean isInbound = normalizeDirection(direction) == DIRECTION_INBOUND;
        draft.subject = isInbound
            ? 'Re: 供應商回覆與進度更新 - ' + accountName
            : '供應商溝通事項確認 - ' + accountName;
        String safeContext = escapeHtml(backgroundContext);
        if (isInbound) {
            draft.htmlBody =
                '<p>您好，</p>'
                + '<p><br/></p>'
                + '<p>以下回覆目前進度，供後續對齊與追蹤。</p>'
                + '<p><b>背景摘要：</b>' + safeContext + '</p>'
                + '<p>若有需進一步調整之處，請隨時回覆，我方將配合更新。</p>';
        } else {
            draft.htmlBody =
                '<p>各位夥伴您好，</p>'
                + '<p><br/></p>'
                + '<p>以下為本次模擬郵件情境，供活動時間軸展示與測試使用。</p>'
                + '<p><b>背景摘要：</b>' + safeContext + '</p>'
                + '<p>若內容需要調整，可重新輸入不同的模擬背景資料後再次產生。</p>';
        }
        return draft;
    }

    private static String buildFallbackHtmlBody(String accountName, String backgroundContext, String direction) {
        return buildFallbackDraft(accountName, backgroundContext, direction).htmlBody;
    }

    private static List<DateTime> buildMessageDates(Date startDate, Date endDate, Integer count) {
        List<DateTime> results = new List<DateTime>();
        DateTime startDateTime = DateTime.newInstance(startDate, Time.newInstance(9, 0, 0, 0));
        DateTime endDateTime = DateTime.newInstance(endDate, Time.newInstance(18, 0, 0, 0));

        Long totalSeconds = (endDateTime.getTime() - startDateTime.getTime()) / 1000;
        if (totalSeconds < 0) {
            totalSeconds = 0;
        }

        Long stepSeconds = count <= 1 ? 0 : totalSeconds / (count - 1);

        for (Integer index = 0; index < count; index++) {
            DateTime messageDate = startDateTime.addSeconds((Integer) (stepSeconds * index));
            Integer jitterMinutes = Math.mod((index + 1) * 37, 43);
            messageDate = messageDate.addMinutes(jitterMinutes);
            if (messageDate > endDateTime) {
                messageDate = endDateTime.addMinutes(-Math.mod(index * 11, 35));
            }
            results.add(messageDate);
        }

        return results;
    }

    private static String variantSubject(String baseSubject, Integer index, Integer count, Boolean isInbound) {
        if (count <= 1 || index == 0) {
            return baseSubject;
        }

        List<String> suffixes = isInbound
            ? new List<String>{ ' - 回覆', ' - 補充資訊', ' - 進度回報', ' - 確認' }
            : new List<String>{ ' - Follow-up', ' - 時程確認', ' - 後續對齊', ' - 進度更新' };
        String suffix = suffixes[Math.mod(index - 1, suffixes.size())];
        return baseSubject + suffix;
    }

    private static String variantBody(
        String baseHtmlBody,
        String recipientName,
        String currentUserName,
        Integer index,
        Integer count,
        DateTime messageDate,
        Boolean isInbound
    ) {
        String personalizedBody = isInbound
            ? baseHtmlBody.replace('您好，', escapeHtml(currentUserName) + ' 您好，')
            : baseHtmlBody.replace('各位夥伴您好，', escapeHtml(recipientName) + ' 您好，');
        if (count <= 1) {
            return personalizedBody;
        }

        String annotation =
            '<p><br/></p><p><i>模擬郵件 '
            + String.valueOf(index + 1)
            + ' / '
            + String.valueOf(count)
            + ' ｜ 時間：'
            + escapeHtml(messageDate.format('yyyy-MM-dd HH:mm'))
            + '</i></p>';
        return personalizedBody + annotation;
    }

    private static Boolean isInboundEmail(String direction, Integer index) {
        String normalizedDirection = normalizeDirection(direction);
        if (normalizedDirection == DIRECTION_INBOUND) {
            return true;
        }
        if (normalizedDirection == DIRECTION_MIXED) {
            return Math.mod(index, 2) == 1;
        }
        return false;
    }

    private static String directionLabel(String direction) {
        String normalizedDirection = normalizeDirection(direction);
        if (normalizedDirection == DIRECTION_INBOUND) {
            return 'Inbound only';
        }
        if (normalizedDirection == DIRECTION_MIXED) {
            return 'Inbound + Outbound 混合';
        }
        return 'Outbound only';
    }

    private static String resolveBusinessAccountName(String accountName) {
        String normalized = safeString(accountName);
        if (String.isBlank(normalized)) {
            return accountName;
        }
        if (normalized.equalsIgnoreCase('Quincy')) {
            return 'Qualcomm';
        }
        return accountName;
    }

    private static String sanitizeHtml(String htmlBody) {
        if (String.isBlank(htmlBody)) {
            return null;
        }
        String cleaned = htmlBody.replace('<script', '&lt;script').trim();
        if (!cleaned.toLowerCase().contains('<p')) {
            cleaned = '<p>' + escapeHtml(cleaned) + '</p>';
        }
        return cleaned;
    }

    private static String htmlToPlainText(String htmlBody) {
        if (String.isBlank(htmlBody)) {
            return null;
        }

        String plainText = htmlBody
            .replace('<br/>', '\n')
            .replace('<br>', '\n')
            .replace('</p>', '\n')
            .replace('<p>', '')
            .replace('</li>', '\n')
            .replace('<li>', '- ')
            .replace('<ul>', '')
            .replace('</ul>', '')
            .replace('<b>', '')
            .replace('</b>', '')
            .replace('<i>', '')
            .replace('</i>', '');
        return plainText.replaceAll('<[^>]+>', '').trim();
    }

    private static String safeString(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }

    private static String escapeHtml(String value) {
        return value == null ? '' : value.escapeHtml4();
    }
}