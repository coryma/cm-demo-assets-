public with sharing class CMQbrMeetingPrepController {
    private static final Integer DEFAULT_SEARCH_LIMIT = 50;
    private static final Integer MAX_SEARCH_LIMIT = 100;
    private static final String PROMPT_TEMPLATE_NAME = 'CM_CrossRole_MeetingBrief_Gen';
    private static final String SUPPLIER_INTRO_PROMPT_TEMPLATE_NAME = 'CM_QBR_Supplier_Intro_From_File';
    private static final String PPTX_TEMPLATE_STATIC_RESOURCE_NAME = 'CM_QBR_PPTX_Template';
    private static final String RICH_TEXT_CONTENT_KEY = 'rich_text_content';
    private static final String PPTX_RELATIONSHIP_NS = 'http://schemas.openxmlformats.org/package/2006/relationships';
    private static final String PPTX_SLIDE_RELATIONSHIP_TYPE =
        'http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide';
    private static final String PPTX_SLIDE_LAYOUT_RELATIONSHIP_TYPE =
        'http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout';
    private static final String PPTX_NOTES_SLIDE_RELATIONSHIP_TYPE =
        'http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide';
    private static final String PPTX_NOTES_MASTER_RELATIONSHIP_TYPE =
        'http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster';
    private static final Integer PRESENTATION_STATIC_RELATIONSHIP_COUNT = 7;
    private static final Integer PRESENTATION_BASE_SLIDE_ID = 255;
    private static final Integer MAX_SLIDE_BULLET_COUNT = 5;
    private static final Integer MAX_SLIDE_TABLE_ROW_COUNT = 6;
    private static final Integer MAX_CONTENT_VISUAL_LINE_UNITS = 14;
    private static final Integer BODY_FONT_SIZE = 1600;
    private static final Integer INDENTED_FONT_SIZE = 1300;
    private static final Integer MAX_PPTX_LINE_LENGTH = 140;
    private static final Integer MAX_PPTX_NOTES_LINE_LENGTH = 240;
    private static final String COVER_LAYOUT_TARGET = '../slideLayouts/slideLayout1.xml';
    private static final String CONTENT_LAYOUT_TARGET = '../slideLayouts/slideLayout2.xml';
    private static final Integer SLIDE_CONTENT_MAX_LENGTH = 32000;
    private static final List<String> SPENDING_HINT_KEYWORDS = new List<String>{
        'spend', 'spending', 'amount', 'revenue', 'ytd', 'yoy', 'mix', 'share',
        '採購', '營收', '金額', '產品線', '產品類別', '佔比', '占比', '商務項目', 'item'
    };
    private static final List<String> SCORECARD_HINT_KEYWORDS = new List<String>{
        'kpi', 'otd', 'dppm', 'score', 'target', 'actual', 'weight', 'cost', 'service',
        '評分', '目標', '實際', '權重', '品質', '交期'
    };

    private static final List<String> FIXED_TOPICS = new List<String>{
        'XXX公司簡介',
        '供應商公司簡介',
        'XXX公司營運概況暨XXX新產品技術、組織變動簡介',
        '供應商公司營運概況暨新產品技術、產能簡介',
        '上季 QBR 改善狀況追蹤',
        '雙方商務指標回顧',
        '品質問題討論',
        '未來預測需求',
        '重大議題商討'
    };

    @TestVisible
    static String testPromptResponse;
    @TestVisible
    static String testSupplierIntroPromptResponse;
    @TestVisible
    static Blob testPptxTemplateBlob;

    public class FocusContextPayload {
        @AuraEnabled public Id focusCompanyId;
        @AuraEnabled public String focusCompanyName;
        @AuraEnabled public Boolean hasFocusCompany;
        @AuraEnabled public List<String> fixedTopics;
    }

    public class AccountRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String industry;
        @AuraEnabled public String type;
        @AuraEnabled public String website;
        @AuraEnabled public Datetime lastModifiedDate;
    }

    public class GenerateResult {
        @AuraEnabled public Id meetingId;
        @AuraEnabled public String meetingName;
        @AuraEnabled public String meetingUrl;
        @AuraEnabled public String generatedAt;
        @AuraEnabled public String message;
    }

    public class EditableSlidesPayload {
        @AuraEnabled public Id meetingId;
        @AuraEnabled public String meetingName;
        @AuraEnabled public String pageOneTitle;
        @AuraEnabled public String pageTwoTitle;
        @AuraEnabled public String pageThreeTitle;
        @AuraEnabled public String pageFourTitle;
        @AuraEnabled public String pageFiveTitle;
        @AuraEnabled public String pageSixTitle;
        @AuraEnabled public String pageSevenTitle;
        @AuraEnabled public String pageEightTitle;
        @AuraEnabled public String pageNineTitle;
        @AuraEnabled public String pageOneRichText;
        @AuraEnabled public String pageTwoRichText;
        @AuraEnabled public String pageThreeRichText;
        @AuraEnabled public String pageFourRichText;
        @AuraEnabled public String pageFiveRichText;
        @AuraEnabled public String pageSixRichText;
        @AuraEnabled public String pageSevenRichText;
        @AuraEnabled public String pageEightRichText;
        @AuraEnabled public String pageNineRichText;
        @AuraEnabled public Boolean pageFiveHasTable;
        @AuraEnabled public Boolean pageSixHasTable;
        @AuraEnabled public List<String> pageFiveTableHeaders;
        @AuraEnabled public List<String> pageSixTableHeaders;
        @AuraEnabled public List<List<String>> pageFiveAvailableRows;
        @AuraEnabled public List<List<String>> pageSixAvailableRows;
        @AuraEnabled public List<Integer> pageFiveSelectedRowIndexes;
        @AuraEnabled public List<Integer> pageSixSelectedRowIndexes;
    }

    public class PresentationTopicOption {
        @AuraEnabled public String key;
        @AuraEnabled public Integer slideNumber;
        @AuraEnabled public String topicTitle;
        @AuraEnabled public String slideTitle;
        @AuraEnabled public Boolean selected;
    }

    public class PresentationExportOptionsPayload {
        @AuraEnabled public Id meetingId;
        @AuraEnabled public String meetingName;
        @AuraEnabled public List<PresentationTopicOption> topics;
    }

    public class PresentationFilePayload {
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public String fileName;
        @AuraEnabled public String fileUrl;
        @AuraEnabled public String message;
    }

    @AuraEnabled(cacheable=true)
    public static FocusContextPayload getFocusContext() {
        FocusContextPayload payload = new FocusContextPayload();
        Account activeDemoTarget = getActiveDemoTargetAccount(false);

        payload.focusCompanyId = activeDemoTarget == null ? null : activeDemoTarget.Id;
        payload.focusCompanyName = activeDemoTarget == null ? null : activeDemoTarget.Name;
        payload.hasFocusCompany = activeDemoTarget != null;
        payload.fixedTopics = new List<String>();
        payload.fixedTopics.addAll(FIXED_TOPICS);
        return payload;
    }

    @AuraEnabled(cacheable=true)
    public static List<AccountRow> searchRootAccounts(String searchTerm, Integer limitSize) {
        Integer safeLimit = limitSize == null ? DEFAULT_SEARCH_LIMIT : limitSize;
        if (safeLimit < 1) {
            safeLimit = DEFAULT_SEARCH_LIMIT;
        }
        if (safeLimit > MAX_SEARCH_LIMIT) {
            safeLimit = MAX_SEARCH_LIMIT;
        }

        String normalizedSearchTerm = searchTerm == null ? '' : searchTerm.trim();
        String likeTerm = '%' + normalizedSearchTerm + '%';

        Account activeDemoTarget = getActiveDemoTargetAccount(false);
        Id focusCompanyId = activeDemoTarget == null ? null : activeDemoTarget.Id;

        List<Account> accounts;
        if (String.isBlank(normalizedSearchTerm)) {
            accounts = focusCompanyId == null
                ? [
                    SELECT Id, Name, Industry, Type, Website, LastModifiedDate
                    FROM Account
                    ORDER BY LastModifiedDate DESC
                    LIMIT :safeLimit
                ]
                : [
                    SELECT Id, Name, Industry, Type, Website, LastModifiedDate
                    FROM Account
                    WHERE Id != :focusCompanyId
                    ORDER BY LastModifiedDate DESC
                    LIMIT :safeLimit
                ];
        } else {
            accounts = focusCompanyId == null
                ? [
                    SELECT Id, Name, Industry, Type, Website, LastModifiedDate
                    FROM Account
                    WHERE Name LIKE :likeTerm
                    ORDER BY Name
                    LIMIT :safeLimit
                ]
                : [
                    SELECT Id, Name, Industry, Type, Website, LastModifiedDate
                    FROM Account
                    WHERE Name LIKE :likeTerm
                    AND Id != :focusCompanyId
                    ORDER BY Name
                    LIMIT :safeLimit
                ];
        }

        List<AccountRow> rows = new List<AccountRow>();
        for (Account accountRecord : accounts) {
            AccountRow row = new AccountRow();
            row.id = accountRecord.Id;
            row.name = accountRecord.Name;
            row.industry = accountRecord.Industry;
            row.type = accountRecord.Type;
            row.website = accountRecord.Website;
            row.lastModifiedDate = accountRecord.LastModifiedDate;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static GenerateResult generateMeetingPreparation(
        Id rootAccountId,
        String focusDepartment,
        String quarterOverride
    ) {
        if (rootAccountId == null) {
            throw new AuraHandledException('Please select a Root Account.');
        }

        String normalizedDepartment = normalizeText(focusDepartment);
        if (String.isBlank(normalizedDepartment)) {
            throw new AuraHandledException('Focus Department is required.');
        }

        Account focusCompany = getActiveDemoTargetAccount(true);
        Account rootAccount = [
            SELECT Id, Name
            FROM Account
            WHERE Id = :rootAccountId
            LIMIT 1
        ];

        String promptResponse = callPromptTemplate(
            focusCompany.Name,
            normalizedDepartment,
            rootAccount.Id
        );
        Map<Integer, String> slidePayloadByNumber = extractSlidePayloads(promptResponse);

        CM_QBR_Meeting__c meetingRecord = new CM_QBR_Meeting__c(
            Focus_Company__c = focusCompany.Id,
            Focus_Department__c = normalizedDepartment,
            Root_Account__c = rootAccount.Id,
            Quarter__c = resolveQuarterValue(quarterOverride, Date.today()),
            Status__c = 'Generated',
            Last_Generated_At__c = System.now(),
            Prompt_Response__c = promptResponse,
            Slide_01_Content__c = slidePayloadByNumber.get(1),
            Slide_02_Content__c = slidePayloadByNumber.get(2),
            Slide_03_Content__c = slidePayloadByNumber.get(3),
            Slide_04_Content__c = slidePayloadByNumber.get(4),
            Slide_05_Content__c = slidePayloadByNumber.get(5),
            Slide_06_Content__c = slidePayloadByNumber.get(6),
            Slide_07_Content__c = slidePayloadByNumber.get(7),
            Slide_08_Content__c = slidePayloadByNumber.get(8),
            Slide_09_Content__c = slidePayloadByNumber.get(9)
        );
        insert meetingRecord;

        meetingRecord = [
            SELECT Id, Name, Last_Generated_At__c
            FROM CM_QBR_Meeting__c
            WHERE Id = :meetingRecord.Id
            LIMIT 1
        ];

        GenerateResult result = new GenerateResult();
        result.meetingId = meetingRecord.Id;
        result.meetingName = meetingRecord.Name;
        result.meetingUrl = '/lightning/r/CM_QBR_Meeting__c/' + String.valueOf(meetingRecord.Id) + '/view';
        result.generatedAt = meetingRecord.Last_Generated_At__c == null
            ? null
            : meetingRecord.Last_Generated_At__c.format('yyyy-MM-dd HH:mm');
        result.message = 'QBR meeting preparation generated.';
        return result;
    }

    @AuraEnabled(cacheable=false)
    public static GenerateResult findLatestGeneratedMeeting(Id rootAccountId, String quarterOverride) {
        if (rootAccountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }

        String resolvedQuarter = resolveQuarterValue(quarterOverride, Date.today());
        List<CM_QBR_Meeting__c> meetingRecords = [
            SELECT Id, Name, Last_Generated_At__c
            FROM CM_QBR_Meeting__c
            WHERE Root_Account__c = :rootAccountId
            AND Quarter__c = :resolvedQuarter
            AND Status__c = 'Generated'
            ORDER BY Last_Generated_At__c DESC NULLS LAST, LastModifiedDate DESC
            LIMIT 1
        ];

        GenerateResult result = new GenerateResult();
        if (meetingRecords.isEmpty()) {
            result.message = 'No generated QBR default found for ' + resolvedQuarter + '. Please run QBR Setup first.';
            return result;
        }

        CM_QBR_Meeting__c meetingRecord = meetingRecords[0];
        result.meetingId = meetingRecord.Id;
        result.meetingName = meetingRecord.Name;
        result.meetingUrl = '/lightning/r/CM_QBR_Meeting__c/' + String.valueOf(meetingRecord.Id) + '/view';
        result.generatedAt = meetingRecord.Last_Generated_At__c == null
            ? null
            : meetingRecord.Last_Generated_At__c.format('yyyy-MM-dd HH:mm');
        result.message = 'Loaded generated QBR default for ' + resolvedQuarter + '.';
        return result;
    }

    @AuraEnabled(cacheable=false)
    public static EditableSlidesPayload getEditableSlides(Id meetingId) {
        CM_QBR_Meeting__c meetingRecord = [
            SELECT Id, Name, Slide_01_Content__c, Slide_02_Content__c,
                   Slide_03_Content__c, Slide_04_Content__c,
                   Slide_05_Content__c, Slide_06_Content__c,
                   Slide_07_Content__c, Slide_08_Content__c, Slide_09_Content__c
            FROM CM_QBR_Meeting__c
            WHERE Id = :meetingId
            LIMIT 1
        ];
        return buildEditableSlidesPayload(meetingRecord);
    }

    @AuraEnabled
    public static EditableSlidesPayload saveEditableSlides(
        Id meetingId,
        String pageOneTitle,
        String pageTwoTitle,
        String pageThreeTitle,
        String pageFourTitle,
        String pageFiveTitle,
        String pageSixTitle,
        String pageSevenTitle,
        String pageEightTitle,
        String pageNineTitle,
        String pageOneRichText,
        String pageTwoRichText,
        String pageThreeRichText,
        String pageFourRichText,
        List<Integer> pageFiveSelectedRowIndexes,
        List<Integer> pageSixSelectedRowIndexes,
        String pageSevenRichText,
        String pageEightRichText,
        String pageNineRichText
    ) {
        CM_QBR_Meeting__c meetingRecord = [
            SELECT Id, Name, Slide_01_Content__c, Slide_02_Content__c,
                   Slide_03_Content__c, Slide_04_Content__c,
                   Slide_05_Content__c, Slide_06_Content__c,
                   Slide_07_Content__c, Slide_08_Content__c, Slide_09_Content__c
            FROM CM_QBR_Meeting__c
            WHERE Id = :meetingId
            LIMIT 1
        ];

        Map<String, Object> slideOne = parseSlideFromField(meetingRecord.Slide_01_Content__c, 1);
        Map<String, Object> slideTwo = parseSlideFromField(meetingRecord.Slide_02_Content__c, 2);
        Map<String, Object> slideThree = parseSlideFromField(meetingRecord.Slide_03_Content__c, 3);
        Map<String, Object> slideFour = parseSlideFromField(meetingRecord.Slide_04_Content__c, 4);
        Map<String, Object> slideFive = parseSlideFromField(meetingRecord.Slide_05_Content__c, 5);
        Map<String, Object> slideSix = parseSlideFromField(meetingRecord.Slide_06_Content__c, 6);
        Map<String, Object> slideSeven = parseSlideFromField(meetingRecord.Slide_07_Content__c, 7);
        Map<String, Object> slideEight = parseSlideFromField(meetingRecord.Slide_08_Content__c, 8);
        Map<String, Object> slideNine = parseSlideFromField(meetingRecord.Slide_09_Content__c, 9);

        applySlideTitleOverride(slideOne, pageOneTitle);
        applySlideTitleOverride(slideTwo, pageTwoTitle);
        applySlideTitleOverride(slideThree, pageThreeTitle);
        applySlideTitleOverride(slideFour, pageFourTitle);
        applySlideTitleOverride(slideFive, pageFiveTitle);
        applySlideTitleOverride(slideSix, pageSixTitle);
        applySlideTitleOverride(slideSeven, pageSevenTitle);
        applySlideTitleOverride(slideEight, pageEightTitle);
        applySlideTitleOverride(slideNine, pageNineTitle);

        slideOne.put(
            RICH_TEXT_CONTENT_KEY,
            normalizeRichTextHtml(pageOneRichText, slideOne)
        );
        slideTwo.put(
            RICH_TEXT_CONTENT_KEY,
            normalizeRichTextHtml(pageTwoRichText, slideTwo)
        );
        if (pageThreeRichText != null) {
            slideThree.put(
                RICH_TEXT_CONTENT_KEY,
                normalizeRichTextHtml(pageThreeRichText, slideThree)
            );
        }
        if (pageFourRichText != null) {
            slideFour.put(
                RICH_TEXT_CONTENT_KEY,
                normalizeRichTextHtml(pageFourRichText, slideFour)
            );
        }
        if (pageFiveSelectedRowIndexes != null) {
            applySelectedTableRows(slideFive, pageFiveSelectedRowIndexes);
            slideFive.put(
                RICH_TEXT_CONTENT_KEY,
                normalizeRichTextHtml(null, slideFive)
            );
        }
        if (pageSixSelectedRowIndexes != null) {
            applySelectedTableRows(slideSix, pageSixSelectedRowIndexes);
            slideSix.put(
                RICH_TEXT_CONTENT_KEY,
                normalizeRichTextHtml(null, slideSix)
            );
        }
        if (pageSevenRichText != null) {
            slideSeven.put(
                RICH_TEXT_CONTENT_KEY,
                normalizeRichTextHtml(pageSevenRichText, slideSeven)
            );
        }
        if (pageEightRichText != null) {
            slideEight.put(
                RICH_TEXT_CONTENT_KEY,
                normalizeRichTextHtml(pageEightRichText, slideEight)
            );
        }
        if (pageNineRichText != null) {
            slideNine.put(
                RICH_TEXT_CONTENT_KEY,
                normalizeRichTextHtml(pageNineRichText, slideNine)
            );
        }

        meetingRecord.Slide_01_Content__c = truncate(JSON.serialize(slideOne), SLIDE_CONTENT_MAX_LENGTH);
        meetingRecord.Slide_02_Content__c = truncate(JSON.serialize(slideTwo), SLIDE_CONTENT_MAX_LENGTH);
        meetingRecord.Slide_03_Content__c = truncate(JSON.serialize(slideThree), SLIDE_CONTENT_MAX_LENGTH);
        meetingRecord.Slide_04_Content__c = truncate(JSON.serialize(slideFour), SLIDE_CONTENT_MAX_LENGTH);
        if (pageFiveSelectedRowIndexes != null) {
            meetingRecord.Slide_05_Content__c = truncate(JSON.serialize(slideFive), SLIDE_CONTENT_MAX_LENGTH);
        }
        if (pageSixSelectedRowIndexes != null) {
            meetingRecord.Slide_06_Content__c = truncate(JSON.serialize(slideSix), SLIDE_CONTENT_MAX_LENGTH);
        }
        if (pageSevenRichText != null) {
            meetingRecord.Slide_07_Content__c = truncate(JSON.serialize(slideSeven), SLIDE_CONTENT_MAX_LENGTH);
        }
        if (pageEightRichText != null) {
            meetingRecord.Slide_08_Content__c = truncate(JSON.serialize(slideEight), SLIDE_CONTENT_MAX_LENGTH);
        }
        if (pageNineRichText != null) {
            meetingRecord.Slide_09_Content__c = truncate(JSON.serialize(slideNine), SLIDE_CONTENT_MAX_LENGTH);
        }
        update meetingRecord;

        meetingRecord = [
            SELECT Id, Name, Slide_01_Content__c, Slide_02_Content__c,
                   Slide_03_Content__c, Slide_04_Content__c,
                   Slide_05_Content__c, Slide_06_Content__c,
                   Slide_07_Content__c, Slide_08_Content__c, Slide_09_Content__c
            FROM CM_QBR_Meeting__c
            WHERE Id = :meetingRecord.Id
            LIMIT 1
        ];
        return buildEditableSlidesPayload(meetingRecord);
    }

    private static void applySlideTitleOverride(Map<String, Object> slideMap, String inputTitle) {
        if (slideMap == null || inputTitle == null) {
            return;
        }
        String normalizedTitle = normalizeText(inputTitle);
        if (String.isBlank(normalizedTitle)) {
            return;
        }
        slideMap.put('slide_title', normalizedTitle);
    }

    @AuraEnabled
    public static EditableSlidesPayload regenerateSupplierIntroFromFile(Id meetingId, Id fileId) {
        Id contentDocumentId = resolveContentDocumentId(fileId);

        CM_QBR_Meeting__c meetingRecord = [
            SELECT Id, Name, Focus_Department__c,
                   Focus_Company__c, Focus_Company__r.Name,
                   Root_Account__c, Root_Account__r.Name,
                   Slide_01_Content__c, Slide_02_Content__c,
                   Slide_03_Content__c, Slide_04_Content__c,
                   Slide_05_Content__c, Slide_06_Content__c,
                   Slide_07_Content__c, Slide_08_Content__c, Slide_09_Content__c
            FROM CM_QBR_Meeting__c
            WHERE Id = :meetingId
            LIMIT 1
        ];

        if (meetingRecord.Focus_Company__c == null || meetingRecord.Root_Account__c == null) {
            throw new AuraHandledException('QBR Meeting is missing Focus Company or Root Account.');
        }

        String generatedText = callSupplierIntroPromptTemplate(
            contentDocumentId,
            meetingRecord.Focus_Company__r.Name,
            meetingRecord.Focus_Department__c,
            meetingRecord.Root_Account__r.Name
        );

        Map<String, Object> supplierSlide = extractSupplierIntroSlide(generatedText);
        supplierSlide = normalizeSlide(supplierSlide, 2);
        supplierSlide.put(
            RICH_TEXT_CONTENT_KEY,
            normalizeRichTextHtml(null, supplierSlide)
        );

        meetingRecord.Slide_02_Content__c = truncate(JSON.serialize(supplierSlide), SLIDE_CONTENT_MAX_LENGTH);
        update meetingRecord;

        meetingRecord = [
            SELECT Id, Name, Slide_01_Content__c, Slide_02_Content__c,
                   Slide_03_Content__c, Slide_04_Content__c,
                   Slide_05_Content__c, Slide_06_Content__c,
                   Slide_07_Content__c, Slide_08_Content__c, Slide_09_Content__c
            FROM CM_QBR_Meeting__c
            WHERE Id = :meetingRecord.Id
            LIMIT 1
        ];
        return buildEditableSlidesPayload(meetingRecord);
    }

    @AuraEnabled(cacheable=false)
    public static PresentationExportOptionsPayload getPresentationExportOptions(Id meetingId) {
        if (meetingId == null) {
            throw new AuraHandledException('QBR Meeting Id is required.');
        }

        CM_QBR_Meeting__c meetingRecord = [
            SELECT Id, Name,
                   Focus_Company__r.Name, Root_Account__r.Name,
                   Slide_01_Content__c, Slide_02_Content__c, Slide_03_Content__c,
                   Slide_04_Content__c, Slide_05_Content__c, Slide_06_Content__c,
                   Slide_07_Content__c, Slide_08_Content__c, Slide_09_Content__c
            FROM CM_QBR_Meeting__c
            WHERE Id = :meetingId
            LIMIT 1
        ];

        PresentationExportOptionsPayload payload = new PresentationExportOptionsPayload();
        payload.meetingId = meetingRecord.Id;
        payload.meetingName = meetingRecord.Name;
        payload.topics = new List<PresentationTopicOption>();
        String focusCompanyName = meetingRecord.Focus_Company__r == null
            ? null
            : meetingRecord.Focus_Company__r.Name;
        String rootAccountName = meetingRecord.Root_Account__r == null
            ? null
            : meetingRecord.Root_Account__r.Name;

        for (Integer slideNumber = 1; slideNumber <= FIXED_TOPICS.size(); slideNumber++) {
            Map<String, Object> slide = parseSlideFromField(
                getSlideContentByNumber(meetingRecord, slideNumber),
                slideNumber
            );
            PresentationTopicOption option = new PresentationTopicOption();
            option.key = 'SLIDE_' + String.valueOf(slideNumber);
            option.slideNumber = slideNumber;
            option.topicTitle = resolvePresentationTopicTitle(
                slideNumber,
                slide,
                focusCompanyName,
                rootAccountName
            );
            option.slideTitle = normalizeText(castString(slide.get('slide_title')));
            if (String.isBlank(option.slideTitle)) {
                option.slideTitle = option.topicTitle;
            }
            option.selected = true;
            payload.topics.add(option);
        }
        return payload;
    }

    @AuraEnabled
    public static PresentationFilePayload generatePresentationFile(
        Id meetingId,
        List<Integer> selectedSlideNumbers
    ) {
        if (meetingId == null) {
            throw new AuraHandledException('QBR Meeting Id is required.');
        }

        List<Integer> selectedNumbers = normalizeRequestedSlideNumbers(selectedSlideNumbers);
        if (selectedNumbers.isEmpty()) {
            throw new AuraHandledException('Please select at least 1 topic.');
        }

        CM_QBR_Meeting__c meetingRecord = [
            SELECT Id, Name, Quarter__c,
                   Focus_Company__r.Name, Root_Account__r.Name,
                   Slide_01_Content__c, Slide_02_Content__c, Slide_03_Content__c,
                   Slide_04_Content__c, Slide_05_Content__c, Slide_06_Content__c,
                   Slide_07_Content__c, Slide_08_Content__c, Slide_09_Content__c
            FROM CM_QBR_Meeting__c
            WHERE Id = :meetingId
            LIMIT 1
        ];

        String timestamp = Datetime.now().format('yyyyMMdd_HHmmss');
        String quarterLabel = normalizeText(meetingRecord.Quarter__c);
        if (String.isBlank(quarterLabel)) {
            quarterLabel = deriveQuarter(Date.today());
        }
        String fileTitle = 'QBR_Presentation_' + quarterLabel.replace(' ', '_') + '_' + timestamp;
        String fileName = fileTitle + '.pptx';

        ContentVersion fileVersion = new ContentVersion(
            Title = fileTitle,
            PathOnClient = fileName,
            VersionData = buildPresentationPptxDocument(meetingRecord, selectedNumbers)
        );
        insert fileVersion;

        ContentVersion savedFileVersion = [
            SELECT Id, ContentDocumentId, PathOnClient
            FROM ContentVersion
            WHERE Id = :fileVersion.Id
            LIMIT 1
        ];

        PresentationFilePayload payload = new PresentationFilePayload();
        payload.contentVersionId = savedFileVersion.Id;
        payload.contentDocumentId = savedFileVersion.ContentDocumentId;
        payload.fileName = savedFileVersion.PathOnClient;
        payload.fileUrl = '/lightning/r/ContentDocument/' + String.valueOf(savedFileVersion.ContentDocumentId) + '/view';
        payload.message = 'Presentation generated.';
        return payload;
    }

    private static Account getActiveDemoTargetAccount(Boolean throwWhenMissing) {
        List<Account> activeTargets = [
            SELECT Id, Name
            FROM Account
            WHERE CM_Is_Demo_Target__c = true
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];

        if (activeTargets.isEmpty()) {
            if (throwWhenMissing) {
                throw new AuraHandledException(
                    'Demo target Account is not configured. Please set Focus Company in Demo Setup first.'
                );
            }
            return null;
        }
        return activeTargets[0];
    }

    private static String callPromptTemplate(
        String focusCompanyName,
        String focusDepartment,
        Id rootAccountId
    ) {
        if (Test.isRunningTest() && testPromptResponse != null) {
            return testPromptResponse;
        }

        try {
            Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
            inputParams.put('Input:FocusCompany', toPrimitiveInput(focusCompanyName));
            inputParams.put('Input:FocusDepartment', toPrimitiveInput(focusDepartment));
            inputParams.put('Input:RootAccount', toSObjectInput(rootAccountId));

            ConnectApi.EinsteinPromptTemplateGenerationsInput promptInput =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            promptInput.inputParams = inputParams;
            promptInput.isPreview = false;

            ConnectApi.EinsteinLlmAdditionalConfigInput additionalConfig =
                new ConnectApi.EinsteinLlmAdditionalConfigInput();
            additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
            promptInput.additionalConfig = additionalConfig;

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation promptResult =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(PROMPT_TEMPLATE_NAME, promptInput);

            if (promptResult == null || promptResult.generations == null || promptResult.generations.isEmpty()) {
                throw new AuraHandledException('Prompt template returned no generation text.');
            }

            String generatedText = promptResult.generations[0].text;
            if (String.isBlank(generatedText)) {
                throw new AuraHandledException('Prompt template returned empty text.');
            }
            return generatedText;
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Prompt generation failed: ' + ex.getMessage());
        }
    }

    private static String callSupplierIntroPromptTemplate(
        Id contentDocumentId,
        String focusCompanyName,
        String focusDepartment,
        String rootAccountName
    ) {
        if (Test.isRunningTest() && testSupplierIntroPromptResponse != null) {
            return testSupplierIntroPromptResponse;
        }

        try {
            Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
            inputParams.put('Input:supplierFile', toSObjectInput(contentDocumentId));
            inputParams.put('Input:FocusCompany', toPrimitiveInput(focusCompanyName));
            inputParams.put('Input:FocusDepartment', toPrimitiveInput(focusDepartment));
            inputParams.put('Input:RootAccount', toPrimitiveInput(rootAccountName));

            ConnectApi.EinsteinPromptTemplateGenerationsInput promptInput =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            promptInput.inputParams = inputParams;
            promptInput.isPreview = false;

            ConnectApi.EinsteinLlmAdditionalConfigInput additionalConfig =
                new ConnectApi.EinsteinLlmAdditionalConfigInput();
            additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
            promptInput.additionalConfig = additionalConfig;

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation promptResult =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                    SUPPLIER_INTRO_PROMPT_TEMPLATE_NAME,
                    promptInput
                );

            if (promptResult == null || promptResult.generations == null || promptResult.generations.isEmpty()) {
                throw new AuraHandledException('Supplier intro prompt returned no generation text.');
            }

            String generatedText = promptResult.generations[0].text;
            if (String.isBlank(generatedText)) {
                throw new AuraHandledException('Supplier intro prompt returned empty text.');
            }
            return generatedText;
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Supplier intro prompt failed: ' + ex.getMessage());
        }
    }

    private static EditableSlidesPayload buildEditableSlidesPayload(CM_QBR_Meeting__c meetingRecord) {
        Map<String, Object> slideOne = parseSlideFromField(meetingRecord.Slide_01_Content__c, 1);
        Map<String, Object> slideTwo = parseSlideFromField(meetingRecord.Slide_02_Content__c, 2);
        Map<String, Object> slideThree = parseSlideFromField(meetingRecord.Slide_03_Content__c, 3);
        Map<String, Object> slideFour = parseSlideFromField(meetingRecord.Slide_04_Content__c, 4);
        Map<String, Object> slideFive = parseSlideFromField(meetingRecord.Slide_05_Content__c, 5);
        Map<String, Object> slideSix = parseSlideFromField(meetingRecord.Slide_06_Content__c, 6);
        Map<String, Object> slideSeven = parseSlideFromField(meetingRecord.Slide_07_Content__c, 7);
        Map<String, Object> slideEight = parseSlideFromField(meetingRecord.Slide_08_Content__c, 8);
        Map<String, Object> slideNine = parseSlideFromField(meetingRecord.Slide_09_Content__c, 9);
        Map<String, Object> slideFiveTableData = normalizeTableData(slideFive.get('table_data'));
        Map<String, Object> slideSixTableData = normalizeTableData(slideSix.get('table_data'));

        EditableSlidesPayload payload = new EditableSlidesPayload();
        payload.meetingId = meetingRecord.Id;
        payload.meetingName = meetingRecord.Name;
        payload.pageOneTitle = castString(slideOne.get('slide_title'));
        payload.pageTwoTitle = castString(slideTwo.get('slide_title'));
        payload.pageThreeTitle = castString(slideThree.get('slide_title'));
        payload.pageFourTitle = castString(slideFour.get('slide_title'));
        payload.pageFiveTitle = castString(slideFive.get('slide_title'));
        payload.pageSixTitle = castString(slideSix.get('slide_title'));
        payload.pageSevenTitle = castString(slideSeven.get('slide_title'));
        payload.pageEightTitle = castString(slideEight.get('slide_title'));
        payload.pageNineTitle = castString(slideNine.get('slide_title'));
        payload.pageOneRichText = resolveEditableRichText(slideOne);
        payload.pageTwoRichText = resolveEditableRichText(slideTwo);
        payload.pageThreeRichText = resolveEditableRichText(slideThree);
        payload.pageFourRichText = resolveEditableRichText(slideFour);
        payload.pageFiveRichText = resolveEditableRichText(slideFive);
        payload.pageSixRichText = resolveEditableRichText(slideSix);
        payload.pageSevenRichText = resolveEditableRichText(slideSeven);
        payload.pageEightRichText = resolveEditableRichText(slideEight);
        payload.pageNineRichText = resolveEditableRichText(slideNine);
        payload.pageFiveHasTable = toBoolean(slideFiveTableData.get('has_table'));
        payload.pageSixHasTable = toBoolean(slideSixTableData.get('has_table'));
        payload.pageFiveTableHeaders = normalizeStringList(slideFiveTableData.get('headers'));
        payload.pageSixTableHeaders = normalizeStringList(slideSixTableData.get('headers'));
        payload.pageFiveAvailableRows = normalizeStringMatrix(
            slideFiveTableData.get('available_rows'),
            payload.pageFiveTableHeaders.size()
        );
        payload.pageSixAvailableRows = normalizeStringMatrix(
            slideSixTableData.get('available_rows'),
            payload.pageSixTableHeaders.size()
        );
        payload.pageFiveSelectedRowIndexes = normalizeSelectedIndexes(
            normalizeIntegerList(slideFiveTableData.get('selected_row_indexes')),
            payload.pageFiveAvailableRows.size()
        );
        payload.pageSixSelectedRowIndexes = normalizeSelectedIndexes(
            normalizeIntegerList(slideSixTableData.get('selected_row_indexes')),
            payload.pageSixAvailableRows.size()
        );
        return payload;
    }

    private static Map<String, Object> parseSlideFromField(String slideJson, Integer slideNumber) {
        if (String.isBlank(slideJson)) {
            return normalizeSlide(new Map<String, Object>(), slideNumber);
        }

        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(slideJson);
            if (parsed == null) {
                return normalizeSlide(new Map<String, Object>(), slideNumber);
            }
            return normalizeSlide(parsed, slideNumber);
        } catch (Exception ex) {
            return normalizeSlide(new Map<String, Object>(), slideNumber);
        }
    }

    private static Map<String, Object> extractSupplierIntroSlide(String rawPromptResponse) {
        String normalized = normalizePromptOutput(rawPromptResponse);

        Map<String, Object> responsePayload;
        try {
            responsePayload = (Map<String, Object>) JSON.deserializeUntyped(normalized);
        } catch (Exception ex) {
            throw new AuraHandledException('Supplier intro prompt output is not valid JSON: ' + ex.getMessage());
        }

        if (responsePayload == null) {
            throw new AuraHandledException('Supplier intro prompt output is empty.');
        }

        if (responsePayload.containsKey('slide')) {
            Map<String, Object> singleSlide = castMap(responsePayload.get('slide'));
            if (singleSlide != null) {
                return singleSlide;
            }
        }

        if (responsePayload.containsKey('slides')) {
            List<Object> slides = castList(responsePayload.get('slides'));
            if (slides != null && !slides.isEmpty()) {
                for (Object slideObj : slides) {
                    Map<String, Object> slideMap = castMap(slideObj);
                    if (slideMap == null) {
                        continue;
                    }
                    Integer slideNumber = toInteger(slideMap.get('slide_number'));
                    if (slideNumber == 2) {
                        return slideMap;
                    }
                }
                Map<String, Object> firstSlide = castMap(slides[0]);
                if (firstSlide != null) {
                    return firstSlide;
                }
            }
            throw new AuraHandledException('Supplier intro prompt output contains empty slides.');
        }

        return responsePayload;
    }

    private static String resolveEditableRichText(Map<String, Object> slideMap) {
        String richText = normalizeText(castString(slideMap.get(RICH_TEXT_CONTENT_KEY)));
        if (!String.isBlank(richText)) {
            return richText;
        }
        return buildRichTextFromSlide(slideMap);
    }

    private static String normalizeRichTextHtml(String candidateHtml, Map<String, Object> fallbackSlide) {
        String normalizedHtml = normalizeText(candidateHtml);
        if (String.isBlank(normalizedHtml)) {
            normalizedHtml = buildRichTextFromSlide(fallbackSlide);
        }
        return truncate(normalizedHtml, SLIDE_CONTENT_MAX_LENGTH);
    }

    private static void applySelectedTableRows(Map<String, Object> slideMap, List<Integer> requestedIndexes) {
        Map<String, Object> tableData = normalizeTableData(slideMap.get('table_data'));
        if (!toBoolean(tableData.get('has_table'))) {
            slideMap.put('table_data', tableData);
            return;
        }

        List<String> headers = normalizeStringList(tableData.get('headers'));
        List<List<String>> availableRows = normalizeStringMatrix(
            tableData.get('available_rows'),
            headers.size()
        );
        List<Integer> selectedIndexes = normalizeSelectedIndexes(requestedIndexes, availableRows.size());
        List<List<String>> selectedRows = pickRowsByIndexes(availableRows, selectedIndexes);

        if (selectedRows.isEmpty()) {
            throw new AuraHandledException('Please select at least 1 table row.');
        }

        tableData.put('has_table', true);
        tableData.put('headers', headers);
        tableData.put('rows', selectedRows);
        tableData.put('available_rows', availableRows);
        tableData.put('selected_row_indexes', selectedIndexes);
        slideMap.put('table_data', tableData);
    }

    private static Map<String, Object> enforceSlideFiveTable(
        Map<String, Object> tableData,
        List<String> bulletPoints
    ) {
        if (isUsableTable(tableData)) {
            return tableData;
        }

        List<List<String>> generatedRows = new List<List<String>>();
        for (String bullet : bulletPoints) {
            if (String.isBlank(normalizeText(bullet))) {
                continue;
            }
            generatedRows.add(splitToItemAndDetail(bullet));
            if (generatedRows.size() >= 5) {
                break;
            }
        }
        if (generatedRows.isEmpty()) {
            generatedRows.add(new List<String>{ '待補充', '待補充' });
        }

        return buildSyntheticTableData(
            new List<String>{ '追蹤議題', '改善措施 / 現況' },
            generatedRows
        );
    }

    private static Map<String, Object> enforceSlideSixSpendingTable(
        Map<String, Object> tableData,
        List<String> bulletPoints
    ) {
        if (isSpendingTable(tableData)) {
            return tableData;
        }

        List<List<String>> spendingRows = extractSpendingRowsFromBulletPoints(bulletPoints);
        if (spendingRows.isEmpty()) {
            spendingRows = extractSpendingRowsFromTable(tableData);
        }
        if (spendingRows.isEmpty()) {
            for (String bullet : bulletPoints) {
                String normalizedBullet = normalizeText(bullet);
                if (String.isBlank(normalizedBullet)) {
                    continue;
                }
                spendingRows.add(
                    new List<String>{
                        deriveSpendingLabel(normalizedBullet),
                        normalizedBullet
                    }
                );
                if (spendingRows.size() >= 5) {
                    break;
                }
            }
        }
        if (spendingRows.isEmpty()) {
            spendingRows.add(new List<String>{ 'Spending', '待補充' });
        }

        return buildSyntheticTableData(
            new List<String>{ '商務項目', '內容' },
            spendingRows
        );
    }

    private static Map<String, Object> buildSyntheticTableData(
        List<String> headers,
        List<List<String>> rows
    ) {
        Map<String, Object> syntheticTable = new Map<String, Object>();
        syntheticTable.put('has_table', true);
        syntheticTable.put('headers', headers == null ? new List<String>() : headers);
        syntheticTable.put('rows', rows == null ? new List<List<String>>() : rows);
        return normalizeTableData(syntheticTable);
    }

    private static Boolean isUsableTable(Map<String, Object> tableData) {
        if (tableData == null || !toBoolean(tableData.get('has_table'))) {
            return false;
        }

        List<String> headers = normalizeStringList(tableData.get('headers'));
        List<List<String>> rows = normalizeStringMatrix(
            tableData.get('available_rows'),
            headers.size()
        );
        if (rows.isEmpty()) {
            rows = normalizeStringMatrix(tableData.get('rows'), headers.size());
        }
        return !headers.isEmpty() && !rows.isEmpty();
    }

    private static Boolean isSpendingTable(Map<String, Object> tableData) {
        if (!isUsableTable(tableData)) {
            return false;
        }

        List<String> headers = normalizeStringList(tableData.get('headers'));
        List<List<String>> rows = normalizeStringMatrix(
            tableData.get('available_rows'),
            headers.size()
        );
        if (rows.isEmpty()) {
            rows = normalizeStringMatrix(tableData.get('rows'), headers.size());
        }

        String mergedHeader = String.join(headers, ' ').toLowerCase();
        Boolean hasSpendingHint = containsKeyword(mergedHeader, SPENDING_HINT_KEYWORDS);
        Boolean hasScorecardHint = containsKeyword(mergedHeader, SCORECARD_HINT_KEYWORDS);
        if (hasSpendingHint) {
            return true;
        }
        if (hasScorecardHint) {
            return false;
        }
        if (headers.size() <= 2) {
            return true;
        }

        for (List<String> row : rows) {
            String mergedRow = joinText(row, ' ');
            if (containsKeyword(mergedRow.toLowerCase(), SPENDING_HINT_KEYWORDS) || containsCurrencyOrAmount(mergedRow)) {
                return true;
            }
        }
        return false;
    }

    private static List<List<String>> extractSpendingRowsFromBulletPoints(List<String> bulletPoints) {
        List<List<String>> rows = new List<List<String>>();
        for (String bullet : bulletPoints) {
            String normalized = normalizeText(bullet);
            if (String.isBlank(normalized)) {
                continue;
            }
            if (!isSpendingLikeText(normalized)) {
                continue;
            }
            rows.add(splitToItemAndDetail(normalized));
            if (rows.size() >= 8) {
                break;
            }
        }
        return rows;
    }

    private static List<List<String>> extractSpendingRowsFromTable(Map<String, Object> tableData) {
        List<List<String>> spendingRows = new List<List<String>>();
        if (tableData == null) {
            return spendingRows;
        }

        List<String> headers = normalizeStringList(tableData.get('headers'));
        Integer columnSize = headers.size();
        List<List<String>> rows = normalizeStringMatrix(tableData.get('available_rows'), columnSize);
        if (rows.isEmpty()) {
            rows = normalizeStringMatrix(tableData.get('rows'), columnSize);
        }

        for (List<String> row : rows) {
            String mergedRow = joinText(row, ' ');
            if (!containsKeyword(mergedRow.toLowerCase(), SPENDING_HINT_KEYWORDS) && !containsCurrencyOrAmount(mergedRow)) {
                continue;
            }
            String item = row.isEmpty() ? deriveSpendingLabel(mergedRow) : normalizeText(row[0]);
            if (String.isBlank(item)) {
                item = deriveSpendingLabel(mergedRow);
            }
            String detail = mergedRow;
            if (row.size() > 1) {
                List<String> detailParts = new List<String>();
                for (Integer index = 1; index < row.size(); index++) {
                    detailParts.add(row[index]);
                }
                detail = joinText(detailParts, ' | ');
            }
            spendingRows.add(new List<String>{ item, detail });
            if (spendingRows.size() >= 8) {
                break;
            }
        }
        return spendingRows;
    }

    private static Boolean isSpendingLikeText(String text) {
        if (String.isBlank(text)) {
            return false;
        }
        String lower = text.toLowerCase();
        if (containsKeyword(lower, SPENDING_HINT_KEYWORDS)) {
            return true;
        }
        if (containsCurrencyOrAmount(text)) {
            return true;
        }
        return (text.contains('%') && (lower.contains('yoy') || lower.contains('share') || lower.contains('佔比') || lower.contains('占比')));
    }

    private static List<String> splitToItemAndDetail(String text) {
        String normalized = normalizeText(text);
        if (String.isBlank(normalized)) {
            return new List<String>{ '商務項目', '待補充' };
        }

        List<String> delimiters = new List<String>{ '：', ':', ' - ', '-', '｜', '|' };
        for (String delimiter : delimiters) {
            Integer index = normalized.indexOf(delimiter);
            if (index <= 0) {
                continue;
            }
            String left = normalizeText(normalized.substring(0, index));
            String right = normalizeText(normalized.substring(index + delimiter.length()));
            if (!String.isBlank(left) && !String.isBlank(right)) {
                return new List<String>{ left, right };
            }
        }

        return new List<String>{
            deriveSpendingLabel(normalized),
            normalized
        };
    }

    private static String deriveSpendingLabel(String text) {
        String lower = normalizeText(text) == null ? '' : normalizeText(text).toLowerCase();
        if (lower.contains('ytd') || lower.contains('採購') || lower.contains('營收')) {
            return 'YTD 金額';
        }
        if (lower.contains('yoy') || lower.contains('年增')) {
            return 'YoY 成長';
        }
        if (lower.contains('產品線') || lower.contains('產品類別') || lower.contains('佔比') || lower.contains('占比') || lower.contains('share') || lower.contains('mix')) {
            return '產品線佔比';
        }
        return '商務指標';
    }

    private static Boolean containsKeyword(String sourceLowerCase, List<String> keywords) {
        if (String.isBlank(sourceLowerCase) || keywords == null || keywords.isEmpty()) {
            return false;
        }
        for (String keyword : keywords) {
            if (String.isBlank(keyword)) {
                continue;
            }
            if (sourceLowerCase.contains(keyword.toLowerCase())) {
                return true;
            }
        }
        return false;
    }

    private static Boolean containsCurrencyOrAmount(String text) {
        if (String.isBlank(text)) {
            return false;
        }
        String lower = text.toLowerCase();
        if (text.contains('$') || lower.contains('usd') || lower.contains('us$') || text.contains('萬') || text.contains('億')) {
            return true;
        }
        return Pattern.matches('.*\\d+(\\.\\d+)?\\s*(m|k|million|billion).*', lower);
    }

    private static String joinText(List<String> values, String delimiter) {
        List<String> normalized = new List<String>();
        if (values == null || values.isEmpty()) {
            return '';
        }

        for (String value : values) {
            normalized.add(value == null ? '' : value);
        }
        return String.join(normalized, delimiter == null ? ' ' : delimiter);
    }

    private static String buildRichTextFromSlide(Map<String, Object> slideMap) {
        String title = normalizeText(castString(slideMap.get('slide_title')));
        List<String> bulletPoints = normalizeStringList(slideMap.get('bullet_points'));
        Map<String, Object> tableData = normalizeTableData(slideMap.get('table_data'));
        String speakerNotes = normalizeText(castString(slideMap.get('speaker_notes')));

        String html = '';
        if (!String.isBlank(title)) {
            html += '<h3>' + escapeHtml(title) + '</h3>';
        }
        if (!bulletPoints.isEmpty()) {
            html += '<ul>';
            for (String bullet : bulletPoints) {
                html += '<li>' + escapeHtml(bullet) + '</li>';
            }
            html += '</ul>';
        }

        html += buildTableHtml(tableData);

        if (!String.isBlank(speakerNotes)) {
            html += '<p><strong>Speaker Notes:</strong></p>';
            html += '<p>' + escapeHtml(speakerNotes).replace('\n', '<br/>') + '</p>';
        }

        if (String.isBlank(html)) {
            return '<p>待補充</p>';
        }
        return html;
    }

    private static String buildTableHtml(Map<String, Object> tableData) {
        if (tableData == null || !toBoolean(tableData.get('has_table'))) {
            return '';
        }

        List<String> headers = normalizeStringList(tableData.get('headers'));
        List<List<String>> rows = normalizeStringMatrix(tableData.get('rows'), headers.size());
        if (headers.isEmpty() || rows.isEmpty()) {
            return '';
        }

        String html = '<table border="1" style="border-collapse:collapse;width:100%;">';
        html += '<thead><tr>';
        for (String header : headers) {
            html += '<th>' + escapeHtml(header) + '</th>';
        }
        html += '</tr></thead><tbody>';
        for (List<String> row : rows) {
            html += '<tr>';
            for (String cell : row) {
                html += '<td>' + escapeHtml(cell).replace('\n', '<br/>') + '</td>';
            }
            html += '</tr>';
        }
        html += '</tbody></table>';
        return html;
    }

    private static String escapeHtml(String text) {
        if (text == null) {
            return '';
        }
        String escaped = text.replace('&', '&amp;');
        escaped = escaped.replace('<', '&lt;');
        escaped = escaped.replace('>', '&gt;');
        escaped = escaped.replace('"', '&quot;');
        escaped = escaped.replace('\'', '&#39;');
        return escaped;
    }

    private static String truncate(String value, Integer maxLength) {
        if (value == null || maxLength == null || maxLength <= 0) {
            return value;
        }
        if (value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength);
    }

    private static Id resolveContentDocumentId(Id fileId) {
        if (fileId == null) {
            throw new AuraHandledException('Please upload a file first.');
        }

        String prefix = String.valueOf(fileId).substring(0, 3);
        if (prefix == '069') {
            return fileId;
        }

        if (prefix == '068') {
            List<ContentVersion> versions = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :fileId
                LIMIT 1
            ];
            if (!versions.isEmpty()) {
                return versions[0].ContentDocumentId;
            }
        }

        List<ContentVersion> latest = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE ContentDocumentId = :fileId
            AND IsLatest = true
            LIMIT 1
        ];
        if (!latest.isEmpty()) {
            return latest[0].ContentDocumentId;
        }

        throw new AuraHandledException('Unable to resolve file document id for prompt generation.');
    }

    private static Map<Integer, String> extractSlidePayloads(String rawPromptResponse) {
        String normalized = normalizePromptOutput(rawPromptResponse);

        Map<String, Object> responsePayload;
        try {
            responsePayload = (Map<String, Object>) JSON.deserializeUntyped(normalized);
        } catch (Exception ex) {
            throw new AuraHandledException('Prompt output is not valid JSON: ' + ex.getMessage());
        }

        if (responsePayload == null || !responsePayload.containsKey('slides')) {
            throw new AuraHandledException('Prompt output must contain "slides".');
        }

        List<Object> slidesRaw = castList(responsePayload.get('slides'));
        if (slidesRaw == null || slidesRaw.isEmpty()) {
            throw new AuraHandledException('Prompt output contains empty slides.');
        }

        Map<Integer, Map<String, Object>> normalizedByNumber = new Map<Integer, Map<String, Object>>();
        for (Integer index = 0; index < slidesRaw.size(); index++) {
            Map<String, Object> slideMap = castMap(slidesRaw[index]);
            if (slideMap == null) {
                throw new AuraHandledException('Slide payload must be a JSON object.');
            }

            Integer slideNumber = toInteger(slideMap.get('slide_number'));
            if (slideNumber == null) {
                slideNumber = index + 1;
            }

            if (slideNumber < 1 || slideNumber > FIXED_TOPICS.size()) {
                throw new AuraHandledException('Slide number out of range: ' + String.valueOf(slideNumber));
            }
            if (normalizedByNumber.containsKey(slideNumber)) {
                throw new AuraHandledException('Duplicate slide number: ' + String.valueOf(slideNumber));
            }

            normalizedByNumber.put(slideNumber, normalizeSlide(slideMap, slideNumber));
        }

        if (normalizedByNumber.size() != FIXED_TOPICS.size()) {
            throw new AuraHandledException('Prompt output must contain exactly 9 slides.');
        }

        Map<Integer, String> payloadByNumber = new Map<Integer, String>();
        for (Integer slideSequence = 1; slideSequence <= FIXED_TOPICS.size(); slideSequence++) {
            if (!normalizedByNumber.containsKey(slideSequence)) {
                throw new AuraHandledException('Missing slide number: ' + String.valueOf(slideSequence));
            }
            payloadByNumber.put(
                slideSequence,
                JSON.serialize(normalizedByNumber.get(slideSequence))
            );
        }
        return payloadByNumber;
    }

    private static Map<String, Object> normalizeSlide(
        Map<String, Object> source,
        Integer slideNumber
    ) {
        Map<String, Object> normalized = new Map<String, Object>();
        normalized.put('slide_number', slideNumber);
        normalized.put('topic_title_fixed', FIXED_TOPICS[slideNumber - 1]);

        String slideTitle = normalizeText(castString(source.get('slide_title')));
        normalized.put(
            'slide_title',
            String.isBlank(slideTitle) ? FIXED_TOPICS[slideNumber - 1] : slideTitle
        );

        List<String> bulletPoints = normalizeStringList(source.get('bullet_points'));
        if (bulletPoints.isEmpty()) {
            bulletPoints.add('待補充');
        }
        normalized.put('bullet_points', bulletPoints);

        Map<String, Object> tableData = normalizeTableData(source.get('table_data'));
        if (slideNumber == 5) {
            tableData = enforceSlideFiveTable(tableData, bulletPoints);
        } else if (slideNumber == 6) {
            tableData = enforceSlideSixSpendingTable(tableData, bulletPoints);
        }
        normalized.put('table_data', tableData);

        String speakerNotes = normalizeText(castString(source.get('speaker_notes')));
        normalized.put('speaker_notes', String.isBlank(speakerNotes) ? '待補充。' : speakerNotes);

        String richTextContent = normalizeText(castString(source.get(RICH_TEXT_CONTENT_KEY)));
        if (!String.isBlank(richTextContent)) {
            normalized.put(
                RICH_TEXT_CONTENT_KEY,
                truncate(richTextContent, SLIDE_CONTENT_MAX_LENGTH)
            );
        }
        return normalized;
    }

    private static Map<String, Object> normalizeTableData(Object rawTableData) {
        Map<String, Object> source = castMap(rawTableData);

        Boolean hasTable = source == null
            ? false
            : toBoolean(source.get('has_table'));
        List<String> headers = source == null
            ? new List<String>()
            : normalizeStringList(source.get('headers'));
        List<List<String>> sourceRows = source == null
            ? new List<List<String>>()
            : normalizeStringMatrix(source.get('rows'), headers.size());
        List<List<String>> availableRows = source == null
            ? new List<List<String>>()
            : normalizeStringMatrix(
                source.containsKey('available_rows') ? source.get('available_rows') : source.get('rows'),
                headers.size()
            );
        List<Integer> selectedIndexes = source == null
            ? new List<Integer>()
            : normalizeIntegerList(source.get('selected_row_indexes'));
        if (selectedIndexes.isEmpty() && source != null && source.containsKey('available_rows')) {
            selectedIndexes = deriveSelectedIndexesFromRows(availableRows, sourceRows);
        }
        selectedIndexes = normalizeSelectedIndexes(selectedIndexes, availableRows.size());
        List<List<String>> selectedRows = pickRowsByIndexes(availableRows, selectedIndexes);

        if (!hasTable || headers.isEmpty() || availableRows.isEmpty() || selectedRows.isEmpty()) {
            hasTable = false;
            headers = new List<String>();
            selectedRows = new List<List<String>>();
            availableRows = new List<List<String>>();
            selectedIndexes = new List<Integer>();
        }

        Map<String, Object> normalized = new Map<String, Object>();
        normalized.put('has_table', hasTable);
        normalized.put('headers', headers);
        normalized.put('rows', selectedRows);
        normalized.put('available_rows', availableRows);
        normalized.put('selected_row_indexes', selectedIndexes);
        return normalized;
    }

    private static List<Integer> deriveSelectedIndexesFromRows(
        List<List<String>> availableRows,
        List<List<String>> selectedRows
    ) {
        List<Integer> indexes = new List<Integer>();
        if (availableRows.isEmpty() || selectedRows.isEmpty()) {
            return indexes;
        }

        Set<String> selectedSignatures = new Set<String>();
        for (List<String> selectedRow : selectedRows) {
            selectedSignatures.add(JSON.serialize(selectedRow));
        }

        for (Integer index = 0; index < availableRows.size(); index++) {
            String signature = JSON.serialize(availableRows[index]);
            if (selectedSignatures.contains(signature)) {
                indexes.add(index);
            }
        }
        return indexes;
    }

    private static List<List<String>> pickRowsByIndexes(
        List<List<String>> sourceRows,
        List<Integer> selectedIndexes
    ) {
        List<List<String>> pickedRows = new List<List<String>>();
        if (sourceRows.isEmpty() || selectedIndexes.isEmpty()) {
            return pickedRows;
        }

        for (Integer selectedIndex : selectedIndexes) {
            if (selectedIndex == null || selectedIndex < 0 || selectedIndex >= sourceRows.size()) {
                continue;
            }
            pickedRows.add(sourceRows[selectedIndex]);
        }
        return pickedRows;
    }

    private static List<Integer> normalizeIntegerList(Object rawValue) {
        List<Integer> normalized = new List<Integer>();
        List<Object> values = castList(rawValue);
        if (values == null || values.isEmpty()) {
            return normalized;
        }

        Set<Integer> seen = new Set<Integer>();
        for (Object item : values) {
            Integer parsed = toInteger(item);
            if (parsed == null || seen.contains(parsed)) {
                continue;
            }
            seen.add(parsed);
            normalized.add(parsed);
        }
        return normalized;
    }

    private static List<Integer> normalizeSelectedIndexes(List<Integer> rawIndexes, Integer maxRows) {
        List<Integer> normalized = new List<Integer>();
        if (maxRows == null || maxRows <= 0) {
            return normalized;
        }

        Set<Integer> seen = new Set<Integer>();
        List<Integer> source = rawIndexes == null ? new List<Integer>() : rawIndexes;
        for (Integer candidate : source) {
            if (candidate == null || candidate < 0 || candidate >= maxRows || seen.contains(candidate)) {
                continue;
            }
            seen.add(candidate);
            normalized.add(candidate);
        }

        if (normalized.isEmpty()) {
            for (Integer index = 0; index < maxRows; index++) {
                normalized.add(index);
            }
        }
        return normalized;
    }

    private static List<Integer> normalizeRequestedSlideNumbers(List<Integer> slideNumbers) {
        List<Integer> normalized = new List<Integer>();
        if (slideNumbers == null || slideNumbers.isEmpty()) {
            return normalized;
        }

        Set<Integer> seen = new Set<Integer>();
        for (Integer slideNumber : slideNumbers) {
            if (slideNumber == null || slideNumber < 1 || slideNumber > FIXED_TOPICS.size() || seen.contains(slideNumber)) {
                continue;
            }
            seen.add(slideNumber);
            normalized.add(slideNumber);
        }
        normalized.sort();
        return normalized;
    }

    private static List<String> normalizeStringList(Object rawValue) {
        List<String> normalized = new List<String>();
        List<Object> values = castList(rawValue);
        if (values == null) {
            return normalized;
        }

        for (Object item : values) {
            String text = normalizeText(castString(item));
            if (String.isBlank(text)) {
                continue;
            }
            normalized.add(text);
        }
        return normalized;
    }

    private static List<List<String>> normalizeStringMatrix(Object rawValue, Integer columnCount) {
        List<List<String>> normalized = new List<List<String>>();
        List<Object> rows = castList(rawValue);
        if (rows == null) {
            return normalized;
        }

        Integer targetColumns = columnCount == null ? 0 : columnCount;
        for (Object rowObj : rows) {
            List<Object> rawCells = castList(rowObj);
            if (rawCells == null) {
                continue;
            }

            List<String> cells = new List<String>();
            for (Object cellObj : rawCells) {
                cells.add(normalizeText(castString(cellObj)));
            }

            if (targetColumns > 0) {
                while (cells.size() < targetColumns) {
                    cells.add('');
                }
                while (cells.size() > targetColumns) {
                    cells.remove(cells.size() - 1);
                }
            }

            if (!cells.isEmpty()) {
                normalized.add(cells);
            }
        }
        return normalized;
    }

    private static String normalizePromptOutput(String rawText) {
        if (String.isBlank(rawText)) {
            throw new AuraHandledException('Prompt output is empty.');
        }

        String normalized = rawText.trim();
        if (normalized.startsWith('```')) {
            normalized = normalized.replace('```json', '').replace('```', '').trim();
        }
        return normalized;
    }

    private static String getSlideContentByNumber(CM_QBR_Meeting__c meetingRecord, Integer slideNumber) {
        if (meetingRecord == null || slideNumber == null) {
            return null;
        }

        if (slideNumber == 1) {
            return meetingRecord.Slide_01_Content__c;
        }
        if (slideNumber == 2) {
            return meetingRecord.Slide_02_Content__c;
        }
        if (slideNumber == 3) {
            return meetingRecord.Slide_03_Content__c;
        }
        if (slideNumber == 4) {
            return meetingRecord.Slide_04_Content__c;
        }
        if (slideNumber == 5) {
            return meetingRecord.Slide_05_Content__c;
        }
        if (slideNumber == 6) {
            return meetingRecord.Slide_06_Content__c;
        }
        if (slideNumber == 7) {
            return meetingRecord.Slide_07_Content__c;
        }
        if (slideNumber == 8) {
            return meetingRecord.Slide_08_Content__c;
        }
        if (slideNumber == 9) {
            return meetingRecord.Slide_09_Content__c;
        }
        return null;
    }

    private static Blob buildPresentationPptxDocument(
        CM_QBR_Meeting__c meetingRecord,
        List<Integer> selectedSlideNumbers
    ) {
        try {
            Blob templateBlob = loadPptxTemplateBlob();
            Map<String, Blob> templateEntries = readZipEntries(templateBlob);
            if (templateEntries.isEmpty()) {
                throw new AuraHandledException('PPTX template is empty.');
            }

            Map<String, Blob> generatedEntries = new Map<String, Blob>();
            for (String entryName : templateEntries.keySet()) {
                if (isDynamicPptxEntry(entryName)) {
                    continue;
                }
                generatedEntries.put(entryName, templateEntries.get(entryName));
            }

            Integer totalSlideCount = selectedSlideNumbers.size() + 1;

            generatedEntries.put(
                'ppt/slides/slide1.xml',
                Blob.valueOf(buildCoverSlideXml(meetingRecord, selectedSlideNumbers))
            );
            generatedEntries.put(
                'ppt/slides/_rels/slide1.xml.rels',
                Blob.valueOf(buildSlideRelationshipsXml(COVER_LAYOUT_TARGET, 1))
            );
            generatedEntries.put(
                'ppt/notesSlides/notesSlide1.xml',
                Blob.valueOf(buildNotesSlideXml(buildCoverSpeakerNotes(meetingRecord, selectedSlideNumbers)))
            );
            generatedEntries.put(
                'ppt/notesSlides/_rels/notesSlide1.xml.rels',
                Blob.valueOf(buildNotesSlideRelationshipsXml(1))
            );

            for (Integer index = 0; index < selectedSlideNumbers.size(); index++) {
                Integer sourceSlideNumber = selectedSlideNumbers[index];
                Integer exportSlideNumber = index + 2;
                Map<String, Object> slideMap = parseSlideFromField(
                    getSlideContentByNumber(meetingRecord, sourceSlideNumber),
                    sourceSlideNumber
                );

                generatedEntries.put(
                    'ppt/slides/slide' + String.valueOf(exportSlideNumber) + '.xml',
                    Blob.valueOf(buildContentSlideXml(sourceSlideNumber, slideMap))
                );
                generatedEntries.put(
                    'ppt/slides/_rels/slide' + String.valueOf(exportSlideNumber) + '.xml.rels',
                    Blob.valueOf(buildSlideRelationshipsXml(CONTENT_LAYOUT_TARGET, exportSlideNumber))
                );
                generatedEntries.put(
                    'ppt/notesSlides/notesSlide' + String.valueOf(exportSlideNumber) + '.xml',
                    Blob.valueOf(buildNotesSlideXml(buildSpeakerNotesText(slideMap)))
                );
                generatedEntries.put(
                    'ppt/notesSlides/_rels/notesSlide' + String.valueOf(exportSlideNumber) + '.xml.rels',
                    Blob.valueOf(buildNotesSlideRelationshipsXml(exportSlideNumber))
                );
            }

            generatedEntries.put(
                'ppt/notesMasters/notesMaster1.xml',
                Blob.valueOf(buildNotesMasterXml())
            );
            generatedEntries.put(
                'ppt/notesMasters/_rels/notesMaster1.xml.rels',
                Blob.valueOf(buildNotesMasterRelationshipsXml())
            );

            generatedEntries.put(
                'ppt/presentation.xml',
                Blob.valueOf(
                    buildPresentationXml(
                        getRequiredTemplateEntryText(templateEntries, 'ppt/presentation.xml'),
                        totalSlideCount
                    )
                )
            );
            generatedEntries.put(
                'ppt/_rels/presentation.xml.rels',
                Blob.valueOf(buildPresentationRelationshipsXml(totalSlideCount))
            );
            generatedEntries.put(
                '[Content_Types].xml',
                Blob.valueOf(
                    buildContentTypesXml(
                        getRequiredTemplateEntryText(templateEntries, '[Content_Types].xml'),
                        totalSlideCount
                    )
                )
            );

            return writeZipEntries(generatedEntries);
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Presentation file generation failed: ' + ex.getMessage());
        }
    }

    private static Blob loadPptxTemplateBlob() {
        if (Test.isRunningTest() && testPptxTemplateBlob != null) {
            return testPptxTemplateBlob;
        }

        List<StaticResource> resources = [
            SELECT Body
            FROM StaticResource
            WHERE Name = :PPTX_TEMPLATE_STATIC_RESOURCE_NAME
            LIMIT 1
        ];
        if (resources.isEmpty() || resources[0].Body == null) {
            throw new AuraHandledException(
                'PPTX template is missing. Please deploy static resource ' + PPTX_TEMPLATE_STATIC_RESOURCE_NAME + '.'
            );
        }
        return resources[0].Body;
    }

    private static Map<String, Blob> readZipEntries(Blob zipBlob) {
        Map<String, Blob> entriesByName = new Map<String, Blob>();
        Compression.ZipReader reader = new Compression.ZipReader(zipBlob);
        for (Compression.ZipEntry entry : reader.getEntries()) {
            entriesByName.put(entry.getName(), reader.extract(entry));
        }
        return entriesByName;
    }

    private static Blob writeZipEntries(Map<String, Blob> entriesByName) {
        Compression.ZipWriter writer = new Compression.ZipWriter();
        List<String> entryNames = new List<String>();
        entryNames.addAll(entriesByName.keySet());
        entryNames.sort();
        for (String entryName : entryNames) {
            writer.addEntry(entryName, entriesByName.get(entryName));
        }
        return writer.getArchive();
    }

    private static Boolean isDynamicPptxEntry(String entryName) {
        if (String.isBlank(entryName)) {
            return false;
        }
        if (entryName == '[Content_Types].xml'
            || entryName == 'ppt/presentation.xml'
            || entryName == 'ppt/_rels/presentation.xml.rels') {
            return true;
        }
        if (entryName.startsWith('ppt/slides/slide') && entryName.endsWith('.xml')) {
            return true;
        }
        if (entryName.startsWith('ppt/slides/_rels/slide') && entryName.endsWith('.xml.rels')) {
            return true;
        }
        if (entryName.startsWith('ppt/notesSlides/notesSlide') && entryName.endsWith('.xml')) {
            return true;
        }
        if (entryName.startsWith('ppt/notesSlides/_rels/notesSlide') && entryName.endsWith('.xml.rels')) {
            return true;
        }
        if (entryName == 'ppt/notesMasters/notesMaster1.xml'
            || entryName == 'ppt/notesMasters/_rels/notesMaster1.xml.rels') {
            return true;
        }
        return false;
    }

    private static String getRequiredTemplateEntryText(Map<String, Blob> templateEntries, String entryName) {
        Blob entryBody = templateEntries == null ? null : templateEntries.get(entryName);
        if (entryBody == null) {
            throw new AuraHandledException('PPTX template is missing required part: ' + entryName);
        }
        return entryBody.toString();
    }

    private static String buildPresentationXml(String templatePresentationXml, Integer slideCount) {
        String slideIdList = '<p:sldIdLst>';
        for (Integer slideNumber = 1; slideNumber <= slideCount; slideNumber++) {
            Integer slideId = PRESENTATION_BASE_SLIDE_ID + slideNumber;
            Integer relationshipId = PRESENTATION_STATIC_RELATIONSHIP_COUNT + slideNumber;
            slideIdList +=
                '<p:sldId id="' + String.valueOf(slideId) + '" r:id="rId' + String.valueOf(relationshipId) + '"/>';
        }
        slideIdList += '</p:sldIdLst>';
        return replaceXmlBlock(templatePresentationXml, '<p:sldIdLst>', '</p:sldIdLst>', slideIdList);
    }

    private static String buildPresentationRelationshipsXml(Integer slideCount) {
        String rels = '';
        rels += '<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\'?>';
        rels += '<Relationships xmlns="' + PPTX_RELATIONSHIP_NS + '">';
        rels += '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>';
        rels += '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/printerSettings" Target="printerSettings/printerSettings1.bin"/>';
        rels += '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/presProps" Target="presProps.xml"/>';
        rels += '<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/viewProps" Target="viewProps.xml"/>';
        rels += '<Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>';
        rels += '<Relationship Id="rId6" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/tableStyles" Target="tableStyles.xml"/>';
        rels += '<Relationship Id="rId7" Type="' + PPTX_NOTES_MASTER_RELATIONSHIP_TYPE + '" Target="notesMasters/notesMaster1.xml"/>';
        for (Integer slideNumber = 1; slideNumber <= slideCount; slideNumber++) {
            Integer relationshipId = PRESENTATION_STATIC_RELATIONSHIP_COUNT + slideNumber;
            rels +=
                '<Relationship Id="rId'
                + String.valueOf(relationshipId)
                + '" Type="'
                + PPTX_SLIDE_RELATIONSHIP_TYPE
                + '" Target="slides/slide'
                + String.valueOf(slideNumber)
                + '.xml"/>';
        }
        rels += '</Relationships>';
        return rels;
    }

    private static String buildContentTypesXml(String templateContentTypesXml, Integer slideCount) {
        String withoutSlides = templateContentTypesXml.replaceAll(
            '<Override\\s+PartName="/ppt/slides/slide\\d+\\.xml"\\s+ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide\\+xml"\\s*/>',
            ''
        );
        String withoutNotesSlides = withoutSlides.replaceAll(
            '<Override\\s+PartName="/ppt/notesSlides/notesSlide\\d+\\.xml"\\s+ContentType="application/vnd.openxmlformats-officedocument.presentationml.notesSlide\\+xml"\\s*/>',
            ''
        );
        String withoutNotesMaster = withoutNotesSlides.replaceAll(
            '<Override\\s+PartName="/ppt/notesMasters/notesMaster1\\.xml"\\s+ContentType="application/vnd.openxmlformats-officedocument.presentationml.notesMaster\\+xml"\\s*/>',
            ''
        );

        String slideOverrides = '';
        for (Integer slideNumber = 1; slideNumber <= slideCount; slideNumber++) {
            slideOverrides +=
                '<Override PartName="/ppt/slides/slide'
                + String.valueOf(slideNumber)
                + '.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>';
        }
        String notesMasterOverride =
            '<Override PartName="/ppt/notesMasters/notesMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.notesMaster+xml"/>';
        String notesSlideOverrides = '';
        for (Integer slideNumber = 1; slideNumber <= slideCount; slideNumber++) {
            notesSlideOverrides +=
                '<Override PartName="/ppt/notesSlides/notesSlide'
                + String.valueOf(slideNumber)
                + '.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml"/>';
        }

        Integer closeIndex = withoutNotesMaster.lastIndexOf('</Types>');
        if (closeIndex < 0) {
            throw new AuraHandledException('PPTX template content types XML is invalid.');
        }
        return withoutNotesMaster.substring(0, closeIndex)
            + notesMasterOverride
            + slideOverrides
            + notesSlideOverrides
            + withoutNotesMaster.substring(closeIndex);
    }

    private static String replaceXmlBlock(String source, String startTag, String endTag, String replacement) {
        Integer startIndex = source == null ? -1 : source.indexOf(startTag);
        Integer endIndex = source == null ? -1 : source.indexOf(endTag);
        if (startIndex < 0 || endIndex < 0 || endIndex < startIndex) {
            throw new AuraHandledException('PPTX template XML is missing expected node: ' + startTag);
        }
        Integer endWithTag = endIndex + endTag.length();
        return source.substring(0, startIndex) + replacement + source.substring(endWithTag);
    }

    private static String buildCoverSlideXml(CM_QBR_Meeting__c meetingRecord, List<Integer> selectedSlideNumbers) {
        String quarterLabel = normalizeText(meetingRecord.Quarter__c);
        if (String.isBlank(quarterLabel)) {
            quarterLabel = deriveQuarter(Date.today());
        }

        String focusCompanyName = meetingRecord.Focus_Company__r == null
            ? 'N/A'
            : normalizeText(meetingRecord.Focus_Company__r.Name);
        if (String.isBlank(focusCompanyName)) {
            focusCompanyName = 'N/A';
        }
        String rootAccountName = meetingRecord.Root_Account__r == null
            ? 'N/A'
            : normalizeText(meetingRecord.Root_Account__r.Name);
        if (String.isBlank(rootAccountName)) {
            rootAccountName = 'N/A';
        }

        String titleParagraphs = '';
        titleParagraphs += buildParagraphXml(
            quarterLabel + ' QBR Meeting Preparation',
            4200,
            true,
            'FFFFFF',
            false
        );

        String bodyParagraphs = '';
        bodyParagraphs += buildParagraphXml('Focus Company: ' + focusCompanyName, 2000, true, 'D8ECFF', false);
        bodyParagraphs += buildParagraphXml('Meeting Target: ' + rootAccountName, 2000, true, 'D8ECFF', false);
        bodyParagraphs += buildParagraphXml('Generated: ' + Datetime.now().format('yyyy-MM-dd HH:mm'), 1700, false, 'C7DCEF', false);

        return buildSlideXmlDocument(titleParagraphs, bodyParagraphs, '0F3A5F', true);
    }

    private static String buildContentSlideXml(Integer sourceSlideNumber, Map<String, Object> slideMap) {
        String slideTitle = normalizeText(castString(slideMap.get('slide_title')));
        if (String.isBlank(slideTitle)) {
            slideTitle = sourceSlideNumber >= 1 && sourceSlideNumber <= FIXED_TOPICS.size()
                ? FIXED_TOPICS[sourceSlideNumber - 1]
                : '待補充';
        }
        String finalSlideTitle = resolveExportSlideTitle(slideTitle);

        String titleParagraphs = '';
        titleParagraphs += buildParagraphXml(
            truncateForPptxLine(finalSlideTitle),
            2400,
            true,
            '0F3A5F',
            false
        );

        String bodyParagraphs = '';
        Integer remainingLineUnits = MAX_CONTENT_VISUAL_LINE_UNITS;

        Map<String, Object> tableData = normalizeTableData(slideMap.get('table_data'));
        List<String> headers = normalizeStringList(tableData.get('headers'));
        List<List<String>> rows = normalizeStringMatrix(tableData.get('rows'), headers.size());
        if (rows.isEmpty()) {
            rows = normalizeStringMatrix(tableData.get('available_rows'), headers.size());
        }
        Boolean hasTableSection = toBoolean(tableData.get('has_table')) && (!headers.isEmpty() || !rows.isEmpty());

        List<String> bulletPoints = new List<String>();
        List<Boolean> bulletIndentedFlags = new List<Boolean>();
        List<Object> rawBulletPoints = castList(slideMap.get('bullet_points'));
        if (rawBulletPoints != null) {
            for (Object rawBulletObj : rawBulletPoints) {
                String rawBullet = castString(rawBulletObj);
                String normalizedBullet = normalizeText(rawBullet);
                if (String.isBlank(normalizedBullet)) {
                    continue;
                }
                bulletPoints.add(normalizedBullet);
                bulletIndentedFlags.add(isIndentedBulletText(rawBullet));
            }
        }

        if (!bulletPoints.isEmpty()) {
            Integer bulletLimit = Math.min(MAX_SLIDE_BULLET_COUNT, bulletPoints.size());
            for (Integer index = 0; index < bulletLimit; index++) {
                Boolean isIndentedBullet = index < bulletIndentedFlags.size()
                    ? bulletIndentedFlags[index]
                    : false;
                Integer fontSize = isIndentedBullet ? INDENTED_FONT_SIZE : BODY_FONT_SIZE;
                Integer paragraphUnits = estimateVisualLineUnits(bulletPoints[index], fontSize, isIndentedBullet);
                Integer minReserveForTable = hasTableSection ? 2 : 0;
                if (remainingLineUnits - paragraphUnits < minReserveForTable) {
                    break;
                }

                bodyParagraphs += buildBulletParagraphXml(
                    truncateForPptxLine(bulletPoints[index]),
                    fontSize,
                    '253746',
                    isIndentedBullet
                );
                remainingLineUnits -= paragraphUnits;
            }
        }

        if (hasTableSection && remainingLineUnits > 0) {
            if (!String.isBlank(bodyParagraphs) && remainingLineUnits > 2) {
                bodyParagraphs += buildBlankParagraphXml();
                remainingLineUnits -= 1;
            }
            if (!headers.isEmpty()) {
                String headerLine = truncateForPptxLine(joinCells(headers));
                Integer headerUnits = estimateVisualLineUnits(headerLine, BODY_FONT_SIZE, false);
                if (remainingLineUnits >= headerUnits + 1) {
                    bodyParagraphs += buildBulletParagraphXml(
                        headerLine,
                        BODY_FONT_SIZE,
                        '4B5563',
                        false
                    );
                    remainingLineUnits -= headerUnits;
                }
            }

            Integer rowLimit = Math.min(MAX_SLIDE_TABLE_ROW_COUNT, rows.size());
            for (Integer rowIndex = 0; rowIndex < rowLimit; rowIndex++) {
                String rowLine = truncateForPptxLine(joinCells(rows[rowIndex]));
                Integer rowUnits = estimateVisualLineUnits(rowLine, INDENTED_FONT_SIZE, true);
                if (remainingLineUnits - rowUnits < 0) {
                    break;
                }
                bodyParagraphs += buildBulletParagraphXml(
                    rowLine,
                    INDENTED_FONT_SIZE,
                    '4B5563',
                    true
                );
                remainingLineUnits -= rowUnits;
            }
        }

        return buildSlideXmlDocument(titleParagraphs, bodyParagraphs, 'F4F8FC', false);
    }

    private static String buildSlideXmlDocument(
        String titleParagraphsXml,
        String bodyParagraphsXml,
        String bgColorHex,
        Boolean isCoverSlide
    ) {
        Boolean compactTop = isCoverSlide == true;
        String titleBodyPr = compactTop
            ? '<a:bodyPr anchor="t" tIns="0" bIns="0" lIns="0" rIns="0"/>'
            : '<a:bodyPr/>';
        String contentBodyPr = compactTop
            ? '<a:bodyPr wrap="square" anchor="t" tIns="0" bIns="0" lIns="0" rIns="0"/>'
            : '<a:bodyPr wrap="square"/>';
        String titleShapePr = compactTop
            ? '<p:spPr><a:xfrm><a:off x="457200" y="114300"/><a:ext cx="8229600" cy="1028700"/></a:xfrm></p:spPr>'
            : '<p:spPr/>';
        String contentShapePr = compactTop
            ? '<p:spPr><a:xfrm><a:off x="914400" y="1714500"/><a:ext cx="7315200" cy="2743200"/></a:xfrm></p:spPr>'
            : '<p:spPr/>';

        String xml = '';
        xml += '<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\'?>';
        xml += '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"';
        xml += ' xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"';
        xml += ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">';
        xml += '<p:cSld>';
        if (!String.isBlank(bgColorHex)) {
            xml += '<p:bg><p:bgPr><a:solidFill><a:srgbClr val="' + bgColorHex + '"/></a:solidFill></p:bgPr></p:bg>';
        }
        xml += '<p:spTree>';
        xml += '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>';
        xml += '<p:sp>';
        xml += '<p:nvSpPr><p:cNvPr id="2" name="Title 1"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>';
        xml += titleShapePr;
        xml += '<p:txBody>' + titleBodyPr + '<a:lstStyle/>' + titleParagraphsXml + '</p:txBody>';
        xml += '</p:sp>';
        xml += '<p:sp>';
        xml += '<p:nvSpPr><p:cNvPr id="3" name="Content Placeholder 2"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph idx="1"/></p:nvPr></p:nvSpPr>';
        xml += contentShapePr;
        xml += '<p:txBody>' + contentBodyPr + '<a:lstStyle/>' + bodyParagraphsXml + '</p:txBody>';
        xml += '</p:sp>';
        xml += '</p:spTree></p:cSld>';
        xml += '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>';
        xml += '</p:sld>';
        return xml;
    }

    private static String resolveExportSlideTitle(String slideTitle) {
        String normalized = normalizeText(slideTitle);
        if (String.isBlank(normalized)) {
            return '待補充';
        }

        String stripped = normalized.replaceFirst('^(議題|Topic)\\s*\\d+\\s*[：:]\\s*', '');
        stripped = normalizeText(stripped);
        return String.isBlank(stripped) ? normalized : stripped;
    }

    private static Boolean isIndentedBulletText(String rawBulletText) {
        if (rawBulletText == null) {
            return false;
        }
        return rawBulletText.startsWith(' ')
            || rawBulletText.startsWith('\t')
            || rawBulletText.startsWith('　');
    }

    private static String buildBulletParagraphXml(
        String text,
        Integer fontSize,
        String colorHex,
        Boolean isIndentedBullet
    ) {
        String safeText = truncateForPptxLine(text);
        String marL = isIndentedBullet == true ? '514350' : '342900';
        String indent = '-171450';

        String xml = '<a:p>';
        xml += '<a:pPr marL="' + marL + '" indent="' + indent + '"><a:buChar char="•"/></a:pPr>';
        xml += '<a:r><a:rPr lang="zh-TW"';
        if (fontSize != null) {
            xml += ' sz="' + String.valueOf(fontSize) + '"';
        }
        xml += '>';
        if (!String.isBlank(colorHex)) {
            xml += '<a:solidFill><a:srgbClr val="' + colorHex + '"/></a:solidFill>';
        }
        xml += '</a:rPr><a:t>' + escapeXml(safeText) + '</a:t></a:r>';
        xml += '<a:endParaRPr lang="zh-TW"/></a:p>';
        return xml;
    }

    private static Integer estimateVisualLineUnits(
        String text,
        Integer fontSize,
        Boolean isIndentedBullet
    ) {
        String normalized = normalizeText(text);
        if (String.isBlank(normalized)) {
            return 1;
        }

        Integer safeFontSize = fontSize == null ? BODY_FONT_SIZE : fontSize;
        Integer charsPerLine;
        if (safeFontSize <= INDENTED_FONT_SIZE) {
            charsPerLine = 60;
        } else if (safeFontSize <= BODY_FONT_SIZE) {
            charsPerLine = 46;
        } else {
            charsPerLine = 34;
        }
        if (isIndentedBullet == true) {
            charsPerLine = Math.max(20, charsPerLine - 6);
        }

        Integer lineCount = (normalized.length() + charsPerLine - 1) / charsPerLine;
        return Math.max(1, lineCount);
    }

    private static String buildSlideRelationshipsXml(String layoutTarget, Integer notesSlideNumber) {
        String safeLayoutTarget = String.isBlank(layoutTarget) ? CONTENT_LAYOUT_TARGET : layoutTarget;
        Integer safeNotesNumber = notesSlideNumber == null || notesSlideNumber < 1 ? 1 : notesSlideNumber;
        String xml = '';
        xml += '<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\'?>';
        xml += '<Relationships xmlns="' + PPTX_RELATIONSHIP_NS + '">';
        xml += '<Relationship Id="rId1" Type="' + PPTX_SLIDE_LAYOUT_RELATIONSHIP_TYPE + '" Target="' + safeLayoutTarget + '"/>';
        xml += '<Relationship Id="rId2" Type="' + PPTX_NOTES_SLIDE_RELATIONSHIP_TYPE + '" Target="../notesSlides/notesSlide' + String.valueOf(safeNotesNumber) + '.xml"/>';
        xml += '</Relationships>';
        return xml;
    }

    private static String buildCoverSpeakerNotes(CM_QBR_Meeting__c meetingRecord, List<Integer> selectedSlideNumbers) {
        List<String> lines = new List<String>();
        String quarterLabel = normalizeText(meetingRecord.Quarter__c);
        if (!String.isBlank(quarterLabel)) {
            lines.add('Quarter: ' + quarterLabel);
        }
        if (meetingRecord.Focus_Company__r != null && !String.isBlank(normalizeText(meetingRecord.Focus_Company__r.Name))) {
            lines.add('Focus Company: ' + normalizeText(meetingRecord.Focus_Company__r.Name));
        }
        if (meetingRecord.Root_Account__r != null && !String.isBlank(normalizeText(meetingRecord.Root_Account__r.Name))) {
            lines.add('Meeting Target: ' + normalizeText(meetingRecord.Root_Account__r.Name));
        }
        if (selectedSlideNumbers != null && !selectedSlideNumbers.isEmpty()) {
            lines.add('Selected Topics: ' + selectedSlideNumbers.size());
        }
        if (lines.isEmpty()) {
            lines.add('QBR Meeting Preparation');
        }
        return String.join(lines, '\n');
    }

    private static String buildSpeakerNotesText(Map<String, Object> slideMap) {
        String speakerNotes = normalizeText(castString(slideMap.get('speaker_notes')));
        if (!String.isBlank(speakerNotes)) {
            return speakerNotes;
        }
        String fallback = normalizeText(castString(slideMap.get('slide_title')));
        if (!String.isBlank(fallback)) {
            return fallback;
        }
        return '待補充';
    }

    private static String buildNotesSlideXml(String notesText) {
        String xml = '';
        xml += '<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\'?>';
        xml += '<p:notes xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"';
        xml += ' xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"';
        xml += ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">';
        xml += '<p:cSld><p:spTree>';
        xml += '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>';
        xml += '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>';
        xml += '<p:sp>';
        xml += '<p:nvSpPr><p:cNvPr id="2" name="Slide Image Placeholder 1"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="sldImg" idx="2"/></p:nvPr></p:nvSpPr>';
        xml += '<p:spPr/></p:sp>';
        xml += '<p:sp>';
        xml += '<p:nvSpPr><p:cNvPr id="3" name="Notes Placeholder 2"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="body" idx="3" sz="quarter"/></p:nvPr></p:nvSpPr>';
        xml += '<p:spPr/>';
        xml += '<p:txBody><a:bodyPr/><a:lstStyle/>' + buildNotesParagraphsXml(notesText) + '</p:txBody>';
        xml += '</p:sp>';
        xml += '<p:sp>';
        xml += '<p:nvSpPr><p:cNvPr id="4" name="Slide Number Placeholder 3"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="sldNum" idx="5" sz="quarter"/></p:nvPr></p:nvSpPr>';
        xml += '<p:spPr/></p:sp>';
        xml += '</p:spTree></p:cSld>';
        xml += '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>';
        xml += '</p:notes>';
        return xml;
    }

    private static String buildNotesSlideRelationshipsXml(Integer slideNumber) {
        Integer safeSlideNumber = slideNumber == null || slideNumber < 1 ? 1 : slideNumber;
        String xml = '';
        xml += '<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\'?>';
        xml += '<Relationships xmlns="' + PPTX_RELATIONSHIP_NS + '">';
        xml += '<Relationship Id="rId1" Type="' + PPTX_NOTES_MASTER_RELATIONSHIP_TYPE + '" Target="../notesMasters/notesMaster1.xml"/>';
        xml += '<Relationship Id="rId2" Type="' + PPTX_SLIDE_RELATIONSHIP_TYPE + '" Target="../slides/slide' + String.valueOf(safeSlideNumber) + '.xml"/>';
        xml += '</Relationships>';
        return xml;
    }

    private static String buildNotesMasterXml() {
        String xml = '';
        xml += '<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\'?>';
        xml += '<p:notesMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"';
        xml += ' xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"';
        xml += ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">';
        xml += '<p:cSld><p:spTree>';
        xml += '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>';
        xml += '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>';
        xml += '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Notes Placeholder"/><p:cNvSpPr/><p:nvPr><p:ph type="body" idx="3" sz="quarter"/></p:nvPr></p:nvSpPr><p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:endParaRPr lang="zh-TW"/></a:p></p:txBody></p:sp>';
        xml += '</p:spTree></p:cSld>';
        xml += '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>';
        xml += '<p:notesStyle><a:lvl1pPr marL="0" algn="l"><a:defRPr sz="1200"/></a:lvl1pPr></p:notesStyle>';
        xml += '</p:notesMaster>';
        return xml;
    }

    private static String buildNotesMasterRelationshipsXml() {
        String xml = '';
        xml += '<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\'?>';
        xml += '<Relationships xmlns="' + PPTX_RELATIONSHIP_NS + '">';
        xml += '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>';
        xml += '</Relationships>';
        return xml;
    }

    private static String buildNotesParagraphsXml(String notesText) {
        List<String> lines = splitTextByLine(notesText);
        String xml = '';
        for (String line : lines) {
            xml += '<a:p><a:r><a:rPr lang="zh-TW"/><a:t>' + escapeXml(truncateForPptxNotesLine(line)) + '</a:t></a:r><a:endParaRPr lang="zh-TW"/></a:p>';
        }
        return xml;
    }

    private static String resolveTopicTitle(Integer sourceSlideNumber, Map<String, Object> slideMap) {
        String topicTitle = normalizeText(castString(slideMap.get('topic_title_fixed')));
        if (!String.isBlank(topicTitle)) {
            return topicTitle;
        }
        if (sourceSlideNumber != null && sourceSlideNumber >= 1 && sourceSlideNumber <= FIXED_TOPICS.size()) {
            return FIXED_TOPICS[sourceSlideNumber - 1];
        }
        return '待補充';
    }

    private static String resolvePresentationTopicTitle(
        Integer slideNumber,
        Map<String, Object> slideMap,
        String focusCompanyName,
        String rootAccountName
    ) {
        if (slideNumber == 1) {
            return composeFocusCompanyIntroTopicTitle(focusCompanyName);
        }
        if (slideNumber == 2) {
            return composeRootAccountIntroTopicTitle(rootAccountName);
        }
        if (slideNumber == 3) {
            return composeFocusCompanyOpsTopicTitle(focusCompanyName);
        }

        String topicTitle = normalizeText(castString(slideMap.get('topic_title_fixed')));
        if (!String.isBlank(topicTitle)) {
            return topicTitle;
        }
        if (slideNumber != null && slideNumber >= 1 && slideNumber <= FIXED_TOPICS.size()) {
            return FIXED_TOPICS[slideNumber - 1];
        }
        return '待補充';
    }

    private static String composeFocusCompanyIntroTopicTitle(String focusCompanyName) {
        String normalizedFocusCompanyName = normalizeText(focusCompanyName);
        if (String.isBlank(normalizedFocusCompanyName)) {
            return FIXED_TOPICS[0];
        }
        return normalizedFocusCompanyName + '公司簡介';
    }

    private static String composeRootAccountIntroTopicTitle(String rootAccountName) {
        String normalizedRootAccountName = normalizeText(rootAccountName);
        if (String.isBlank(normalizedRootAccountName)) {
            return FIXED_TOPICS[1];
        }
        return normalizedRootAccountName + ' 公司簡介';
    }

    private static String composeFocusCompanyOpsTopicTitle(String focusCompanyName) {
        String normalizedFocusCompanyName = normalizeText(focusCompanyName);
        if (String.isBlank(normalizedFocusCompanyName)) {
            return 'XXX公司營運概述暨新產品技術/組織變動簡介';
        }
        return normalizedFocusCompanyName + '公司營運概述暨新產品技術/組織變動簡介';
    }

    private static String joinCells(List<String> cells) {
        if (cells == null || cells.isEmpty()) {
            return '';
        }
        List<String> normalized = new List<String>();
        for (String cell : cells) {
            normalized.add(cell == null ? '' : cell);
        }
        return String.join(normalized, ' | ');
    }

    private static List<String> splitTextByLine(String text) {
        List<String> lines = new List<String>();
        String normalized = text == null ? '' : text.replace('\r\n', '\n').replace('\r', '\n');
        for (String line : normalized.split('\n')) {
            String cleanLine = normalizeText(line);
            if (!String.isBlank(cleanLine)) {
                lines.add(cleanLine);
            }
        }
        if (lines.isEmpty()) {
            lines.add(' ');
        }
        return lines;
    }

    private static String truncateForPptxLine(String value) {
        String normalized = normalizeText(value);
        if (String.isBlank(normalized)) {
            return '待補充';
        }
        if (normalized.length() <= MAX_PPTX_LINE_LENGTH) {
            return normalized;
        }
        return normalized.substring(0, MAX_PPTX_LINE_LENGTH - 1) + '…';
    }

    private static String truncateForPptxNotesLine(String value) {
        String normalized = normalizeText(value);
        if (String.isBlank(normalized)) {
            return '';
        }
        if (normalized.length() <= MAX_PPTX_NOTES_LINE_LENGTH) {
            return normalized;
        }
        return normalized.substring(0, MAX_PPTX_NOTES_LINE_LENGTH - 1) + '…';
    }

    private static String buildBlankParagraphXml() {
        return '<a:p><a:endParaRPr lang="zh-TW"/></a:p>';
    }

    private static String buildParagraphXml(
        String text,
        Integer fontSize,
        Boolean bold,
        String colorHex,
        Boolean isBullet
    ) {
        String safeText = truncateForPptxLine(text);
        String xml = '<a:p>';
        if (isBullet) {
            xml += '<a:pPr marL="342900" indent="-171450"><a:buChar char="•"/></a:pPr>';
        }
        xml += '<a:r><a:rPr lang="zh-TW"';
        if (fontSize != null) {
            xml += ' sz="' + String.valueOf(fontSize) + '"';
        }
        if (bold == true) {
            xml += ' b="1"';
        }
        xml += '>';
        if (!String.isBlank(colorHex)) {
            xml += '<a:solidFill><a:srgbClr val="' + colorHex + '"/></a:solidFill>';
        }
        xml += '</a:rPr><a:t>' + escapeXml(safeText) + '</a:t></a:r>';
        xml += '<a:endParaRPr lang="zh-TW"/></a:p>';
        return xml;
    }

    private static String escapeXml(String text) {
        if (text == null) {
            return '';
        }
        String escaped = text.replace('&', '&amp;');
        escaped = escaped.replace('<', '&lt;');
        escaped = escaped.replace('>', '&gt;');
        escaped = escaped.replace('"', '&quot;');
        escaped = escaped.replace('\'', '&apos;');
        return escaped;
    }

    private static String deriveQuarter(Date targetDate) {
        Integer month = targetDate.month();
        Integer quarter = 1;
        if (month > 9) {
            quarter = 4;
        } else if (month > 6) {
            quarter = 3;
        } else if (month > 3) {
            quarter = 2;
        }
        return String.valueOf(targetDate.year()) + ' Q' + String.valueOf(quarter);
    }

    private static String resolveQuarterValue(String quarterOverride, Date fallbackDate) {
        String normalizedQuarter = normalizeText(quarterOverride);
        if (!String.isBlank(normalizedQuarter)) {
            return normalizedQuarter;
        }
        return deriveQuarter(fallbackDate == null ? Date.today() : fallbackDate);
    }

    private static Integer toInteger(Object rawValue) {
        if (rawValue == null) {
            return null;
        }
        if (rawValue instanceof Integer) {
            return (Integer) rawValue;
        }
        if (rawValue instanceof Long) {
            return Integer.valueOf(String.valueOf(rawValue));
        }
        if (rawValue instanceof Decimal) {
            return ((Decimal) rawValue).intValue();
        }

        String text = normalizeText(castString(rawValue));
        if (String.isBlank(text)) {
            return null;
        }
        try {
            return Integer.valueOf(text);
        } catch (Exception ex) {
            return null;
        }
    }

    private static Boolean toBoolean(Object rawValue) {
        if (rawValue == null) {
            return false;
        }
        if (rawValue instanceof Boolean) {
            return (Boolean) rawValue;
        }

        String text = normalizeText(castString(rawValue));
        return text == 'true' || text == 'TRUE' || text == '1';
    }

    private static String normalizeText(String value) {
        if (value == null) {
            return null;
        }
        String normalized = value.trim();
        return String.isBlank(normalized) ? null : normalized;
    }

    private static String castString(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static Map<String, Object> castMap(Object value) {
        try {
            return (Map<String, Object>) value;
        } catch (Exception ex) {
            return null;
        }
    }

    private static List<Object> castList(Object value) {
        try {
            return (List<Object>) value;
        } catch (Exception ex) {
            return null;
        }
    }

    private static ConnectApi.WrappedValue toSObjectInput(Id recordId) {
        Map<String, String> recordRef = new Map<String, String>{ 'id' => String.valueOf(recordId) };
        ConnectApi.WrappedValue wrappedValue = new ConnectApi.WrappedValue();
        wrappedValue.value = recordRef;
        return wrappedValue;
    }

    private static ConnectApi.WrappedValue toPrimitiveInput(String value) {
        ConnectApi.WrappedValue wrappedValue = new ConnectApi.WrappedValue();
        wrappedValue.value = value;
        return wrappedValue;
    }
}