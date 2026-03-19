public with sharing class CM_BusinessCard_Controller {

    private static final Integer MAX_ACCOUNT_MATCHES = 5;
    @TestVisible private static String TEST_LLM_OUTPUT;

    // ===== DTOs =====
    public class CM_CardData {
        @AuraEnabled public String Company;
        @AuraEnabled public String LastName;
        @AuraEnabled public String FirstName;
        @AuraEnabled public String Title;
        @AuraEnabled public String Email;
        @AuraEnabled public String Phone;
        @AuraEnabled public String MobilePhone;
        @AuraEnabled public String Website;
        @AuraEnabled public String Street;
        @AuraEnabled public String City;
        @AuraEnabled public String State;
        @AuraEnabled public String PostalCode;
        @AuraEnabled public String Country;
        @AuraEnabled public String Description;
        @AuraEnabled public Double  Confidence;
        @AuraEnabled public String  Remark;
        @AuraEnabled public String  TaxId;
        @AuraEnabled public String  CreateAs;
        @AuraEnabled public String  LeadSource;
        @AuraEnabled public String  ExistingAccountId;

        // for front-end grouping / image display
        @AuraEnabled public String  ContentVersionId;
        @AuraEnabled public String  ContentDocumentId;
        @AuraEnabled public Boolean Seed;
    }
    public class InitResult {
        @AuraEnabled public String  batchId;
        @AuraEnabled public Integer createdCount;
    }
    public class BatchProgress {
        @AuraEnabled public Integer total = 0;       // denominator: sum of ExpectedCards__c of seeds
        @AuraEnabled public Integer recognized = 0;  // processed and non-failed estimate
        @AuraEnabled public Integer failed = 0;      // number of images failed as a whole
        @AuraEnabled public String  status;          // ALL_RECOGNIZED / IN_PROGRESS / EMPTY
    }
    public class AccountMatch {
        @AuraEnabled public String companyName;
        @AuraEnabled public List<AccountOption> accounts = new List<AccountOption>();
    }
    public class AccountOption {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String name;
        @AuraEnabled public String phone;
        @AuraEnabled public String billingCity;
        @AuraEnabled public String billingCountry;
    }

    // ===== Screen A：init batch & persist temp rows (supports 069/068) =====
    @AuraEnabled
    public static InitResult initBatchAndPersist(List<Id> contentVersionIds) {
        if (contentVersionIds == null || contentVersionIds.isEmpty()) {
            throw new AuraHandledException(Label.CM_BC_Err_NoFiles);
        }

        String batchId = newBatchId();

        // branch: 069 = ContentDocumentId, 068 = ContentVersionId
        Set<Id> docIds = new Set<Id>();
        Set<Id> verIds = new Set<Id>();
        for (Id anyId : contentVersionIds) {
            String pref = String.valueOf(anyId).substring(0, 3);
            if (pref == '069') docIds.add(anyId);
            else if (pref == '068') verIds.add(anyId);
            else docIds.add(anyId);
        }

        List<ContentVersion> versions = new List<ContentVersion>();
        try {
            if (!docIds.isEmpty()) {
                versions.addAll([
                    SELECT Id, ContentDocumentId, Title, IsLatest, VersionData
                    FROM ContentVersion
                    WHERE ContentDocumentId IN :docIds
                      AND IsLatest = true
                    LIMIT 200
                ]);
            }
            if (!verIds.isEmpty()) {
                versions.addAll([
                    SELECT Id, ContentDocumentId, Title, IsLatest, VersionData
                    FROM ContentVersion
                    WHERE Id IN :verIds
                    LIMIT 200
                ]);
            }
        } catch (Exception qex) {
            throw new AuraHandledException(String.format(
                Label.CM_BC_Err_ReadFileVersionFailed,
                new List<String>{ String.valueOf(qex.getMessage()) }
            ));
        }

        if (versions.isEmpty()) {
            throw new AuraHandledException(Label.CM_BC_Err_NoUsableFileVersion);
        }

        List<CM_BusinessCard__c> toInsert = new List<CM_BusinessCard__c>();
        for (ContentVersion cv : versions) {
            String hashHex;
            try {
                // prefer bytes → SHA-256
                Blob body = cv.VersionData;
                hashHex = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', body));
            } catch (Exception ex) {
                // fallback when no Download Content permission
                String seed = String.valueOf(cv.ContentDocumentId) + ':' + String.valueOf(cv.Id);
                hashHex = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(seed)));
            }

            CM_BusinessCard__c bc = new CM_BusinessCard__c();
            bc.BatchId__c           = batchId;
            bc.ContentDocumentId__c = cv.ContentDocumentId;
            bc.ContentVersionId__c  = cv.Id;
            bc.FileHash__c          = fitToField(hashHex, CM_BusinessCard__c.FileHash__c);
            bc.Status__c            = 'Recognizing';

            // seed rows (one per uploaded image)
            bc.Seed__c              = true;
            bc.ExpectedCards__c     = 1;
            bc.ProcessedCards__c    = 0;

            toInsert.add(bc);
        }

        try {
            insert toInsert;
        } catch (DmlException dmle) {
            throw new AuraHandledException(String.format(
                Label.CM_BC_Err_CreateTempFailed,
                new List<String>{ String.valueOf(dmle.getDmlMessage(0)) }
            ));
        }

        try {
            System.enqueueJob(new CM_BusinessCard_Ocr_Job(batchId));
        } catch (Exception jex) {
            throw new AuraHandledException(String.format(
                Label.CM_BC_Err_QueueJobFailed,
                new List<String>{ String.valueOf(jex.getMessage()) }
            ));
        }

        InitResult res = new InitResult();
        res.batchId = batchId;
        res.createdCount = toInsert.size();
        return res;
    }

    // ===== Screen B：poll batch progress (denominator = cards) =====
    @AuraEnabled(cacheable=false)
    public static BatchProgress getBatchProgress(String batchId) {
        if (String.isBlank(batchId)) throw new AuraHandledException(Label.CM_BC_Err_BatchIdRequired);

        BatchProgress p = new BatchProgress();

        List<CM_BusinessCard__c> seeds = [
            SELECT Status__c, ExpectedCards__c, ProcessedCards__c
            FROM CM_BusinessCard__c
            WHERE BatchId__c = :batchId AND Seed__c = true
            LIMIT 1000
        ];

        Integer totalItems = 0;
        Integer processedItems = 0;
        Integer failedImages = 0;

        for (CM_BusinessCard__c s : seeds) {
            Integer exp = (s.ExpectedCards__c == null || s.ExpectedCards__c <= 0) ? 1 : Integer.valueOf(s.ExpectedCards__c);
            Integer pro = (s.ProcessedCards__c == null || s.ProcessedCards__c < 0) ? 0 : Integer.valueOf(s.ProcessedCards__c);
            totalItems += exp;
            processedItems += pro;

            if (s.Status__c == 'Failed') {
                failedImages += 1;
                if (pro == 0) { processedItems += 1; } // whole image failed still counts as processed 1
            }
        }

        p.total = totalItems;
        p.recognized = Math.max(0, processedItems - failedImages);
        p.failed = failedImages;

        if (p.total == 0) p.status = 'EMPTY';
        else if (processedItems >= totalItems) p.status = 'ALL_RECOGNIZED';
        else p.status = 'IN_PROGRESS';

        return p;
    }

    // ===== Seed version ids (for one image one seed) =====
    @AuraEnabled(cacheable=false)
    public static List<Id> getSeedVersionIdsByBatch(String batchId) {
        if (String.isBlank(batchId)) throw new AuraHandledException(Label.CM_BC_Err_BatchIdRequired);
        List<Id> outIds = new List<Id>();
        for (CM_BusinessCard__c r : [
            SELECT ContentVersionId__c
            FROM CM_BusinessCard__c
            WHERE BatchId__c = :batchId AND Seed__c = true
            ORDER BY CreatedDate ASC
            LIMIT 2000
        ]) {
            if (r.ContentVersionId__c != null) outIds.add((Id) r.ContentVersionId__c);
        }
        return outIds;
    }

    // ===== Cards by single ContentVersionId (optionally scoped by batch) =====
    @AuraEnabled(cacheable=false)
    public static List<CM_CardData> getCardsByVersion(Id contentVersionId, String batchId) {
        if (contentVersionId == null) throw new AuraHandledException(Label.CM_BC_Err_ContentVersionIdRequired);

        List<CM_CardData> out = new List<CM_CardData>();
        List<CM_BusinessCard__c> rows = String.isBlank(batchId)
            ? [SELECT Status__c, Company__c, TaxId__c, LastName__c, FirstName__c, Title__c, Email__c,
                      Phone__c, MobilePhone__c, Website__c, Street__c, City__c, State__c, PostalCode__c,
                      Country__c, Description__c, Remark__c,
                      ContentVersionId__c, ContentDocumentId__c, Seed__c
               FROM CM_BusinessCard__c
               WHERE ContentVersionId__c = :contentVersionId
                 AND Status__c = 'Recognized'
               ORDER BY CreatedDate ASC LIMIT 200]
            : [SELECT Status__c, Company__c, TaxId__c, LastName__c, FirstName__c, Title__c, Email__c,
                      Phone__c, MobilePhone__c, Website__c, Street__c, City__c, State__c, PostalCode__c,
                      Country__c, Description__c, Remark__c,
                      ContentVersionId__c, ContentDocumentId__c, Seed__c
               FROM CM_BusinessCard__c
               WHERE ContentVersionId__c = :contentVersionId
                 AND BatchId__c = :batchId
                 AND Status__c = 'Recognized'
               ORDER BY CreatedDate ASC LIMIT 200];

        for (CM_BusinessCard__c r : rows) {
            CM_CardData d = new CM_CardData();
            d.Company     = r.Company__c;
            d.TaxId       = r.TaxId__c;
            d.LastName    = r.LastName__c;
            d.FirstName   = r.FirstName__c;
            d.Title       = r.Title__c;
            d.Email       = r.Email__c;
            d.Phone       = r.Phone__c;
            d.MobilePhone = r.MobilePhone__c;
            d.Website     = r.Website__c;
            d.Street      = r.Street__c;
            d.City        = r.City__c;
            d.State       = r.State__c;
            d.PostalCode  = r.PostalCode__c;
            d.Country     = r.Country__c;
            d.Description = r.Description__c;
            d.Remark      = r.Remark__c;
            d.ContentVersionId  = (String) r.ContentVersionId__c;
            d.ContentDocumentId = (String) r.ContentDocumentId__c;
            d.Seed              = r.Seed__c;
            out.add(d);
        }
        return out;
    }

    @AuraEnabled
    public static void updateDescriptionsForVersion(Id contentVersionId, List<String> descriptions, String batchId) {
        if (contentVersionId == null) throw new AuraHandledException(Label.CM_BC_Err_ContentVersionIdRequired);
        if (descriptions == null) descriptions = new List<String>();

        List<CM_BusinessCard__c> rows = String.isBlank(batchId)
            ? [SELECT Id FROM CM_BusinessCard__c
               WHERE ContentVersionId__c = :contentVersionId
               ORDER BY CreatedDate ASC LIMIT 200]
            : [SELECT Id FROM CM_BusinessCard__c
               WHERE ContentVersionId__c = :contentVersionId AND BatchId__c = :batchId
               ORDER BY CreatedDate ASC LIMIT 200];

        Integer n = Math.min(rows.size(), descriptions.size());
        for (Integer i = 0; i < n; i++) rows[i].Description__c = descriptions[i];
        if (n > 0) update rows;
    }

    // ===== Batch cards (return only Recognized) =====
    @AuraEnabled(cacheable=false)
    public static List<CM_CardData> getCardsByBatch(String batchId) {
        if (String.isBlank(batchId)) throw new AuraHandledException(Label.CM_BC_Err_BatchIdRequired);

        List<CM_CardData> outList = new List<CM_CardData>();
        for (CM_BusinessCard__c r : [
            SELECT Status__c,
                   Company__c, TaxId__c, LastName__c, FirstName__c, Title__c, Email__c,
                   Phone__c, MobilePhone__c, Website__c, Street__c, City__c,
                   State__c, PostalCode__c, Country__c, Description__c, Remark__c,
                   ContentVersionId__c, ContentDocumentId__c, Seed__c
            FROM CM_BusinessCard__c
            WHERE BatchId__c = :batchId
              AND Status__c = 'Recognized'
            ORDER BY CreatedDate ASC
            LIMIT 1000
        ]) {
            CM_CardData d = new CM_CardData();
            d.Company     = r.Company__c;
            d.LastName    = r.LastName__c;
            d.FirstName   = r.FirstName__c;
            d.Title       = r.Title__c;
            d.Email       = r.Email__c;
            d.Phone       = r.Phone__c;
            d.MobilePhone = r.MobilePhone__c;
            d.Website     = r.Website__c;
            d.Street      = r.Street__c;
            d.City        = r.City__c;
            d.State       = r.State__c;
            d.PostalCode  = r.PostalCode__c;
            d.Country     = r.Country__c;
            d.Description = r.Description__c;
            d.Remark      = r.Remark__c;
            d.TaxId       = r.TaxId__c;
            d.ContentVersionId  = (String) r.ContentVersionId__c;
            d.ContentDocumentId = (String) r.ContentDocumentId__c;
            d.Seed              = r.Seed__c;
            outList.add(d);
        }
        return outList;
    }

    @AuraEnabled(cacheable=false)
    public static List<AccountMatch> findAccountDuplicates(List<String> companyNames) {
        List<AccountMatch> outputs = new List<AccountMatch>();
        if (companyNames == null) {
            return outputs;
        }

        Map<String, List<Integer>> indexByKey = new Map<String, List<Integer>>();
        Map<String, Set<String>> valuesByKey = new Map<String, Set<String>>();

        Integer position = 0;
        for (String rawName : companyNames) {
            AccountMatch match = new AccountMatch();
            match.companyName = rawName;
            outputs.add(match);

            String trimmed = String.isBlank(rawName) ? null : rawName.trim();
            String normalized = normalizeCompanyName(trimmed);
            if (normalized != null) {
                List<Integer> indexes = indexByKey.get(normalized);
                if (indexes == null) {
                    indexes = new List<Integer>();
                    indexByKey.put(normalized, indexes);
                }
                indexes.add(position);

                Set<String> actualValues = valuesByKey.get(normalized);
                if (actualValues == null) {
                    actualValues = new Set<String>();
                    valuesByKey.put(normalized, actualValues);
                }
                actualValues.add(trimmed);
            }
            position++;
        }

        if (indexByKey.isEmpty()) {
            return outputs;
        }

        Set<String> queryValues = new Set<String>();
        for (Set<String> subset : valuesByKey.values()) {
            queryValues.addAll(subset);
        }

        if (queryValues.isEmpty()) {
            return outputs;
        }

        List<Account> accounts = [
            SELECT Id, Name, Phone, BillingCity, BillingCountry
            FROM Account
            WHERE Name IN :queryValues
            ORDER BY LastModifiedDate DESC
            LIMIT 500
        ];

        Map<String, List<AccountOption>> optionsByKey = new Map<String, List<AccountOption>>();
        for (Account acc : accounts) {
            String normalized = normalizeCompanyName(acc.Name);
            if (normalized == null || !indexByKey.containsKey(normalized)) {
                continue;
            }

            List<AccountOption> options = optionsByKey.get(normalized);
            if (options == null) {
                options = new List<AccountOption>();
                optionsByKey.put(normalized, options);
            }
            if (options.size() >= MAX_ACCOUNT_MATCHES) {
                continue;
            }

            AccountOption option = new AccountOption();
            option.accountId = acc.Id;
            option.name = acc.Name;
            option.phone = acc.Phone;
            option.billingCity = acc.BillingCity;
            option.billingCountry = acc.BillingCountry;
            options.add(option);
        }

        for (String key : indexByKey.keySet()) {
            List<AccountOption> options = optionsByKey.get(key);
            if (options == null) {
                continue;
            }
            for (Integer idx : indexByKey.get(key)) {
                outputs[idx].accounts.addAll(options);
            }
        }

        return outputs;
    }

    // ===== Batch update descriptions (by created order) =====
    @AuraEnabled
    public static void updateDescriptions(String batchId, List<String> descriptions) {
        if (String.isBlank(batchId)) throw new AuraHandledException(Label.CM_BC_Err_BatchIdRequired);
        if (descriptions == null) descriptions = new List<String>();

        List<CM_BusinessCard__c> rows = [
            SELECT Id
            FROM CM_BusinessCard__c
            WHERE BatchId__c = :batchId
            ORDER BY CreatedDate ASC
            LIMIT 1000
        ];
        Integer n = Math.min(rows.size(), descriptions.size());
        for (Integer i = 0; i < n; i++) {
            rows[i].Description__c = descriptions[i];
        }
        if (n > 0) update rows;
    }

    // ===== Helper: call Prompt Template & return JSON array =====
    @AuraEnabled(cacheable=false)
    public static List<CM_CardData> getCardProcessingResult(String contentDocumentId) {
        if (String.isBlank(contentDocumentId)) {
            throw new AuraHandledException(Label.CM_BC_Err_FileIdBlank);
        }
        try {
            if (Test.isRunningTest() && TEST_LLM_OUTPUT != null) {
                return parseLlmOutput(TEST_LLM_OUTPUT);
            }
            Map<String, String> idMap = new Map<String, String>();
            idMap.put('id', contentDocumentId);

            ConnectApi.WrappedValue inputValue = new ConnectApi.WrappedValue();
            inputValue.value = idMap;

            Map<String, ConnectApi.WrappedValue> inputParamsMap = new Map<String, ConnectApi.WrappedValue>();
            inputParamsMap.put('Input:cardFile', inputValue);

            ConnectApi.EinsteinPromptTemplateGenerationsInput promptInput =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            promptInput.inputParams = inputParamsMap;
            promptInput.isPreview   = false;

            ConnectApi.EinsteinLlmAdditionalConfigInput addcfg =
                new ConnectApi.EinsteinLlmAdditionalConfigInput();
            addcfg.applicationName = 'PromptTemplateGenerationsInvocable';
            promptInput.additionalConfig = addcfg;

            String promptApiName = 'CM_BusinessCard_Card_To_Lead';

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation result =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(promptApiName, promptInput);

            if (result != null && result.generations != null && !result.generations.isEmpty()) {
                String llmOutput = result.generations[0].text;
                return parseLlmOutput(llmOutput);
            } else {
                return new List<CM_CardData>();
            }
        } catch (Exception e) {
            throw new AuraHandledException(String.format(
                Label.CM_BC_Err_PromptCallFailed,
                new List<String>{ String.valueOf(e.getMessage()) }
            ));
        }
    }

    // ===== Progress by single ContentVersionId =====
    @AuraEnabled(cacheable=false)
    public static BatchProgress getProgressByVersionId(Id contentVersionIdOrDocId) {
        if (contentVersionIdOrDocId == null) {
            throw new AuraHandledException(Label.CM_BC_Err_ContentVersionIdRequired);
        }
        Id verId = toLatestVersionId(contentVersionIdOrDocId);
        if (verId == null) {
            BatchProgress p0 = new BatchProgress();
            p0.status = 'EMPTY';
            return p0;
        }

        BatchProgress p = new BatchProgress();

        List<CM_BusinessCard__c> seeds = [
            SELECT Status__c, ExpectedCards__c, ProcessedCards__c
            FROM CM_BusinessCard__c
            WHERE Seed__c = true AND ContentVersionId__c = :verId
            LIMIT 200
        ];

        Integer totalItems = 0, processedItems = 0, failedImages = 0;
        for (CM_BusinessCard__c s : seeds) {
            Integer exp = (s.ExpectedCards__c == null || s.ExpectedCards__c <= 0) ? 1 : Integer.valueOf(s.ExpectedCards__c);
            Integer pro = (s.ProcessedCards__c == null || s.ProcessedCards__c < 0) ? 0 : Integer.valueOf(s.ProcessedCards__c);
            totalItems += exp;
            processedItems += pro;
            if (s.Status__c == 'Failed') {
                failedImages += 1;
                if (pro == 0) processedItems += 1; // whole image failed counts as one processed
            }
        }
        p.total = totalItems;
        p.recognized = Math.max(0, processedItems - failedImages);
        p.failed = failedImages;

        if (p.total == 0) p.status = 'EMPTY';
        else if (processedItems >= totalItems) p.status = 'ALL_RECOGNIZED';
        else p.status = 'IN_PROGRESS';

        return p;
    }

    // ===== Cards by single ContentVersionId (Recognized only) =====
    @AuraEnabled(cacheable=false)
    public static List<CM_CardData> getCardsByVersionId(Id contentVersionIdOrDocId) {
        if (contentVersionIdOrDocId == null) {
            throw new AuraHandledException(Label.CM_BC_Err_ContentVersionIdRequired);
        }
        Id verId = toLatestVersionId(contentVersionIdOrDocId);
        if (verId == null) return new List<CM_CardData>();

        List<CM_CardData> outList = new List<CM_CardData>();
        for (CM_BusinessCard__c r : [
            SELECT Status__c,
                   Company__c, TaxId__c, LastName__c, FirstName__c, Title__c, Email__c,
                   Phone__c, MobilePhone__c, Website__c, Street__c, City__c,
                   State__c, PostalCode__c, Country__c, Description__c, Remark__c,
                   ContentVersionId__c, ContentDocumentId__c, Seed__c
            FROM CM_BusinessCard__c
            WHERE ContentVersionId__c = :verId
              AND Status__c = 'Recognized'
            ORDER BY CreatedDate ASC
            LIMIT 1000
        ]) {
            CM_CardData d = new CM_CardData();
            d.Company     = r.Company__c;
            d.TaxId       = r.TaxId__c;
            d.LastName    = r.LastName__c;
            d.FirstName   = r.FirstName__c;
            d.Title       = r.Title__c;
            d.Email       = r.Email__c;
            d.Phone       = r.Phone__c;
            d.MobilePhone = r.MobilePhone__c;
            d.Website     = r.Website__c;
            d.Street      = r.Street__c;
            d.City        = r.City__c;
            d.State       = r.State__c;
            d.PostalCode  = r.PostalCode__c;
            d.Country     = r.Country__c;
            d.Description = r.Description__c;
            d.Remark      = r.Remark__c;
            d.ContentVersionId  = (String) r.ContentVersionId__c;
            d.ContentDocumentId = (String) r.ContentDocumentId__c;
            d.Seed              = r.Seed__c;
            outList.add(d);
        }
        return outList;
    }

    // ===== Helper: 069 → latest 068; if already 068, return as-is =====
    private static Id toLatestVersionId(Id verOrDocId) {
        if (verOrDocId == null) return null;
        String pref = String.valueOf(verOrDocId).substring(0,3);
        if (pref == '068') return verOrDocId;
        if (pref == '069') {
            List<ContentVersion> vs = [
                SELECT Id FROM ContentVersion
                WHERE ContentDocumentId = :verOrDocId AND IsLatest = true
                LIMIT 1
            ];
            return vs.isEmpty() ? null : vs[0].Id;
        }
        return verOrDocId;
    }

    private static String normalizeCompanyName(String name) {
        if (String.isBlank(name)) {
            return null;
        }
        return name.trim().toLowerCase();
    }

    // ===== Utilities =====
    private static String newBatchId() {
        String seed = String.valueOf(System.now().getTime())
            + ':' + UserInfo.getOrganizationId()
            + ':' + UserInfo.getUserId()
            + ':' + String.valueOf(Math.random());
        String hex = EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', Blob.valueOf(seed))
        );
        return hex.substring(0,8) + '-' + hex.substring(8,12) + '-' + hex.substring(12,16)
             + '-' + hex.substring(16,20) + '-' + hex.substring(20,32);
    }
    private static String shortId() {
        String seed = String.valueOf(System.now().getTime()) + ':' + Math.random();
        String hex = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(seed)));
        return hex.substring(0,6);
    }
    // trim string to field length
    private static String fitToField(String s, SObjectField f) {
        if (s == null) return null;
        Integer max = f.getDescribe().getLength();
        return (s.length() <= max) ? s : s.substring(0, max);
    }
    // extract JSON array from LLM output
    private static String extractJsonArray(String s) {
        if (String.isBlank(s)) return '[]';
        String x = s.trim();
        if (x.startsWith('```json')) x = x.substring(7).trim();
        else if (x.startsWith('```')) x = x.substring(3).trim();
        if (x.endsWith('```')) x = x.substring(0, x.length() - 3).trim();
        Integer a = x.indexOf('[');
        Integer b = x.lastIndexOf(']');
        if (a < 0 || b <= a) return null;
        return x.substring(a, b + 1);
    }

    private static List<CM_CardData> parseLlmOutput(String llmOutput) {
        if (llmOutput != null && llmOutput.trim() == '[]') {
            return new List<CM_CardData>();
        }
        String cleanJson = extractJsonArray(llmOutput); // first '[' to last ']'
        if (cleanJson == null) {
            throw new AuraHandledException(String.format(
                Label.CM_BC_Err_InvalidJsonArrayFromAI,
                new List<String>{ String.valueOf(llmOutput) }
            ));
        }
        List<CM_CardData> parsed =
            (List<CM_CardData>) JSON.deserialize(cleanJson, List<CM_CardData>.class);
        return parsed == null ? new List<CM_CardData>() : parsed;
    }
}