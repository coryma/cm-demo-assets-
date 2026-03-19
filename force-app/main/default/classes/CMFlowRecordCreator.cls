public with sharing class CMFlowRecordCreator {
    /**
     * Invocable wrapper to create follow-up records from analyzed meeting notes.
     * Designed to run in orgs that may not have FSC Interaction objects.
     */
    @InvocableMethod(label='CM Create Records From JSON' description='Creates lead, opportunity, and tasks from analyzed meeting-note JSON')
    public static List<CMResponse> createRecords(List<CMRequest> requests) {
        List<CMResponse> responses = new List<CMResponse>();
        for (CMRequest req : requests) {
            CMResponse res = new CMResponse();
            try {
                if (req == null || String.isBlank(req.recordId) || String.isBlank(req.jsonString)) {
                    throw new AuraHandledException('recordId and jsonString are required.');
                }
                Id accountId = Id.valueOf(req.recordId);

                Account person = [
                    SELECT Id, Name, PersonContactId
                    FROM Account
                    WHERE Id = :accountId
                    LIMIT 1
                ];

                String cleanedJson = sanitizeJson(req.jsonString);
                Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(cleanedJson);
                if (payload == null) {
                    throw new AuraHandledException('Unable to parse JSON payload.');
                }

                Map<String, Object> interactionMap = (Map<String, Object>) payload.get('interaction');
                Map<String, Object> overviewMap = (Map<String, Object>) payload.get('meeting_decision_overview');
                res.interactionSubject = buildInteractionSubject(interactionMap, overviewMap);
                res.interactionSummaryBody = buildInteractionSummary(interactionMap, overviewMap);

                // Lead
                Lead leadRec = buildLead(payload, person);

                // Opportunity
                Opportunity oppRec = buildOpportunity(payload, person.Id);

                // Tasks
                List<Task> tasks = buildTasks(payload, person.Id);

                // Interaction & Interaction Summary (dynamic to avoid compile-time dependency on FSC package)
                List<SObject> interactionRecords = buildInteractionRecords(payload, person.Id);

                List<String> errors = new List<String>();

                // Lead DML
                if (leadRec != null) {
                    Database.DMLOptions dmlOpts = new Database.DMLOptions();
                    dmlOpts.duplicateRuleHeader.allowSave = true;
                    dmlOpts.duplicateRuleHeader.runAsCurrentUser = true;
                    leadRec.setOptions(dmlOpts);
                    Database.SaveResult leadResult = Database.insert(leadRec, false);
                    if (leadResult.isSuccess()) {
                        res.leadRecord = leadRec;
                    } else {
                        Lead dupLead = resolveDuplicateLead(leadRec, leadResult);
                        if (dupLead != null) {
                            res.leadRecord = dupLead;
                        } else {
                            errors.addAll(extractErrors(leadResult));
                        }
                    }
                }

                // Opportunity DML
                if (oppRec != null) {
                    Database.SaveResult oppResult = Database.insert(oppRec, false);
                    if (oppResult.isSuccess()) {
                        res.opportunityRecord = oppRec;
                    } else {
                        errors.addAll(extractErrors(oppResult));
                    }
                }

                // Tasks DML
                if (!tasks.isEmpty()) {
                    Database.SaveResult[] taskResults = Database.insert(tasks, false);
                    List<Task> successfulTasks = new List<Task>();
                    for (Integer i = 0; i < taskResults.size(); i++) {
                        if (taskResults[i].isSuccess()) {
                            successfulTasks.add(tasks[i]);
                        } else {
                            errors.addAll(extractErrors(taskResults[i]));
                        }
                    }
                    if (!successfulTasks.isEmpty()) {
                        res.taskRecords = successfulTasks;
                    }
                }

                // Interaction / InteractionSummary DML
                if (!interactionRecords.isEmpty()) {
                    Database.SaveResult[] interactionResults = Database.insert(interactionRecords, false);
                    for (Integer i = 0; i < interactionResults.size(); i++) {
                        if (!interactionResults[i].isSuccess()) {
                            errors.addAll(extractErrors(interactionResults[i]));
                        }
                    }
                }

                if (!errors.isEmpty()) {
                    res.errorMsg = String.join(errors, ' | ');
                }
            } catch (Exception e) {
                res.errorMsg = e.getMessage();
            }
            responses.add(res);
        }
        return responses;
    }

    // Remove markdown fences/backticks that sometimes wrap JSON from LLM responses.
    private static String sanitizeJson(String rawJson) {
        if (String.isBlank(rawJson)) {
            return rawJson;
        }
        String cleaned = rawJson
            .replace('```json', '')
            .replace('```', '')
            .replace('\u00A0', ' ') // non-breaking space
            .replace('\uFEFF', ' ') // BOM if present
            .trim();
        // If extra prose exists, keep only the JSON object block.
        Integer start = cleaned.indexOf('{');
        Integer endIdx = cleaned.lastIndexOf('}');
        if (start >= 0 && endIdx >= start) {
            cleaned = cleaned.substring(start, endIdx + 1);
        }
        return cleaned;
    }

    private static List<String> extractErrors(Database.SaveResult sr) {
        List<String> errs = new List<String>();
        for (Database.Error err : sr.getErrors()) {
            errs.add(err.getMessage());
        }
        return errs;
    }

    private static Lead buildLead(Map<String, Object> payload, Account person) {
        Map<String, Object> leadMap = (Map<String, Object>) payload.get('lead');
        if (leadMap == null) {
            return null;
        }
        Lead leadRec = new Lead();
        Map<String, Schema.SObjectField> leadFields = Lead.SObjectType.getDescribe().fields.getMap();
        String companyName = leadMap != null ? (String) leadMap.get('companyName') : null;
        if (String.isBlank(companyName)) {
            companyName = person.Name;
        }
        setIfPresent(leadRec, leadFields, 'Company', companyName);

        String firstName = getString(leadMap, 'firstName');
        String lastName = getString(leadMap, 'lastName');
        if (String.isBlank(lastName)) {
            lastName = String.isBlank(person.Name) ? 'Meeting Contact' : person.Name;
        }
        setIfPresent(leadRec, leadFields, 'FirstName', firstName);
        setIfPresent(leadRec, leadFields, 'LastName', lastName);
        setIfPresent(leadRec, leadFields, 'SDO_Sales_Has_Budget__c', true);
        setIfPresent(leadRec, leadFields, 'SDO_Sales_Decision_Timeframe__c', 'Immediately');
        setIfPresent(leadRec, leadFields, 'SDO_Sales_Know_Decision_Maker__c', true);
        setIfPresent(leadRec, leadFields, 'Rating', 'Hot');
        setIfPresent(leadRec, leadFields, 'FinServ__ExpressedInterest__c', 'Commercial Loan');

        if (leadMap != null) {
            setIfPresent(leadRec, leadFields, 'LeadSource', leadMap.get('leadSource'));
            setIfPresent(leadRec, leadFields, 'Description', leadMap.get('description'));
            setIfPresent(leadRec, leadFields, 'Title', leadMap.get('title'));
        }
        // Use the current Account's Person Contact when the target org supports that FSC field.
        Id referredContactId = person.PersonContactId;
        if (referredContactId != null) {
            setIfPresent(leadRec, leadFields, 'FinServ__ReferredByContact__c', referredContactId);
        }

        // Resolve related account by company name
        if (!String.isBlank(companyName) && hasField(leadFields, 'FinServ__RelatedAccount__c')) {
            List<Account> relatedAccounts = [
                SELECT Id
                FROM Account
                WHERE Name = :companyName
                LIMIT 1
            ];
            if (!relatedAccounts.isEmpty()) {
                leadRec.put('FinServ__RelatedAccount__c', relatedAccounts[0].Id);
            }
        }
        return leadRec;
    }

    private static Opportunity buildOpportunity(Map<String, Object> payload, Id accountId) {
        Map<String, Object> oppMap = (Map<String, Object>) payload.get('opportunity');
        if (oppMap == null) {
            return null;
        }
        Opportunity oppRec = new Opportunity();
        oppRec.AccountId = accountId;
        oppRec.Name = oppMap != null && oppMap.get('name') != null ? (String) oppMap.get('name') : 'New Opportunity';
        oppRec.StageName = oppMap != null && oppMap.get('stageName') != null ? (String) oppMap.get('stageName') : 'Prospecting';
        if (oppMap != null && oppMap.get('closeDate') != null) {
            oppRec.CloseDate = Date.valueOf((String) oppMap.get('closeDate'));
        } else {
            oppRec.CloseDate = Date.today();
        }
        if (oppMap != null && oppMap.get('amount') != null) {
            oppRec.Amount = ((Decimal) ((Object) oppMap.get('amount')));
        }
        return oppRec;
    }

    private static List<Task> buildTasks(Map<String, Object> payload, Id accountId) {
        List<Task> tasks = new List<Task>();
        List<Object> taskList = (List<Object>) payload.get('tasks');
        Boolean useLegacyShape = taskList != null;
        if (taskList == null) {
            taskList = (List<Object>) payload.get('follow_up_actions');
        }
        if (taskList == null) {
            return tasks;
        }
        for (Object tObj : taskList) {
            Map<String, Object> tMap = (Map<String, Object>) tObj;
            Task t = new Task();
            if (useLegacyShape) {
                t.Subject = (String) tMap.get('subject');
                t.Description = (String) tMap.get('description');
                String dueDateStr = (String) tMap.get('dueDate');
                if (!String.isBlank(dueDateStr)) {
                    t.ActivityDate = Date.valueOf(dueDateStr);
                } else {
                    t.ActivityDate = Date.today().addDays(7);
                }
            } else {
                t.Subject = getString(tMap, 'action');
                t.Description = buildFollowUpDescription(tMap);
                t.ActivityDate = resolveRelativeDate(getString(tMap, 'timeframe'));
            }
            if (String.isBlank(t.Subject)) {
                continue;
            }
            t.WhatId = accountId;
            t.OwnerId = UserInfo.getUserId();
            t.Status = 'Not Started';
            t.Priority = 'Normal';
            tasks.add(t);
        }
        return tasks;
    }

    private static List<SObject> buildInteractionRecords(Map<String, Object> payload, Id accountId) {
        List<SObject> records = new List<SObject>();
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();

        Map<String, Object> interactionMap = (Map<String, Object>) payload.get('interaction');
        Map<String, Object> overviewMap = (Map<String, Object>) payload.get('meeting_decision_overview');
        String interactionSubject = buildInteractionSubject(interactionMap, overviewMap);
        String interactionSummary = buildInteractionSummary(interactionMap, overviewMap);
        if (!String.isBlank(interactionSubject) && gd.containsKey('Interaction')) {
            SObject interaction = gd.get('Interaction').newSObject();
            interaction.put('AccountId', accountId);
            interaction.put('Name', interactionSubject);
            records.add(interaction);
        }

        if (!String.isBlank(interactionSubject) && gd.containsKey('InteractionSummary')) {
            SObject summary = gd.get('InteractionSummary').newSObject();
            summary.put('AccountId', accountId);
            summary.put('Name', interactionSubject);
            summary.put('MeetingNotes', interactionSummary);
            records.add(summary);
        }
        return records;
    }

    private static String buildInteractionSubject(Map<String, Object> interactionMap, Map<String, Object> overviewMap) {
        String subject = getString(interactionMap, 'subject');
        if (!String.isBlank(subject)) {
            return subject;
        }
        String vendorName = getString(overviewMap, 'vendorName');
        if (!String.isBlank(vendorName)) {
            return 'QBR 會議跟進 - ' + vendorName;
        }
        return null;
    }

    private static String buildInteractionSummary(Map<String, Object> interactionMap, Map<String, Object> overviewMap) {
        String summaryBody = getString(interactionMap, 'summaryBody');
        if (!String.isBlank(summaryBody)) {
            return summaryBody;
        }
        String overviewSummary = getString(overviewMap, 'summary');
        return String.isBlank(overviewSummary) ? null : overviewSummary;
    }

    private static String buildFollowUpDescription(Map<String, Object> tMap) {
        List<String> lines = new List<String>();
        String owner = getString(tMap, 'owner');
        String timeframe = getString(tMap, 'timeframe');
        String status = getString(tMap, 'status');
        if (!String.isBlank(owner)) {
            lines.add('Owner: ' + owner);
        }
        if (!String.isBlank(timeframe)) {
            lines.add('Target: ' + timeframe);
        }
        if (!String.isBlank(status)) {
            lines.add('Status: ' + status);
        }
        return lines.isEmpty() ? null : String.join(lines, '\n');
    }

    private static Date resolveRelativeDate(String timeframe) {
        if (String.isBlank(timeframe)) {
            return Date.today().addDays(7);
        }
        String normalized = timeframe.trim().toUpperCase();
        if (normalized == 'ASAP') {
            return Date.today();
        }
        if (normalized == 'NEXT_WEEK' || normalized == 'PLUS_7_DAYS') {
            return Date.today().addDays(7);
        }
        if (normalized == 'END_OF_MONTH') {
            Date today = Date.today();
            return Date.newInstance(today.year(), today.month(), Date.daysInMonth(today.year(), today.month()));
        }
        return Date.today().addDays(7);
    }

    private static Boolean hasField(Map<String, Schema.SObjectField> fieldMap, String fieldName) {
        return fieldMap != null && fieldMap.containsKey(fieldName);
    }

    private static void setIfPresent(SObject record, Map<String, Schema.SObjectField> fieldMap, String fieldName, Object value) {
        if (record == null || String.isBlank(fieldName) || value == null || !hasField(fieldMap, fieldName)) {
            return;
        }
        record.put(fieldName, value);
    }

    private static String getString(Map<String, Object> source, String key) {
        if (source == null || String.isBlank(key) || !source.containsKey(key) || source.get(key) == null) {
            return null;
        }
        return String.valueOf(source.get(key));
    }

    // When duplicate rules block insert, try to return an existing matching Lead instead of failing the flow.
    private static Lead resolveDuplicateLead(Lead template, Database.SaveResult sr) {
        if (template == null || sr == null) {
            return null;
        }
        Boolean looksDuplicate = false;
        for (Database.Error err : sr.getErrors()) {
            if (err.getStatusCode() == StatusCode.DUPLICATES_DETECTED ||
                String.valueOf(err.getMessage()).toLowerCase().contains('duplicate')) {
                looksDuplicate = true;
                break;
            }
        }
        if (!looksDuplicate || String.isBlank(template.FirstName) || String.isBlank(template.LastName) || String.isBlank(template.Company)) {
            return null;
        }

        List<Lead> leads;
        if (!String.isBlank(template.FirstName)) {
            leads = [
                SELECT Id, FirstName, LastName, Company, LeadSource, RecordTypeId
                FROM Lead
                WHERE FirstName = :template.FirstName
                    AND LastName = :template.LastName
                    AND Company = :template.Company
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
        } else {
            leads = [
                SELECT Id, FirstName, LastName, Company, LeadSource, RecordTypeId
                FROM Lead
                WHERE LastName = :template.LastName
                    AND Company = :template.Company
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
        }
        return leads.isEmpty() ? null : leads[0];
    }

    public class CMRequest {
        @InvocableVariable(required=true label='Account Id')
        public String recordId;

        @InvocableVariable(required=true label='JSON Payload')
        public String jsonString;
    }

    public class CMResponse {
        @InvocableVariable(label='Error Message')
        public String errorMsg;

        @InvocableVariable(label='Created Lead')
        public Lead leadRecord;

        @InvocableVariable(label='Created Opportunity')
        public Opportunity opportunityRecord;

        @InvocableVariable(label='Interaction Subject')
        public String interactionSubject;

        @InvocableVariable(label='Interaction Summary Body')
        public String interactionSummaryBody;

        @InvocableVariable(label='Created Tasks')
        public List<Task> taskRecords;
    }
}