/**
 * @description Queueable job that processes business card recognition in the background.
 * Supports chaining, chunked flush (real-time updates), and fast-fail for empty results ([]).
 */
public class CM_BusinessCard_Ocr_Job implements Queueable, Database.AllowsCallouts {

    private final String batchId;
    @TestVisible private static String TEST_LLM_OUTPUT;

    // Max images per execute() (well below 100 callouts)
    private static final Integer PROCESSING_LIMIT = 10;
    // Chunked DML so the UI can see progress sooner
    private static final Integer UPDATE_CHUNK = 10;
    private static final Integer INSERT_CHUNK = 10;

    public CM_BusinessCard_Ocr_Job(String batchId) {
        this.batchId = batchId;
    }

    public void execute(QueueableContext qc) {
        if (String.isBlank(batchId)) return;

        // Note: don't place inline // comments inside SOQL
        List<CM_BusinessCard__c> seedsToProcess = [
            SELECT  Id, BatchId__c, Status__c, Seed__c,
                    ContentDocumentId__c, ContentVersionId__c,
                    Remark__c, Name, FileHash__c,
                    Company__c, LastName__c, FirstName__c, Title__c, Email__c,
                    Phone__c, MobilePhone__c, Website__c, Street__c, City__c,
                    State__c, PostalCode__c, Country__c, Description__c,
                    ExpectedCards__c, ProcessedCards__c
            FROM CM_BusinessCard__c
            WHERE BatchId__c = :batchId
              AND Seed__c = true
              AND Status__c = 'Recognizing'
            ORDER BY CreatedDate ASC
            LIMIT :PROCESSING_LIMIT
        ];
        if (seedsToProcess.isEmpty()) return;

        Map<Id, Id> ver2doc = resolveVersionIds(seedsToProcess);

        List<CM_BusinessCard__c> toUpdate = new List<CM_BusinessCard__c>();
        List<CM_BusinessCard__c> toInsert = new List<CM_BusinessCard__c>();

        for (CM_BusinessCard__c seed : seedsToProcess) {
            try {
                Id contentDocId = String.isNotBlank(seed.ContentDocumentId__c)
                    ? (Id) seed.ContentDocumentId__c
                    : ver2doc.get((Id) seed.ContentVersionId__c);

                if (contentDocId == null) {
                    markAsFailed(seed, 'ContentDocumentId not found');
                    toUpdate.add(seed);
                    flushUpdatesIfNeeded(toUpdate);
                    continue;
                }

                Long t0 = DateTime.now().getTime();
                List<CM_BusinessCard_Controller.CM_CardData> cards = callOcrPrompt(contentDocId);
                Long ocrMs = DateTime.now().getTime() - t0;
                String ocrTag = 'OCRms=' + String.valueOf(ocrMs);

                // No cards recognized (including llmOutput == '[]')
                if (cards == null || cards.isEmpty()) {
                    markAsFailed(seed, ocrTag + '; reason=no_card');
                    if (seed.ExpectedCards__c == null || seed.ExpectedCards__c <= 0) seed.ExpectedCards__c = 1;
                    if (seed.ProcessedCards__c == null || seed.ProcessedCards__c < 1) seed.ProcessedCards__c = 1;
                    toUpdate.add(seed);
                    flushUpdatesIfNeeded(toUpdate);
                    continue;
                }

                Integer total = cards.size();

                // Write the first card back to the seed
                applyCard(seed, cards.get(0));
                seed.Status__c = 'Recognized';
                seed.ExpectedCards__c = total;
                seed.ProcessedCards__c = total;
                seed.Remark__c = appendRemark(seed.Remark__c, ocrTag);
                toUpdate.add(seed);
                flushUpdatesIfNeeded(toUpdate);

                // Insert remaining cards separately
                for (Integer i = 1; i < total; i++) {
                    CM_BusinessCard__c extra = cloneSkeleton(seed);
                    extra.Seed__c = false;
                    applyCard(extra, cards.get(i));
                    extra.Status__c = 'Recognized';
                    extra.Remark__c = appendRemark(extra.Remark__c, ocrTag);
                    toInsert.add(extra);
                    flushInsertsIfNeeded(toInsert);
                }

            } catch (Exception ex) {
                markAsFailed(seed, 'Exception: ' + ex.getMessage());
                toUpdate.add(seed);
                flushUpdatesIfNeeded(toUpdate);
            }
        }

        // Finalize: flush remaining batches
        flushInsertsAll(toInsert);
        flushUpdatesAll(toUpdate);

        // Queue chaining: if seeds are still Recognizing, enqueue another job
        if (!Test.isRunningTest()) {
            Integer remaining = [
                SELECT COUNT() FROM CM_BusinessCard__c
                WHERE BatchId__c = :batchId AND Seed__c = true AND Status__c = 'Recognizing'
            ];
            if (remaining > 0) {
                System.enqueueJob(new CM_BusinessCard_Ocr_Job(this.batchId));
            }
        }
    }

    // ===== Call Prompt Template =====
    private static List<CM_BusinessCard_Controller.CM_CardData> callOcrPrompt(Id contentDocumentId) {
        if (Test.isRunningTest() && TEST_LLM_OUTPUT != null) {
            return parseLlmOutput(TEST_LLM_OUTPUT);
        }
        Map<String, String> idMap = new Map<String, String>{ 'id' => (String) contentDocumentId };
        ConnectApi.WrappedValue inputValue = new ConnectApi.WrappedValue();
        inputValue.value = idMap;

        Map<String, ConnectApi.WrappedValue> inputParamsMap = new Map<String, ConnectApi.WrappedValue>();
        inputParamsMap.put('Input:cardFile', inputValue);

        ConnectApi.EinsteinPromptTemplateGenerationsInput promptInput =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        promptInput.inputParams = inputParamsMap;
        promptInput.isPreview = false;

        ConnectApi.EinsteinLlmAdditionalConfigInput addCfg =
            new ConnectApi.EinsteinLlmAdditionalConfigInput();
        addCfg.applicationName = 'PromptTemplateGenerationsInvocable';
        promptInput.additionalConfig = addCfg;

        String promptApiName = 'CM_BusinessCard_Card_To_Lead';
        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation res =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(promptApiName, promptInput);

        if (res == null || res.generations == null || res.generations.isEmpty()) {
            return new List<CM_BusinessCard_Controller.CM_CardData>();
        }

        String llmOutput = res.generations[0].text;
        // Quick check for empty array string
        if (llmOutput != null && llmOutput.trim() == '[]') {
            return new List<CM_BusinessCard_Controller.CM_CardData>();
        }

        String jsonArray = extractJsonArray(llmOutput);
        if (jsonArray == null || jsonArray.trim() == '' || jsonArray.trim() == '[]') {
            return new List<CM_BusinessCard_Controller.CM_CardData>();
        }

        return (List<CM_BusinessCard_Controller.CM_CardData>)
            JSON.deserialize(jsonArray, List<CM_BusinessCard_Controller.CM_CardData>.class);
    }

    // ===== Chunked / finalize DML =====
    private static void flushUpdatesIfNeeded(List<CM_BusinessCard__c> records) {
        if (records.size() >= UPDATE_CHUNK) {
            Database.SaveResult[] results = Database.update(records, false);
            logDmlErrors('update', records, results);
            records.clear();
        }
    }
    private static void flushInsertsIfNeeded(List<CM_BusinessCard__c> records) {
        if (records.size() >= INSERT_CHUNK) {
            Database.SaveResult[] results = Database.insert(records, false);
            logDmlErrors('insert', records, results);
            records.clear();
        }
    }
    private static void flushUpdatesAll(List<CM_BusinessCard__c> records) {
        if (records.isEmpty()) return;
        Database.SaveResult[] results = Database.update(records, false);
        logDmlErrors('update', records, results);
        records.clear();
    }
    private static void flushInsertsAll(List<CM_BusinessCard__c> records) {
        if (records.isEmpty()) return;
        Database.SaveResult[] results = Database.insert(records, false);
        logDmlErrors('insert', records, results);
        records.clear();
    }
    private static void logDmlErrors(String op, List<CM_BusinessCard__c> records, Database.SaveResult[] results) {
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                String rid = records[i].Id != null ? String.valueOf(records[i].Id) : 'N/A';
                System.debug(System.LoggingLevel.ERROR,
                    'Failed to ' + op + ' CM_BusinessCard__c. Id=' + rid + ', Error=' + results[i].getErrors()[0].getMessage());
            }
        }
    }

    // ===== Utility methods =====
    private static void markAsFailed(CM_BusinessCard__c rec, String msg) {
        rec.Status__c = 'Failed';
        rec.Remark__c = appendRemark(rec.Remark__c, msg);
        if (rec.ExpectedCards__c == null || rec.ExpectedCards__c <= 0) rec.ExpectedCards__c = 1;
        if (rec.ProcessedCards__c == null || rec.ProcessedCards__c < 1) rec.ProcessedCards__c = 1;
    }

    private static Map<Id, Id> resolveVersionIds(List<CM_BusinessCard__c> seeds) {
        Map<Id, Id> ver2doc = new Map<Id, Id>();
        Set<Id> verIds = new Set<Id>();
        for (CM_BusinessCard__c r : seeds) {
            if (String.isBlank(r.ContentDocumentId__c) && String.isNotBlank(r.ContentVersionId__c)) {
                verIds.add((Id) r.ContentVersionId__c);
            }
        }
        if (!verIds.isEmpty()) {
            for (ContentVersion cv : [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id IN :verIds
            ]) {
                ver2doc.put(cv.Id, cv.ContentDocumentId);
            }
        }
        return ver2doc;
    }

    private static void applyCard(CM_BusinessCard__c rec, CM_BusinessCard_Controller.CM_CardData d) {
        rec.Company__c     = d.Company;
        rec.TaxId__c       = d.TaxId;
        rec.LastName__c    = d.LastName;
        rec.FirstName__c   = d.FirstName;
        rec.Title__c       = d.Title;
        rec.Email__c       = d.Email;
        rec.Phone__c       = d.Phone;
        rec.MobilePhone__c = d.MobilePhone;
        rec.Website__c     = d.Website;
        rec.Street__c      = d.Street;
        rec.City__c        = d.City;
        rec.State__c       = d.State;
        rec.PostalCode__c  = d.PostalCode;
        rec.Country__c     = d.Country;
        rec.Description__c = d.Description;
    }

    private static CM_BusinessCard__c cloneSkeleton(CM_BusinessCard__c seed) {
        CM_BusinessCard__c x = new CM_BusinessCard__c();
        x.BatchId__c           = seed.BatchId__c;
        x.ContentDocumentId__c = seed.ContentDocumentId__c;
        x.ContentVersionId__c  = seed.ContentVersionId__c;
        x.FileHash__c          = seed.FileHash__c;
        return x;
    }

    private static String extractJsonArray(String s) {
        if (String.isBlank(s)) return '[]';
        String x = s.trim();
        if (x.startsWith('```json')) x = x.substring(7).trim();
        else if (x.startsWith('```')) x = x.substring(3).trim();
        if (x.endsWith('```')) x = x.substring(0, x.length() - 3).trim();
        Integer a = x.indexOf('['), b = x.lastIndexOf(']');
        if (a < 0 || b <= a) return null;
        return x.substring(a, b + 1);
    }

    private static String shortId() {
        String seed = String.valueOf(System.now().getTime()) + ':' + Math.random();
        String hex = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(seed)));
        return hex.substring(0, 6);
    }

    private static String appendRemark(String existing, String part) {
        String base = String.isBlank(existing) ? '' : (existing + ' | ');
        String out = base + (String.isBlank(part) ? '' : part);
        return (out.length() <= 255) ? out : out.substring(0, 255);
    }

    private static List<CM_BusinessCard_Controller.CM_CardData> parseLlmOutput(String llmOutput) {
        if (llmOutput != null && llmOutput.trim() == '[]') {
            return new List<CM_BusinessCard_Controller.CM_CardData>();
        }
        String jsonArray = extractJsonArray(llmOutput);
        if (jsonArray == null || jsonArray.trim() == '' || jsonArray.trim() == '[]') {
            return new List<CM_BusinessCard_Controller.CM_CardData>();
        }
        return (List<CM_BusinessCard_Controller.CM_CardData>)
            JSON.deserialize(jsonArray, List<CM_BusinessCard_Controller.CM_CardData>.class);
    }
}