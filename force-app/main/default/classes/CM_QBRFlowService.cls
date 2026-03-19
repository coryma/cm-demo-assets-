public with sharing class CM_QBRFlowService {

    private static final String DEFAULT_OBJECTIVES = '解決 OTD 爭議、敲定目標價格、確保下一季 Allocation（產能配額）。';
    private static final String DEFAULT_OUTPUT_MODE = 'Internal Briefing';
    private static final String DEFAULT_PRIMARY_FOCUS = 'Allocation';

    public class ContactOption {
        @AuraEnabled public Id contactId;
        @AuraEnabled public String label;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String email;
        @AuraEnabled public String description;
    }

    public class UserOption {
        @AuraEnabled public Id userId;
        @AuraEnabled public String label;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
    }

    public class SendEmailResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Integer recipientCount;
        @AuraEnabled public Integer ccCount;
    }

    public class GenerateRequest {
        @InvocableVariable(required=true)
        public Id accountId;

        @InvocableVariable
        public String quarter;

        @InvocableVariable
        public String meetingDate;

        @InvocableVariable
        public String meetingObjectives;

        @InvocableVariable
        public String outputMode;

        @InvocableVariable
        public String primaryFocus;

        @InvocableVariable
        public String selectedContactIds;

        @InvocableVariable
        public String swotDecision;

        @InvocableVariable
        public String editedStrengthsHtml;

        @InvocableVariable
        public String editedWeaknessesHtml;

        @InvocableVariable
        public String editedOpportunitiesHtml;

        @InvocableVariable
        public String editedThreatsHtml;
    }

    public class GenerateResult {
        @InvocableVariable public Boolean success;
        @InvocableVariable public String statusMessage;
        @InvocableVariable public String briefingHtml;
        @InvocableVariable public String attendeeStrategyHtml;
        @InvocableVariable public String swotHtml;
        @InvocableVariable public String keyTalkingPointsHtml;
        @InvocableVariable public String actionRequestsHtml;
        @InvocableVariable public String emailSubject;
        @InvocableVariable public String emailBody;
    }

    @AuraEnabled(cacheable=true)
    public static List<ContactOption> getAccountContacts(Id accountId) {
        if (accountId == null) {
            return new List<ContactOption>();
        }
        List<ContactOption> options = new List<ContactOption>();
        for (Contact contactRecord : [
            SELECT Id, Name, Title, Email, Description
            FROM Contact
            WHERE AccountId = :accountId
            ORDER BY LastName, FirstName
            LIMIT 200
        ]) {
            options.add(toContactOption(contactRecord));
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<ContactOption> getContactsByIds(List<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            return new List<ContactOption>();
        }
        Map<Id, Contact> contactsById = new Map<Id, Contact>([
            SELECT Id, Name, Title, Email, Description
            FROM Contact
            WHERE Id IN :contactIds
        ]);

        List<ContactOption> options = new List<ContactOption>();
        for (Id contactId : contactIds) {
            if (contactsById.containsKey(contactId)) {
                options.add(toContactOption(contactsById.get(contactId)));
            }
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<UserOption> getActiveUsers() {
        List<UserOption> options = new List<UserOption>();
        for (User userRecord : [
            SELECT Id, Name, Email
            FROM User
            WHERE IsActive = true
              AND Email != null
              AND UserType != 'Guest'
            ORDER BY Name
            LIMIT 200
        ]) {
            options.add(toUserOption(userRecord));
        }
        return options;
    }

    @AuraEnabled
    public static SendEmailResult sendDraftEmail(
        String outputMode,
        String recipientContactIds,
        String recipientUserIds,
        String ccRecipientContactIds,
        String ccRecipientUserIds,
        String emailSubject,
        String emailBody
    ) {
        Boolean useChinese = isChineseLanguage();
        SendEmailResult result = new SendEmailResult();
        result.success = false;
        result.recipientCount = 0;
        result.ccCount = 0;

        if (String.isBlank(emailSubject) || String.isBlank(emailBody)) {
            result.message = useChinese
                ? '郵件主旨與內容皆為必填。'
                : 'Email subject and body are required.';
            return result;
        }

        Set<String> recipientEmails = new Set<String>();
        Set<String> ccEmails = new Set<String>();

        Set<Id> contactIds = parseIds(recipientContactIds);
        if (!contactIds.isEmpty()) {
            for (Contact contactRecord : [
                SELECT Id, Email
                FROM Contact
                WHERE Id IN :contactIds
            ]) {
                if (!String.isBlank(contactRecord.Email)) {
                    recipientEmails.add(contactRecord.Email.trim());
                }
            }
        }

        Set<Id> userIds = parseIds(recipientUserIds);
        if (!userIds.isEmpty()) {
            for (User userRecord : [
                SELECT Id, Email
                FROM User
                WHERE Id IN :userIds
                  AND IsActive = true
            ]) {
                if (!String.isBlank(userRecord.Email)) {
                    recipientEmails.add(userRecord.Email.trim());
                }
            }
        }

        Set<Id> ccContactIds = parseIds(ccRecipientContactIds);
        if (!ccContactIds.isEmpty()) {
            for (Contact contactRecord : [
                SELECT Id, Email
                FROM Contact
                WHERE Id IN :ccContactIds
            ]) {
                if (!String.isBlank(contactRecord.Email)) {
                    String normalizedEmail = contactRecord.Email.trim();
                    if (!recipientEmails.contains(normalizedEmail)) {
                        ccEmails.add(normalizedEmail);
                    }
                }
            }
        }

        Set<Id> ccUserIds = parseIds(ccRecipientUserIds);
        if (!ccUserIds.isEmpty()) {
            for (User userRecord : [
                SELECT Id, Email
                FROM User
                WHERE Id IN :ccUserIds
                  AND IsActive = true
            ]) {
                if (!String.isBlank(userRecord.Email)) {
                    String normalizedEmail = userRecord.Email.trim();
                    if (!recipientEmails.contains(normalizedEmail)) {
                        ccEmails.add(normalizedEmail);
                    }
                }
            }
        }

        if (recipientEmails.isEmpty()) {
            result.message = useChinese
                ? '請至少選擇一位具備電子郵件的收件人。'
                : 'Select at least one recipient with a valid email address.';
            return result;
        }

        Messaging.SingleEmailMessage outbound = new Messaging.SingleEmailMessage();
        outbound.setToAddresses(new List<String>(recipientEmails));
        if (!ccEmails.isEmpty()) {
            outbound.setCcAddresses(new List<String>(ccEmails));
        }
        outbound.setSubject(emailSubject.trim());
        outbound.setHtmlBody(normalizeHtmlBody(emailBody));
        outbound.setPlainTextBody(toPlainTextEmailBody(emailBody));
        outbound.setSaveAsActivity(false);

        try {
            Messaging.SendEmailResult[] sendResults = Messaging.sendEmail(
                new Messaging.SingleEmailMessage[] { outbound }
            );
            if (sendResults != null && !sendResults.isEmpty() && sendResults[0].isSuccess()) {
                result.success = true;
                result.recipientCount = recipientEmails.size();
                result.ccCount = ccEmails.size();
                result.message = useChinese
                    ? '郵件已送出，收件者 ' + String.valueOf(result.recipientCount) + ' 位，副本 ' + String.valueOf(result.ccCount) + ' 位。'
                    : 'Email sent. To: ' + String.valueOf(result.recipientCount) + ', Cc: ' + String.valueOf(result.ccCount) + '.';
                return result;
            }

            String failureMessage = useChinese
                ? '郵件送出失敗。'
                : 'Failed to send the email.';
            if (sendResults != null && !sendResults.isEmpty() && sendResults[0].getErrors() != null) {
                List<String> errors = new List<String>();
                for (Messaging.SendEmailError sendError : sendResults[0].getErrors()) {
                    errors.add(sendError.getMessage());
                }
                if (!errors.isEmpty()) {
                    failureMessage += ' ' + String.join(errors, ' | ');
                }
            }
            result.message = failureMessage;
            return result;
        } catch (Exception ex) {
            result.message = useChinese
                ? '郵件送出失敗：' + ex.getMessage()
                : 'Failed to send the email: ' + ex.getMessage();
            return result;
        }
    }

    private static String normalizeHtmlBody(String emailBody) {
        if (String.isBlank(emailBody)) {
            return '';
        }
        if (Pattern.compile('<[a-zA-Z][^>]*>').matcher(emailBody).find()) {
            return emailBody;
        }
        List<String> paragraphs = new List<String>();
        for (String block : emailBody.split('\\r?\\n\\r?\\n')) {
            if (String.isBlank(block)) {
                continue;
            }
            paragraphs.add('<p>' + EncodingUtil.urlDecode(
                EncodingUtil.urlEncode(block, 'UTF-8'),
                'UTF-8'
            ).escapeHtml4().replace('\r\n', '<br/>').replace('\n', '<br/>') + '</p>');
        }
        return paragraphs.isEmpty() ? '<p></p>' : String.join(paragraphs, '');
    }

    private static String toPlainTextEmailBody(String emailBody) {
        if (String.isBlank(emailBody)) {
            return '';
        }
        String normalized = emailBody
            .replaceAll('(?i)<br\\s*/?>', '\n')
            .replaceAll('(?i)</p>', '\n\n')
            .replaceAll('(?i)</div>', '\n')
            .replaceAll('<[^>]+>', '')
            .replace('&nbsp;', ' ')
            .replace('&amp;', '&')
            .replace('&lt;', '<')
            .replace('&gt;', '>')
            .replace('&quot;', '"')
            .replace('&#39;', '\'');
        return normalized.trim();
    }

    @InvocableMethod(label='Generate QBR Briefing' description='Build structured QBR analysis and a draft email package for the selected Account contacts')
    public static List<GenerateResult> generateBriefing(List<GenerateRequest> requests) {
        List<GenerateResult> results = new List<GenerateResult>();
        Boolean useChinese = isChineseLanguage();
        if (requests == null || requests.isEmpty()) {
            GenerateResult emptyResult = new GenerateResult();
            emptyResult.success = false;
            emptyResult.statusMessage = useChinese ? '未收到 QBR 請求資料。' : 'No QBR request payload.';
            results.add(emptyResult);
            return results;
        }

        Set<Id> accountIds = new Set<Id>();
        for (GenerateRequest request : requests) {
            if (request != null && request.accountId != null) {
                accountIds.add(request.accountId);
            }
        }

        Map<Id, Account> accountsById = accountIds.isEmpty()
            ? new Map<Id, Account>()
            : new Map<Id, Account>([
                SELECT Id, Name, Industry, Description, Website
                FROM Account
                WHERE Id IN :accountIds
            ]);

        Map<Id, List<Contact>> contactsByAccountId = new Map<Id, List<Contact>>();
        if (!accountIds.isEmpty()) {
            for (Contact contactRecord : [
                SELECT Id, AccountId, Name, Title, Email, Description
                FROM Contact
                WHERE AccountId IN :accountIds
                ORDER BY LastName, FirstName
                LIMIT 1000
            ]) {
                List<Contact> bucket = contactsByAccountId.get(contactRecord.AccountId);
                if (bucket == null) {
                    bucket = new List<Contact>();
                    contactsByAccountId.put(contactRecord.AccountId, bucket);
                }
                bucket.add(contactRecord);
            }
        }

        Map<Id, AccountPlan> latestPlanByAccountId = new Map<Id, AccountPlan>();
        if (!accountIds.isEmpty()) {
            for (AccountPlan plan : [
                SELECT Id, AccountId, Name, RelationshipStrengths, RelationshipWeaknesses,
                       RelationshipOpportunities, RelationshipThreats
                FROM AccountPlan
                WHERE AccountId IN :accountIds
                ORDER BY AccountId, LastModifiedDate DESC
                LIMIT 200
            ]) {
                if (!latestPlanByAccountId.containsKey(plan.AccountId)) {
                    latestPlanByAccountId.put(plan.AccountId, plan);
                }
            }
        }

        for (GenerateRequest request : requests) {
            GenerateResult result = new GenerateResult();
            result.success = false;
            result.statusMessage = useChinese ? '無法產生 QBR 草稿。' : 'Unable to generate QBR draft.';

            if (request == null || request.accountId == null || !accountsById.containsKey(request.accountId)) {
                result.statusMessage = useChinese ? '找不到 Account。' : 'Account not found.';
                results.add(result);
                continue;
            }

            Account accountRecord = accountsById.get(request.accountId);
            List<Contact> availableContacts = contactsByAccountId.containsKey(request.accountId)
                ? contactsByAccountId.get(request.accountId)
                : new List<Contact>();
            List<Contact> selectedContacts = selectContacts(availableContacts, request.selectedContactIds);
            if (selectedContacts.isEmpty()) {
                selectedContacts.addAll(availableContacts);
            }

            AccountPlan accountPlan = latestPlanByAccountId.get(request.accountId);
            String quarter = String.isBlank(request.quarter) ? deriveQuarterLabel(Date.today()) : request.quarter.trim();
            String meetingDate = String.isBlank(request.meetingDate) ? String.valueOf(Date.today()) : request.meetingDate.trim();
            String meetingObjectives = String.isBlank(request.meetingObjectives)
                ? DEFAULT_OBJECTIVES
                : request.meetingObjectives.trim();
            String outputMode = normalizeOutputMode(request.outputMode);
            String primaryFocus = normalizePrimaryFocus(request.primaryFocus);
            String swotDecision = normalizeSwotDecision(request.swotDecision);
            String strengthsHtml = swotDecision == 'SKIP'
                ? null
                : pickSwotOverride(request.editedStrengthsHtml, accountPlan == null ? null : accountPlan.RelationshipStrengths);
            String weaknessesHtml = swotDecision == 'SKIP'
                ? null
                : pickSwotOverride(request.editedWeaknessesHtml, accountPlan == null ? null : accountPlan.RelationshipWeaknesses);
            String opportunitiesHtml = swotDecision == 'SKIP'
                ? null
                : pickSwotOverride(request.editedOpportunitiesHtml, accountPlan == null ? null : accountPlan.RelationshipOpportunities);
            String threatsHtml = swotDecision == 'SKIP'
                ? null
                : pickSwotOverride(request.editedThreatsHtml, accountPlan == null ? null : accountPlan.RelationshipThreats);

            result.attendeeStrategyHtml = buildAttendeeStrategyHtml(selectedContacts, primaryFocus, useChinese);
            result.swotHtml = buildSwotHtml(
                strengthsHtml,
                weaknessesHtml,
                opportunitiesHtml,
                threatsHtml,
                useChinese
            );
            result.keyTalkingPointsHtml = buildKeyTalkingPointsHtml(
                accountRecord,
                quarter,
                meetingDate,
                meetingObjectives,
                primaryFocus,
                outputMode,
                useChinese
            );
            result.actionRequestsHtml = buildActionRequestsHtml(primaryFocus, outputMode, useChinese);
            result.briefingHtml = buildBriefingHtml(
                accountRecord,
                quarter,
                meetingDate,
                meetingObjectives,
                outputMode,
                primaryFocus,
                result.attendeeStrategyHtml,
                result.swotHtml,
                result.keyTalkingPointsHtml,
                result.actionRequestsHtml,
                useChinese
            );
            result.emailSubject = buildEmailSubject(accountRecord, quarter, outputMode, useChinese);
            result.emailBody = buildEmailBody(
                accountRecord,
                selectedContacts,
                quarter,
                meetingDate,
                meetingObjectives,
                outputMode,
                primaryFocus,
                result.keyTalkingPointsHtml,
                result.actionRequestsHtml,
                useChinese
            );
            result.success = true;
            result.statusMessage = useChinese
                ? 'QBR 分析已完成。請確認內容、選擇收件人，並在同一步驟送出郵件。'
                : 'QBR analysis is ready. Confirm the content, choose recipients, and send the email from the same step.';
            results.add(result);
        }

        return results;
    }

    private static ContactOption toContactOption(Contact contactRecord) {
        ContactOption option = new ContactOption();
        option.contactId = contactRecord.Id;
        option.name = contactRecord.Name;
        option.title = contactRecord.Title;
        option.email = contactRecord.Email;
        option.description = contactRecord.Description;
        option.label = contactRecord.Name
            + (String.isBlank(contactRecord.Title) ? '' : ' | ' + contactRecord.Title)
            + (String.isBlank(contactRecord.Email) ? '' : ' | ' + contactRecord.Email);
        return option;
    }

    private static UserOption toUserOption(User userRecord) {
        UserOption option = new UserOption();
        option.userId = userRecord.Id;
        option.name = userRecord.Name;
        option.email = userRecord.Email;
        option.label = userRecord.Name
            + (String.isBlank(userRecord.Email) ? '' : ' | ' + userRecord.Email);
        return option;
    }

    private static List<Contact> selectContacts(List<Contact> availableContacts, String selectedContactIds) {
        if (availableContacts == null || availableContacts.isEmpty()) {
            return new List<Contact>();
        }

        Set<Id> selectedIds = parseIds(selectedContactIds);
        if (selectedIds.isEmpty()) {
            return new List<Contact>();
        }

        List<Contact> selectedContacts = new List<Contact>();
        for (Contact contactRecord : availableContacts) {
            if (selectedIds.contains(contactRecord.Id)) {
                selectedContacts.add(contactRecord);
            }
        }
        return selectedContacts;
    }

    private static Set<Id> parseIds(String rawIds) {
        Set<Id> ids = new Set<Id>();
        if (String.isBlank(rawIds)) {
            return ids;
        }
        String normalized = rawIds.replace(',', ';');
        for (String token : normalized.split(';')) {
            String candidate = token == null ? null : token.trim();
            if (String.isBlank(candidate)) {
                continue;
            }
            try {
                ids.add((Id) candidate);
            } catch (Exception ignored) {
                // Ignore malformed ids from UI payloads.
            }
        }
        return ids;
    }

    private static String normalizeOutputMode(String outputMode) {
        if (String.isBlank(outputMode)) {
            return DEFAULT_OUTPUT_MODE;
        }
        String normalized = outputMode.trim();
        if (normalized == 'External Agenda') {
            return normalized;
        }
        return DEFAULT_OUTPUT_MODE;
    }

    private static String normalizePrimaryFocus(String primaryFocus) {
        if (String.isBlank(primaryFocus)) {
            return DEFAULT_PRIMARY_FOCUS;
        }
        String normalized = primaryFocus.trim();
        Set<String> supported = new Set<String>{
            'OTD', 'Pricing', 'Allocation', 'VMI', 'Supply Risk', 'Exec Alignment'
        };
        return supported.contains(normalized) ? normalized : DEFAULT_PRIMARY_FOCUS;
    }

    private static String normalizeSwotDecision(String swotDecision) {
        if (String.isBlank(swotDecision)) {
            return 'USE_CURRENT';
        }
        String normalized = swotDecision.trim();
        Set<String> supported = new Set<String>{ 'USE_CURRENT', 'REGENERATE', 'SKIP' };
        return supported.contains(normalized) ? normalized : 'USE_CURRENT';
    }

    private static Boolean isChineseLanguage() {
        String language = UserInfo.getLanguage();
        return !String.isBlank(language) && language.toLowerCase().startsWith('zh');
    }

    private static String displayOutputMode(String outputMode, Boolean useChinese) {
        if (outputMode == 'External Agenda') {
            return useChinese ? '外部議程' : 'External Agenda';
        }
        return useChinese ? '內部簡報' : 'Internal Briefing';
    }

    private static String displayPrimaryFocus(String primaryFocus, Boolean useChinese) {
        if (!useChinese) {
            return primaryFocus;
        }
        if (primaryFocus == 'OTD') {
            return '交付達成率 (OTD)';
        }
        if (primaryFocus == 'Pricing') {
            return '價格';
        }
        if (primaryFocus == 'Allocation') {
            return '配額';
        }
        if (primaryFocus == 'VMI') {
            return 'VMI';
        }
        if (primaryFocus == 'Supply Risk') {
            return '供應風險';
        }
        if (primaryFocus == 'Exec Alignment') {
            return '高層對齊';
        }
        return primaryFocus;
    }

    private static String deriveQuarterLabel(Date sourceDate) {
        Integer quarterNumber = ((sourceDate.month() - 1) / 3) + 1;
        return String.valueOf(sourceDate.year()) + ' Q' + String.valueOf(quarterNumber);
    }

    private static String buildAttendeeStrategyHtml(List<Contact> contacts, String primaryFocus, Boolean useChinese) {
        if (contacts == null || contacts.isEmpty()) {
            return useChinese
                ? '<ul><li>尚未選擇外部與會者。發送前請至少選擇一位帳戶聯絡人。</li></ul>'
                : '<ul><li>No external attendees selected. Add at least one account contact before distributing the final package.</li></ul>';
        }

        String html = '<ul>';
        for (Contact contactRecord : contacts) {
            html += '<li><b>' + escapeHtml(contactRecord.Name) + '</b>';
            if (!String.isBlank(contactRecord.Title)) {
                html += ' (' + escapeHtml(contactRecord.Title) + ')';
            }
            html += '<br/>' + escapeHtml(resolveRoleGuidance(contactRecord.Title, useChinese));
            html += '<br/><b>'
                + (useChinese ? '談判切入點' : 'Negotiation angle')
                + ':</b> '
                + escapeHtml(resolvePrimaryFocusGuidance(primaryFocus, useChinese));
            if (!String.isBlank(contactRecord.Description)) {
                html += '<br/><b>'
                    + (useChinese ? '既有背景' : 'Stored context')
                    + ':</b> '
                    + escapeHtml(contactRecord.Description);
            }
            html += '</li>';
        }
        html += '</ul>';
        return html;
    }

    private static String buildSwotHtml(
        String strengthsHtml,
        String weaknessesHtml,
        String opportunitiesHtml,
        String threatsHtml,
        Boolean useChinese
    ) {
        String html = '';
        html += '<p><b>' + (useChinese ? '優勢' : 'Strengths') + '</b></p>' + coalesceHtml(
            strengthsHtml,
            useChinese
                ? '<ul><li>以既有合作覆蓋、design-in 紀錄與 forecast 槓桿作為高層對齊的核心基礎。</li></ul>'
                : '<ul><li>Use existing relationship coverage, design-in history, and forecast leverage as the anchor for executive alignment.</li></ul>'
        );
        html += '<p><b>' + (useChinese ? '劣勢' : 'Weaknesses') + '</b></p>' + coalesceHtml(
            weaknessesHtml,
            useChinese
                ? '<ul><li>先整理交付、成本或驗證缺口的硬數據，讓會議維持在事實與責任歸屬上。</li></ul>'
                : '<ul><li>Document exact delivery, cost, or qualification gaps so the meeting stays fact-based.</li></ul>'
        );
        html += '<p><b>' + (useChinese ? '機會' : 'Opportunities') + '</b></p>' + coalesceHtml(
            opportunitiesHtml,
            useChinese
                ? '<ul><li>把本次 QBR 轉成與量能綁定的價格、供應保證或 VMI 承諾。</li></ul>'
                : '<ul><li>Convert the QBR into concrete pricing, supply assurance, or VMI commitments tied to volume.</li></ul>'
        );
        html += '<p><b>' + (useChinese ? '威脅' : 'Threats') + '</b></p>' + coalesceHtml(
            threatsHtml,
            useChinese
                ? '<ul><li>持續警戒配額壓力、上游缺料與跨區物流延遲，避免影響實際出貨執行。</li></ul>'
                : '<ul><li>Watch allocation pressure, upstream shortages, and cross-region logistics delays that can derail execution.</li></ul>'
        );
        return html;
    }

    private static String buildKeyTalkingPointsHtml(
        Account accountRecord,
        String quarter,
        String meetingDate,
        String meetingObjectives,
        String primaryFocus,
        String outputMode,
        Boolean useChinese
    ) {
        String businessAccountName = resolveBusinessAccountName(accountRecord == null ? null : accountRecord.Name);
        String html = '<ul>';
        if (useChinese) {
            html += '<li><b>會議框架:</b> ' + escapeHtml(quarter) + ' 與 ' + escapeHtml(businessAccountName) + ' 的 QBR，預定於 ' + escapeHtml(meetingDate) + ' 進行。</li>';
            html += '<li><b>核心焦點:</b> 先圍繞「' + escapeHtml(displayPrimaryFocus(primaryFocus, true)) + '」進行硬數據討論，再延伸至合作層面的訊息。</li>';
            html += '<li><b>會議目標:</b> ' + escapeHtml(meetingObjectives) + '</li>';
            html += '<li><b>建議順序:</b> 先對齊爭議數字，再進入商務訴求，最後鎖定責任人與追蹤時程。</li>';
        } else {
            html += '<li><b>Meeting frame:</b> ' + escapeHtml(quarter) + ' QBR on ' + escapeHtml(meetingDate) + ' for ' + escapeHtml(businessAccountName) + '.</li>';
            html += '<li><b>Primary focus:</b> ' + escapeHtml(displayPrimaryFocus(primaryFocus, false)) + ' should drive the first hard-data discussion before broader partnership messaging.</li>';
            html += '<li><b>Objectives:</b> ' + escapeHtml(meetingObjectives) + '</li>';
            html += '<li><b>Suggested order:</b> Start with disputed numbers, move into commercial asks, then lock owner-based follow-up items.</li>';
        }
        if (outputMode == 'External Agenda') {
            html += useChinese
                ? '<li><b>郵件口徑:</b> 對外草稿必須維持中性、聚焦執行，不揭露內部籌碼、底線或談判註記。</li>'
                : '<li><b>Email posture:</b> Keep the draft neutral and execution-focused. Do not expose internal leverage, guardrails, or negotiation notes.</li>';
        } else {
            html += useChinese
                ? '<li><b>郵件口徑:</b> 此草稿僅供內部使用，需明確標示決策權、升級路徑與備援立場。</li>'
                : '<li><b>Email posture:</b> Treat the draft as internal-only. Call out decision rights, escalation paths, and fallback positions.</li>';
        }
        if (!String.isBlank(accountRecord.Description)) {
            html += '<li><b>' + (useChinese ? '帳戶背景' : 'Account context') + ':</b> ' + escapeHtml(accountRecord.Description) + '</li>';
        }
        html += '</ul>';
        return html;
    }

    private static String buildActionRequestsHtml(String primaryFocus, String outputMode, Boolean useChinese) {
        List<String> asks = new List<String>();
        asks.add(
            useChinese
                ? '確認一位具名高層負責會後決策與升級追蹤。'
                : 'Confirm one named executive owner for post-QBR decisions and escalation follow-through.'
        );

        if (primaryFocus == 'OTD') {
            asks.add(useChinese
                ? '在下次檢討週期前，先對齊 OTD 爭議計分方式與單一事實來源。'
                : 'Reconcile the disputed OTD scorecard and agree the source-of-truth logic before the next review cycle.');
            asks.add(useChinese
                ? '針對延遲出貨提出改善計畫，包含在途、標籤錯誤與清關風險的控管作法。'
                : 'Commit to a corrective action plan for late shipments, including transit or label-error containment.');
        } else if (primaryFocus == 'Pricing') {
            asks.add(useChinese
                ? '提出可彌補現有目標價差的價格路徑，包含前端降價或後端 rebate 結構。'
                : 'Present a price path that closes the current target gap, including any front-end cost down or back-end rebate structure.');
            asks.add(useChinese
                ? '明確定義啟動高層價格核准所需的數量或 forecast 門檻。'
                : 'Define the volume or forecast thresholds required to unlock executive pricing approval.');
        } else if (primaryFocus == 'VMI') {
            asks.add(useChinese
                ? '確認各廠區、各料別所需的最低 VMI 或 Hub 庫存覆蓋。'
                : 'Confirm the minimum VMI or hub stock coverage by site and by material family.');
            asks.add(useChinese
                ? '釐清過渡期間額外運費與 buffer 庫存成本由哪一方吸收。'
                : 'Document who absorbs incremental freight or buffer carrying cost during the transition period.');
        } else if (primaryFocus == 'Supply Risk') {
            asks.add(useChinese
                ? '揭露目前最關鍵的上游缺料或配額風險，並指派應變負責人。'
                : 'Surface the top upstream shortage or allocation risks and assign owners for contingency planning.');
            asks.add(useChinese
                ? '定義替代料、加急與高層升級的啟動條件。'
                : 'Agree the trigger points for substitution, expedite, or executive escalation.');
        } else if (primaryFocus == 'Exec Alignment') {
            asks.add(useChinese
                ? '利用高層對談段落，鎖定價格、供應與升級機制的跨部門承諾。'
                : 'Use the executive segment to secure cross-functional commitment on pricing, supply, and escalation behavior.');
            asks.add(useChinese
                ? '在會議結束前先敲定下一次 checkpoint 日期。'
                : 'Lock the next checkpoint date before the meeting closes.');
        } else {
            asks.add(useChinese
                ? '確認下一季配額覆蓋，以及哪些條件會改變供應承諾。'
                : 'Confirm next-quarter allocation coverage and the conditions that would change the supply commitment.');
            asks.add(useChinese
                ? '設定維持配額優先權所需的 forecast 週期與更新節奏。'
                : 'Set the forecast horizon and cadence required to preserve allocation priority.');
        }

        if (outputMode == 'External Agenda') {
            asks.add(useChinese
                ? '對外寄送前，先將上述內容轉成中性議程項目。'
                : 'Translate these items into neutral agenda points before sharing externally.');
        } else {
            asks.add(useChinese
                ? '在內部預讀稿中明確標示談判底線，確保 WNC 團隊採取一致立場。'
                : 'Keep internal negotiation guardrails explicit in the pre-read so the WNC team uses one consistent position.');
        }

        String html = '<ul>';
        for (String ask : asks) {
            html += '<li>' + escapeHtml(ask) + '</li>';
        }
        html += '</ul>';
        return html;
    }

    private static String buildBriefingHtml(
        Account accountRecord,
        String quarter,
        String meetingDate,
        String meetingObjectives,
        String outputMode,
        String primaryFocus,
        String attendeeStrategyHtml,
        String swotHtml,
        String keyTalkingPointsHtml,
        String actionRequestsHtml,
        Boolean useChinese
    ) {
        String businessAccountName = resolveBusinessAccountName(accountRecord == null ? null : accountRecord.Name);
        String html = '';
        if (useChinese) {
            html += '<p><b>【僅供內部】' + escapeHtml(quarter) + ' ' + escapeHtml(businessAccountName) + ' QBR 會前簡報</b></p>';
            html += '<p><b>文件擁有者:</b> WNC 全球供應鏈管理<br/>';
            html += '<b>會議日期:</b> ' + escapeHtml(meetingDate) + '<br/>';
            html += '<b>會議目標:</b> ' + escapeHtml(meetingObjectives) + '<br/>';
            html += '<b>輸出模式:</b> ' + escapeHtml(displayOutputMode(outputMode, true)) + '<br/>';
            html += '<b>核心焦點:</b> ' + escapeHtml(displayPrimaryFocus(primaryFocus, true)) + '</p>';
            html += '<p><b>與會者策略</b></p>' + attendeeStrategyHtml;
            html += '<p><b>策略 SWOT</b></p>' + swotHtml;
            html += '<p><b>關鍵談判重點</b></p>' + keyTalkingPointsHtml;
            html += '<p><b>要求事項</b></p>' + actionRequestsHtml;
            return html;
        }

        html += '<p><b>[Internal Only] ' + escapeHtml(quarter) + ' ' + escapeHtml(businessAccountName) + ' QBR Briefing</b></p>';
        html += '<p><b>Document Owner:</b> WNC Global Supply Chain Management<br/>';
        html += '<b>Meeting Date:</b> ' + escapeHtml(meetingDate) + '<br/>';
        html += '<b>Meeting Objectives:</b> ' + escapeHtml(meetingObjectives) + '<br/>';
        html += '<b>Output Mode:</b> ' + escapeHtml(displayOutputMode(outputMode, false)) + '<br/>';
        html += '<b>Primary Focus:</b> ' + escapeHtml(displayPrimaryFocus(primaryFocus, false)) + '</p>';
        html += '<p><b>Attendee Strategy</b></p>' + attendeeStrategyHtml;
        html += '<p><b>Strategic SWOT</b></p>' + swotHtml;
        html += '<p><b>Key Talking Points</b></p>' + keyTalkingPointsHtml;
        html += '<p><b>Action Requests</b></p>' + actionRequestsHtml;
        return html;
    }

    private static String buildEmailSubject(Account accountRecord, String quarter, String outputMode, Boolean useChinese) {
        String displayAccountName = accountRecord == null ? '' : accountRecord.Name;
        if (outputMode == 'External Agenda') {
            return useChinese
                ? quarter + ' ' + displayAccountName + ' QBR 議程'
                : quarter + ' ' + displayAccountName + ' QBR Agenda';
        }
        return useChinese
            ? '【僅供內部】' + quarter + ' ' + displayAccountName + ' QBR 會前準備'
            : '[Internal Only] ' + quarter + ' ' + displayAccountName + ' QBR Preparation';
    }

    private static String buildEmailBody(
        Account accountRecord,
        List<Contact> selectedContacts,
        String quarter,
        String meetingDate,
        String meetingObjectives,
        String outputMode,
        String primaryFocus,
        String keyTalkingPointsHtml,
        String actionRequestsHtml,
        Boolean useChinese
    ) {
        String displayAccountName = accountRecord == null ? '' : accountRecord.Name;
        String doubleBreak = '<p><br/></p><p><br/></p>';
        if (outputMode == 'External Agenda') {
            String html = '';
            if (useChinese) {
                html += '<p>各位好，</p>';
                html += doubleBreak;
                html += '<p>以下為即將與 ' + escapeHtml(displayAccountName) + ' 進行 ' + escapeHtml(quarter) + ' QBR 的建議議程草稿。</p>';
                html += '<p><b>會議日期：</b>' + escapeHtml(meetingDate) + '<br/>';
                html += '<b>核心焦點：</b>' + escapeHtml(displayPrimaryFocus(primaryFocus, true)) + '</p>';
                html += '<p><b>議程重點</b></p>';
                html += '<ul>';
                html += '<li>檢視目前營運表現，以及尚未結案的交付或品質議題。</li>';
                html += '<li>對齊支撐下一季計畫所需的商務條件。</li>';
                html += '<li>確認供應、物流與行動項目的責任歸屬。</li>';
                html += '</ul>';
            } else {
                html += '<p>Team,</p>';
                html += doubleBreak;
                html += '<p>Please find the proposed agenda for the upcoming ' + escapeHtml(quarter) + ' QBR with ' + escapeHtml(displayAccountName) + '.</p>';
                html += '<p><b>Meeting Date:</b> ' + escapeHtml(meetingDate) + '<br/>';
                html += '<b>Primary Focus:</b> ' + escapeHtml(displayPrimaryFocus(primaryFocus, false)) + '</p>';
                html += '<p><b>Agenda Highlights</b></p>';
                html += '<ul>';
                html += '<li>Review current operating performance and any open delivery or quality issues.</li>';
                html += '<li>Align the commercial path needed to support the next quarter plan.</li>';
                html += '<li>Confirm supply, logistics, and action-owner follow-through.</li>';
                html += '</ul>';
            }
            if (selectedContacts != null && !selectedContacts.isEmpty()) {
                html += '<p><b>' + (useChinese ? '預計與會者' : 'Planned Attendees') + '</b></p><ul>';
                for (Contact contactRecord : selectedContacts) {
                    String attendeeLine = escapeHtml(contactRecord.Name);
                    if (!String.isBlank(contactRecord.Title)) {
                        attendeeLine += ' (' + escapeHtml(contactRecord.Title) + ')';
                    }
                    html += '<li>' + attendeeLine + '</li>';
                }
                html += '</ul>';
            }
            html += '<p><b>' + (useChinese ? '會議目標' : 'Objectives') + '：</b>' + escapeHtml(meetingObjectives) + '</p>';
            html += '<p>' + (useChinese ? '敬上' : 'Regards,') + '<br/>' + (useChinese ? 'WNC 全球供應鏈管理' : 'WNC Global Supply Chain Management') + '</p>';
            return html;
        }

        String html = '';
        if (useChinese) {
            html += '<p>各位好，</p>';
            html += doubleBreak;
            html += '<p>請先檢視 ' + escapeHtml(displayAccountName) + ' 的內部 QBR 會前準備資料。</p>';
            html += doubleBreak;
            html += '<p><b>季度：</b>' + escapeHtml(quarter) + '<br/>';
            html += '<b>會議日期：</b>' + escapeHtml(meetingDate) + '<br/>';
            html += '<b>核心焦點：</b>' + escapeHtml(displayPrimaryFocus(primaryFocus, true)) + '<br/>';
            html += '<b>會議目標：</b>' + escapeHtml(meetingObjectives) + '</p>';
            html += doubleBreak;
            html += '<p><b>與會者策略</b></p>';
        } else {
            html += '<p>Team,</p>';
            html += doubleBreak;
            html += '<p>Please review the internal QBR preparation package for ' + escapeHtml(displayAccountName) + '.</p>';
            html += doubleBreak;
            html += '<p><b>Quarter:</b> ' + escapeHtml(quarter) + '<br/>';
            html += '<b>Meeting Date:</b> ' + escapeHtml(meetingDate) + '<br/>';
            html += '<b>Primary Focus:</b> ' + escapeHtml(displayPrimaryFocus(primaryFocus, false)) + '<br/>';
            html += '<b>Objectives:</b> ' + escapeHtml(meetingObjectives) + '</p>';
            html += doubleBreak;
            html += '<p><b>Attendee Strategy</b></p>';
        }
        html += '<ul>';
        if (selectedContacts == null || selectedContacts.isEmpty()) {
            html += '<li>' + (useChinese ? '尚未選擇外部與會者。' : 'No external attendees selected.') + '</li>';
        } else {
            for (Contact contactRecord : selectedContacts) {
                String attendeeLine = escapeHtml(contactRecord.Name);
                if (!String.isBlank(contactRecord.Title)) {
                    attendeeLine += ' (' + escapeHtml(contactRecord.Title) + ')';
                }
                if (!String.isBlank(contactRecord.Description)) {
                    attendeeLine += ': ' + escapeHtml(contactRecord.Description);
                }
                html += '<li>' + attendeeLine + '</li>';
            }
        }
        html += '</ul>';
        html += '<p><b>' + (useChinese ? '關鍵談判重點' : 'Key Talking Points') + '</b></p>';
        html += coalesceHtml(
            keyTalkingPointsHtml,
            useChinese
                ? '<ul><li>先用爭議數據對齊事實，再收斂商務與營運訴求。</li></ul>'
                : '<ul><li>Use disputed metrics first, then align on commercial and operational asks.</li></ul>'
        );
        html += '<p><b>' + (useChinese ? '要求事項' : 'Action Requests') + '</b></p>';
        html += coalesceHtml(
            actionRequestsHtml,
            useChinese
                ? '<ul><li>離開會議前要鎖定責任人、明確訴求與目標日期。</li></ul>'
                : '<ul><li>Leave with named owners, explicit asks, and target dates.</li></ul>'
        );
        html += '<p>' + (useChinese ? '敬上' : 'Regards,') + '<br/>' + (useChinese ? 'WNC 全球供應鏈管理' : 'WNC Global Supply Chain Management') + '</p>';
        return html;
    }

    private static String resolveRoleGuidance(String title, Boolean useChinese) {
        String normalized = String.isBlank(title) ? '' : title.toLowerCase();
        if (normalized.contains('vp') || normalized.contains('vice president') || normalized.contains('副總')) {
            return useChinese
                ? '多半是高層核准者。對話要拉到商業影響與戰略合作層級。'
                : 'Likely executive approver. Keep the discussion at the business-impact and partnership level.';
        }
        if (normalized.contains('director') || normalized.contains('總監')) {
            return useChinese
                ? '偏向商務主責。通常會緊盯價格結構、毛利與 forecast 品質。'
                : 'Commercial owner. Expect strong focus on pricing structure, margin, and forecast quality.';
        }
        if (normalized.contains('operation') || normalized.contains('operations') || normalized.contains('pm')
            || normalized.contains('program') || normalized.contains('營運') || normalized.contains('供應')
            || normalized.contains('協理') || normalized.contains('經理')) {
            return useChinese
                ? '偏向執行端關鍵角色。應以交期、lead time、物流與規格缺口的硬數據溝通。'
                : 'Execution stakeholder. Use hard facts on delivery, lead time, logistics, and specification gaps.';
        }
        return useChinese
            ? '先確認對方決策權，再依價格、供應與執行責任分工調整談法。'
            : 'Confirm decision rights early, then tailor the discussion to pricing, supply, and execution ownership.';
    }

    private static String resolvePrimaryFocusGuidance(String primaryFocus, Boolean useChinese) {
        if (primaryFocus == 'OTD') {
            return useChinese
                ? '先拿出 scorecard 證據、出貨里程碑與 Incoterm 責任，再談讓步空間。'
                : 'Lead with scorecard evidence, shipment milestones, and incoterm responsibility before discussing concessions.';
        }
        if (primaryFocus == 'Pricing') {
            return useChinese
                ? '以整機成本、目標價差與哪些數量能換到更好價格作為談判主軸。'
                : 'Anchor on total system cost, required target price gap, and what volume unlocks better economics.';
        }
        if (primaryFocus == 'VMI') {
            return useChinese
                ? '要求明確的 Hub 覆蓋週數、補貨節奏與運費責任歸屬。'
                : 'Push for explicit hub coverage, replenishment timing, and freight ownership.';
        }
        if (primaryFocus == 'Supply Risk') {
            return useChinese
                ? '提早升級上游缺料、替代方案與應變機制的啟動條件。'
                : 'Escalate upstream shortages, substitution paths, and contingency triggers early.';
        }
        if (primaryFocus == 'Exec Alignment') {
            return useChinese
                ? '利用高層贊助推動跨部門決策，避免問題停留在每週例會打轉。'
                : 'Use executive sponsorship to force cross-functional decisions instead of letting issues stall in weekly syncs.';
        }
        return useChinese
            ? '聚焦 forecast 可信度、配額覆蓋與會改變供應優先順序的條件。'
            : 'Focus on forecast credibility, allocation coverage, and the conditions that can change supply priority.';
    }

    private static String coalesceHtml(String sourceHtml, String fallbackHtml) {
        return String.isBlank(sourceHtml) ? fallbackHtml : sourceHtml;
    }

    private static String pickSwotOverride(String overrideHtml, String fallbackHtml) {
        if (overrideHtml == null) {
            return fallbackHtml;
        }
        return overrideHtml;
    }

    private static String resolveBusinessAccountName(String accountName) {
        if (String.isBlank(accountName)) {
            return '';
        }
        String normalized = accountName.trim();
        if (normalized.equalsIgnoreCase('Quincy')) {
            return 'Qualcomm';
        }
        return normalized;
    }

    private static String summarizeHtml(String sourceHtml, String fallbackText) {
        if (String.isBlank(sourceHtml)) {
            return fallbackText;
        }
        String normalized = sourceHtml;
        normalized = normalized.replace('<br/>', '\n').replace('<br />', '\n').replace('<br>', '\n');
        normalized = normalized.replace('</li>', '\n').replace('<li>', '- ');
        normalized = normalized.replace('</p>', '\n').replace('<p>', '');
        normalized = normalized.replaceAll('<[^>]+>', ' ');
        normalized = normalized.replace('&nbsp;', ' ').replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>');
        normalized = normalized.replaceAll('[\u00A0\u2007\u202F]', ' ');
        normalized = normalized.replaceAll(' +', ' ').trim();
        if (normalized.length() > 220) {
            normalized = normalized.substring(0, 217) + '...';
        }
        return normalized;
    }

    private static String escapeHtml(String input) {
        if (input == null) {
            return '';
        }
        return input
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;')
            .replace('\'', '&#39;');
    }
}