public with sharing class CM_LeadAIScoringInvoker {
    private static final String PROMPT_TEMPLATE_NAME = 'CM_Lead_Auto_Screening_Demo';

    @TestVisible
    static String testPromptResponse;

    @InvocableMethod(label='Generate Lead AI Scoring')
    public static List<Results> generate(List<Requests> requests) {
        List<Results> output = new List<Results>();
        if (requests == null || requests.isEmpty()) {
            return output;
        }

        Set<Id> leadIds = new Set<Id>();
        for (Requests request : requests) {
            if (request != null && request.leadId != null) {
                leadIds.add(request.leadId);
            }
        }

        Map<Id, Lead> leadsById = leadIds.isEmpty()
            ? new Map<Id, Lead>()
            : new Map<Id, Lead>([
                SELECT Id, AI_Classification__c, AI_KeyTopics__c, AI_Reason__c, AI_ReplyRecommendation__c, AI_Score__c
                FROM Lead
                WHERE Id IN :leadIds
            ]);

        Id demoTargetAccountId = getActiveDemoTargetAccountId();

        for (Requests request : requests) {
            Lead leadRecord = request == null ? null : leadsById.get(request.leadId);
            Results result = fromExisting(leadRecord);

            if (leadRecord == null || demoTargetAccountId == null) {
                output.add(result);
                continue;
            }

            try {
                String promptResponse = callPrompt(leadRecord.Id, demoTargetAccountId);
                if (!String.isBlank(promptResponse)) {
                    CM_LeadAIJsonParser.Results parsed =
                        CM_LeadAIJsonParser.parseJson(new List<String>{ promptResponse })[0];
                    result.classification = parsed.classification;
                    result.key_topics = parsed.key_topics;
                    result.reason = parsed.reason;
                    result.reply_recommendation = parsed.reply_recommendation;
                    result.score = parsed.score;
                }
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Lead AI scoring failed: ' + ex.getMessage());
            }

            output.add(result);
        }

        return output;
    }

    private static Id getActiveDemoTargetAccountId() {
        List<Account> accounts = [
            SELECT Id
            FROM Account
            WHERE CM_Is_Demo_Target__c = true
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return accounts.isEmpty() ? null : accounts[0].Id;
    }

    private static String callPrompt(Id leadId, Id demoTargetAccountId) {
        if (Test.isRunningTest() && testPromptResponse != null) {
            return testPromptResponse;
        }

        Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
        inputParams.put('Input:Lead', toSObjectInput(leadId));
        inputParams.put('Input:DemoTargetAccount', toSObjectInput(demoTargetAccountId));

        ConnectApi.EinsteinPromptTemplateGenerationsInput promptInput =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        promptInput.inputParams = inputParams;
        promptInput.isPreview = false;

        ConnectApi.EinsteinLlmAdditionalConfigInput additionalConfig =
            new ConnectApi.EinsteinLlmAdditionalConfigInput();
        additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
        promptInput.additionalConfig = additionalConfig;

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation result =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(PROMPT_TEMPLATE_NAME, promptInput);

        if (result != null && result.generations != null && !result.generations.isEmpty()) {
            return result.generations[0].text;
        }
        return null;
    }

    private static ConnectApi.WrappedValue toSObjectInput(Id recordId) {
        Map<String, String> recordRef = new Map<String, String>{ 'id' => String.valueOf(recordId) };
        ConnectApi.WrappedValue wrappedValue = new ConnectApi.WrappedValue();
        wrappedValue.value = recordRef;
        return wrappedValue;
    }

    private static Results fromExisting(Lead leadRecord) {
        Results result = new Results();
        if (leadRecord == null) {
            return result;
        }

        result.classification = leadRecord.AI_Classification__c;
        result.key_topics = leadRecord.AI_KeyTopics__c;
        result.reason = leadRecord.AI_Reason__c;
        result.reply_recommendation = leadRecord.AI_ReplyRecommendation__c;
        result.score = leadRecord.AI_Score__c == null
            ? null
            : Integer.valueOf(String.valueOf(leadRecord.AI_Score__c));
        return result;
    }

    public class Requests {
        @InvocableVariable(required=true)
        public Id leadId;
    }

    public class Results {
        @InvocableVariable public String classification;
        @InvocableVariable public String key_topics;
        @InvocableVariable public String reason;
        @InvocableVariable public String reply_recommendation;
        @InvocableVariable public Integer score;
    }
}