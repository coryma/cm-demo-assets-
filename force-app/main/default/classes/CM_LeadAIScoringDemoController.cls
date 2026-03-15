public with sharing class CM_LeadAIScoringDemoController {
    private static final Integer SEARCH_LIMIT = 25;
    private static final String DESCRIPTION_PROMPT_TEMPLATE = 'CM_Lead_Description_Quality_Demo';

    @TestVisible
    private static final List<String> QUALITY_TIERS = new List<String>{
        'Very High',
        'High',
        'Medium',
        'Low',
        'Very Low'
    };

    @TestVisible
    static Map<String, String> testDescriptionByTier;

    @AuraEnabled(cacheable=true)
    public static DemoTargetSummary getDemoTargetSummary() {
        List<Account> targets = [
            SELECT Id, Name, Industry, Website, Description
            FROM Account
            WHERE CM_Is_Demo_Target__c = true
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (targets.isEmpty()) {
            return null;
        }
        return toSummary(targets[0]);
    }

    @AuraEnabled(cacheable=true)
    public static List<LeadOption> searchLeads(String searchTerm) {
        String normalized = searchTerm == null ? '' : searchTerm.trim();
        List<Lead> leads;

        if (String.isBlank(normalized)) {
            leads = [
                SELECT Id, Name, Company, Title, Email, Description, AI_Score__c, AI_Classification__c
                FROM Lead
                WHERE IsDeleted = false
                AND IsConverted = false
                ORDER BY LastModifiedDate DESC
                LIMIT :SEARCH_LIMIT
            ];
        } else {
            String likeTerm = '%' + normalized + '%';
            leads = [
                SELECT Id, Name, Company, Title, Email, Description, AI_Score__c, AI_Classification__c
                FROM Lead
                WHERE IsDeleted = false
                AND IsConverted = false
                AND (
                    Name LIKE :likeTerm
                    OR Company LIKE :likeTerm
                    OR Email LIKE :likeTerm
                    OR Title LIKE :likeTerm
                )
                ORDER BY LastModifiedDate DESC
                LIMIT :SEARCH_LIMIT
            ];
        }

        List<LeadOption> options = new List<LeadOption>();
        for (Lead leadRecord : leads) {
            options.add(toLeadOption(leadRecord));
        }
        return options;
    }

    @AuraEnabled
    public static List<LeadGenerationResult> generateDescriptionsAndScore(List<Id> leadIds) {
        List<Id> orderedLeadIds = normalizeLeadIds(leadIds);
        if (orderedLeadIds.size() != QUALITY_TIERS.size()) {
            throw new AuraHandledException('Please select exactly 5 Leads.');
        }

        Id demoTargetAccountId = getActiveDemoTargetAccountId();
        if (demoTargetAccountId == null) {
            throw new AuraHandledException(
                'Demo target Account is not set. Please configure it in Demo Setup first.'
            );
        }

        Map<Id, Lead> selectedById = new Map<Id, Lead>([
            SELECT Id, Name, Company, Title, Email, Description,
                   AI_Score__c, AI_Classification__c, AI_Reason__c,
                   AI_KeyTopics__c, AI_ReplyRecommendation__c
            FROM Lead
            WHERE Id IN :orderedLeadIds
            AND IsDeleted = false
            AND IsConverted = false
        ]);

        if (selectedById.size() != orderedLeadIds.size()) {
            throw new AuraHandledException(
                'Some selected Leads are unavailable. Please refresh the list and try again.'
            );
        }

        Map<Id, String> qualityByLeadId = new Map<Id, String>();
        List<Lead> descriptionUpdates = new List<Lead>();

        for (Integer i = 0; i < orderedLeadIds.size(); i++) {
            Id leadId = orderedLeadIds[i];
            String qualityTier = QUALITY_TIERS[i];
            Lead leadRecord = selectedById.get(leadId);
            String generatedDescription = generateDescription(leadRecord, demoTargetAccountId, qualityTier);

            qualityByLeadId.put(leadId, qualityTier);
            descriptionUpdates.add(new Lead(
                Id = leadId,
                Description = generatedDescription
            ));
        }

        update descriptionUpdates;

        List<CM_LeadAIScoringInvoker.Requests> scoringRequests =
            new List<CM_LeadAIScoringInvoker.Requests>();
        for (Id leadId : orderedLeadIds) {
            CM_LeadAIScoringInvoker.Requests request = new CM_LeadAIScoringInvoker.Requests();
            request.leadId = leadId;
            scoringRequests.add(request);
        }

        List<CM_LeadAIScoringInvoker.Results> scoringResults =
            CM_LeadAIScoringInvoker.generate(scoringRequests);

        List<Lead> scoringUpdates = new List<Lead>();
        for (Integer i = 0; i < orderedLeadIds.size(); i++) {
            Id leadId = orderedLeadIds[i];
            CM_LeadAIScoringInvoker.Results scoreResult =
                i < scoringResults.size() ? scoringResults[i] : null;

            Lead updateRow = new Lead(Id = leadId);
            updateRow.AI_Classification__c = scoreResult == null ? null : scoreResult.classification;
            updateRow.AI_KeyTopics__c = scoreResult == null ? null : scoreResult.key_topics;
            updateRow.AI_Reason__c = scoreResult == null ? null : scoreResult.reason;
            updateRow.AI_ReplyRecommendation__c = scoreResult == null
                ? null
                : scoreResult.reply_recommendation;
            updateRow.AI_Score__c = scoreResult == null || scoreResult.score == null
                ? null
                : Decimal.valueOf(scoreResult.score);
            scoringUpdates.add(updateRow);
        }

        if (!scoringUpdates.isEmpty()) {
            update scoringUpdates;
        }

        Map<Id, Lead> refreshedById = new Map<Id, Lead>([
            SELECT Id, Name, Company, Description,
                   AI_Score__c, AI_Classification__c, AI_Reason__c,
                   AI_KeyTopics__c, AI_ReplyRecommendation__c
            FROM Lead
            WHERE Id IN :orderedLeadIds
        ]);

        List<LeadGenerationResult> results = new List<LeadGenerationResult>();
        for (Id leadId : orderedLeadIds) {
            Lead leadRecord = refreshedById.get(leadId);
            LeadGenerationResult dto = new LeadGenerationResult();
            dto.id = leadRecord.Id;
            dto.name = leadRecord.Name;
            dto.company = leadRecord.Company;
            dto.qualityTier = qualityByLeadId.get(leadId);
            dto.generatedDescription = leadRecord.Description;
            dto.aiScore = leadRecord.AI_Score__c;
            dto.aiClassification = leadRecord.AI_Classification__c;
            dto.aiReason = leadRecord.AI_Reason__c;
            dto.aiKeyTopics = leadRecord.AI_KeyTopics__c;
            dto.aiReplyRecommendation = leadRecord.AI_ReplyRecommendation__c;
            dto.recordUrl = '/lightning/r/Lead/' + String.valueOf(leadRecord.Id) + '/view';
            results.add(dto);
        }

        return results;
    }

    private static Id getActiveDemoTargetAccountId() {
        List<Account> targets = [
            SELECT Id
            FROM Account
            WHERE CM_Is_Demo_Target__c = true
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return targets.isEmpty() ? null : targets[0].Id;
    }

    private static String generateDescription(Lead leadRecord, Id demoTargetAccountId, String qualityTier) {
        if (Test.isRunningTest() && testDescriptionByTier != null && testDescriptionByTier.containsKey(qualityTier)) {
            return testDescriptionByTier.get(qualityTier);
        }

        String responseText;
        try {
            Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
            inputParams.put('Input:Lead', toSObjectInput(leadRecord.Id));
            inputParams.put('Input:DemoTargetAccount', toSObjectInput(demoTargetAccountId));
            inputParams.put('Input:QualityTier', toPrimitiveInput(qualityTier));

            ConnectApi.EinsteinPromptTemplateGenerationsInput promptInput =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            promptInput.inputParams = inputParams;
            promptInput.isPreview = false;

            ConnectApi.EinsteinLlmAdditionalConfigInput additionalConfig =
                new ConnectApi.EinsteinLlmAdditionalConfigInput();
            additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
            promptInput.additionalConfig = additionalConfig;

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation generationResult =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                    DESCRIPTION_PROMPT_TEMPLATE,
                    promptInput
                );
            if (generationResult != null && generationResult.generations != null && !generationResult.generations.isEmpty()) {
                responseText = generationResult.generations[0].text;
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Lead description generation failed: ' + ex.getMessage());
        }

        String normalized = normalizeGeneratedText(responseText);
        if (String.isBlank(normalized)) {
            return buildFallbackDescription(leadRecord, qualityTier);
        }
        return normalized;
    }

    private static String normalizeGeneratedText(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }

        String normalized = raw.trim();
        if (normalized.startsWith('```')) {
            normalized = normalized.replace('```json', '').replace('```', '').trim();
        }

        if (normalized.startsWith('"') && normalized.endsWith('"') && normalized.length() > 1) {
            normalized = normalized.substring(1, normalized.length() - 1);
        }

        if (normalized.length() > 3000) {
            normalized = normalized.substring(0, 3000);
        }
        return normalized;
    }

    private static String buildFallbackDescription(Lead leadRecord, String qualityTier) {
        String companyName = String.isBlank(leadRecord.Company) ? 'our company' : leadRecord.Company;

        if (qualityTier == 'Very High') {
            return 'We are evaluating a multi-site rollout and need a formal RFQ with pricing, lead time, and sample availability this month. '
                + 'Target project starts next quarter, forecast volume is 12,000 units, and we need technical alignment meetings within two weeks. '
                + 'Please assign a sales owner for immediate follow-up.';
        }
        if (qualityTier == 'High') {
            return 'Our team at ' + companyName + ' is planning a new product program and wants a quote plus solution comparison. '
                + 'Expected demand is 3,000 units in phase one. We can share specifications after an initial discovery call this week.';
        }
        if (qualityTier == 'Medium') {
            return 'We are exploring potential suppliers for an upcoming project and would like to understand your product options, standard lead time, '
                + 'and integration support. Please share basic information and recommended next steps.';
        }
        if (qualityTier == 'Low') {
            return 'Please send product overview materials and general pricing guidance. We are still evaluating internal requirements '
                + 'and do not yet have a confirmed project timeline.';
        }
        return 'Need information. Please share your catalog and contact details.';
    }

    private static ConnectApi.WrappedValue toSObjectInput(Id recordId) {
        Map<String, String> recordRef = new Map<String, String>{
            'id' => String.valueOf(recordId)
        };
        ConnectApi.WrappedValue wrapped = new ConnectApi.WrappedValue();
        wrapped.value = recordRef;
        return wrapped;
    }

    private static ConnectApi.WrappedValue toPrimitiveInput(String value) {
        ConnectApi.WrappedValue wrapped = new ConnectApi.WrappedValue();
        wrapped.value = value;
        return wrapped;
    }

    private static List<Id> normalizeLeadIds(List<Id> leadIds) {
        List<Id> ordered = new List<Id>();
        Set<Id> seen = new Set<Id>();

        if (leadIds == null) {
            return ordered;
        }

        for (Id leadId : leadIds) {
            if (leadId == null || seen.contains(leadId)) {
                continue;
            }
            ordered.add(leadId);
            seen.add(leadId);
        }
        return ordered;
    }

    private static LeadOption toLeadOption(Lead leadRecord) {
        LeadOption option = new LeadOption();
        option.id = leadRecord.Id;
        option.name = leadRecord.Name;
        option.company = leadRecord.Company;
        option.title = leadRecord.Title;
        option.email = leadRecord.Email;
        option.description = leadRecord.Description;
        option.aiScore = leadRecord.AI_Score__c;
        option.aiClassification = leadRecord.AI_Classification__c;
        option.recordUrl = '/lightning/r/Lead/' + String.valueOf(leadRecord.Id) + '/view';
        return option;
    }

    private static DemoTargetSummary toSummary(Account accountRecord) {
        DemoTargetSummary summary = new DemoTargetSummary();
        summary.id = accountRecord.Id;
        summary.name = accountRecord.Name;
        summary.industry = accountRecord.Industry;
        summary.website = accountRecord.Website;
        summary.description = accountRecord.Description;

        List<String> missing = new List<String>();
        if (String.isBlank(accountRecord.Industry)) {
            missing.add('Industry');
        }
        if (String.isBlank(accountRecord.Website)) {
            missing.add('Website');
        }
        if (String.isBlank(accountRecord.Description)) {
            missing.add('Description');
        }

        summary.hasContext = missing.isEmpty();
        summary.missingContext = String.join(missing, ', ');
        return summary;
    }

    public class DemoTargetSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String industry;
        @AuraEnabled public String website;
        @AuraEnabled public String description;
        @AuraEnabled public Boolean hasContext;
        @AuraEnabled public String missingContext;
    }

    public class LeadOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String company;
        @AuraEnabled public String title;
        @AuraEnabled public String email;
        @AuraEnabled public String description;
        @AuraEnabled public Decimal aiScore;
        @AuraEnabled public String aiClassification;
        @AuraEnabled public String recordUrl;
    }

    public class LeadGenerationResult {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String company;
        @AuraEnabled public String qualityTier;
        @AuraEnabled public String generatedDescription;
        @AuraEnabled public Decimal aiScore;
        @AuraEnabled public String aiClassification;
        @AuraEnabled public String aiReason;
        @AuraEnabled public String aiKeyTopics;
        @AuraEnabled public String aiReplyRecommendation;
        @AuraEnabled public String recordUrl;
    }
}
