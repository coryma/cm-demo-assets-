@IsTest
private class CMQbrMeetingPrepControllerTest {
    @IsTest
    static void getFocusContextReturnsActiveDemoTarget() {
        Account focus = new Account(
            Name = 'WNC Demo Target',
            CM_Is_Demo_Target__c = true
        );
        insert focus;

        Test.startTest();
        CMQbrMeetingPrepController.FocusContextPayload payload =
            CMQbrMeetingPrepController.getFocusContext();
        Test.stopTest();

        System.assertEquals(true, payload.hasFocusCompany);
        System.assertEquals(focus.Id, payload.focusCompanyId);
        System.assertEquals('WNC Demo Target', payload.focusCompanyName);
        System.assertEquals(9, payload.fixedTopics.size());
        System.assertEquals('XXX公司簡介', payload.fixedTopics[0]);
    }

    @IsTest
    static void searchRootAccountsExcludesFocusCompany() {
        Account focus = new Account(
            Name = 'Focus Company',
            CM_Is_Demo_Target__c = true
        );
        Account supplier = new Account(Name = 'Supplier A', Industry = 'Electronics');
        insert new List<Account>{ focus, supplier };

        Test.startTest();
        List<CMQbrMeetingPrepController.AccountRow> rows =
            CMQbrMeetingPrepController.searchRootAccounts('', 20);
        Test.stopTest();

        Set<Id> rowIds = new Set<Id>();
        for (CMQbrMeetingPrepController.AccountRow row : rows) {
            rowIds.add(row.id);
        }
        System.assertEquals(false, rowIds.contains(focus.Id));
        System.assertEquals(true, rowIds.contains(supplier.Id));
    }

    @IsTest
    static void generateMeetingPreparationCreatesMeetingRecord() {
        Account focus = new Account(
            Name = 'Focus Company',
            CM_Is_Demo_Target__c = true
        );
        Account supplier = new Account(Name = 'Micron', Industry = 'Electronics');
        insert new List<Account>{ focus, supplier };

        CMQbrMeetingPrepController.testPromptResponse = buildPromptResponse();

        Test.startTest();
        CMQbrMeetingPrepController.GenerateResult result =
            CMQbrMeetingPrepController.generateMeetingPreparation(supplier.Id, '資材處', null);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertNotEquals(null, result.meetingId);
        System.assert(result.meetingUrl.contains(String.valueOf(result.meetingId)));

        CM_QBR_Meeting__c meeting = [
            SELECT Id, Focus_Company__c, Focus_Department__c, Root_Account__c, Quarter__c,
                   Status__c, Prompt_Response__c, Slide_01_Content__c, Slide_09_Content__c
            FROM CM_QBR_Meeting__c
            WHERE Id = :result.meetingId
            LIMIT 1
        ];

        System.assertEquals(focus.Id, meeting.Focus_Company__c);
        System.assertEquals('資材處', meeting.Focus_Department__c);
        System.assertEquals(supplier.Id, meeting.Root_Account__c);
        System.assertEquals('Generated', meeting.Status__c);
        System.assert(!String.isBlank(meeting.Quarter__c));
        System.assert(meeting.Prompt_Response__c.contains('slides'));
        System.assert(meeting.Slide_01_Content__c.contains('XXX公司簡介'));
        System.assert(meeting.Slide_09_Content__c.contains('重大議題商討'));

        CMQbrMeetingPrepController.testPromptResponse = null;
    }

    @IsTest
    static void findLatestGeneratedMeetingReturnsQuarterMatch() {
        Account focus = new Account(
            Name = 'Focus Company',
            CM_Is_Demo_Target__c = true
        );
        Account supplier = new Account(Name = 'Supplier For Lookup', Industry = 'Electronics');
        insert new List<Account>{ focus, supplier };

        CMQbrMeetingPrepController.testPromptResponse = buildPromptResponse();
        CMQbrMeetingPrepController.GenerateResult generated =
            CMQbrMeetingPrepController.generateMeetingPreparation(supplier.Id, '資材處', '2026 Q2');

        Test.startTest();
        CMQbrMeetingPrepController.GenerateResult found =
            CMQbrMeetingPrepController.findLatestGeneratedMeeting(supplier.Id, '2026 Q2');
        Test.stopTest();

        System.assertNotEquals(null, found);
        System.assertEquals(generated.meetingId, found.meetingId);
        System.assert(!String.isBlank(found.meetingName));
        System.assert(found.message.contains('Loaded generated QBR default'));

        CMQbrMeetingPrepController.testPromptResponse = null;
    }

    @IsTest
    static void findLatestGeneratedMeetingReturnsMessageWhenMissing() {
        Account supplier = new Account(Name = 'Supplier Without Default');
        insert supplier;

        Test.startTest();
        CMQbrMeetingPrepController.GenerateResult found =
            CMQbrMeetingPrepController.findLatestGeneratedMeeting(supplier.Id, '2026 Q3');
        Test.stopTest();

        System.assertNotEquals(null, found);
        System.assertEquals(null, found.meetingId);
        System.assert(found.message.contains('Please run QBR Setup first'));
    }

    @IsTest
    static void editableSlidesCanBeLoadedAndSaved() {
        Account focus = new Account(
            Name = 'Focus Company',
            CM_Is_Demo_Target__c = true
        );
        Account supplier = new Account(Name = 'Supplier For Edit', Industry = 'Electronics');
        insert new List<Account>{ focus, supplier };

        CMQbrMeetingPrepController.testPromptResponse = buildPromptResponse();

        CMQbrMeetingPrepController.GenerateResult result =
            CMQbrMeetingPrepController.generateMeetingPreparation(supplier.Id, '資材處', null);

        Test.startTest();
        CMQbrMeetingPrepController.EditableSlidesPayload beforeSave =
            CMQbrMeetingPrepController.getEditableSlides(result.meetingId);
        CMQbrMeetingPrepController.EditableSlidesPayload afterSave =
            CMQbrMeetingPrepController.saveEditableSlides(
                result.meetingId,
                '第1頁自訂標題',
                '第2頁自訂標題',
                '第3頁自訂標題',
                '第4頁自訂標題',
                null,
                null,
                null,
                null,
                null,
                '<p><strong>Page1 Manual</strong></p><p>Custom intro</p>',
                '<p><strong>Page2 Manual</strong></p><p>Custom supplier intro</p>',
                '<p><strong>Page3 Manual</strong></p><p>Custom focus operation update</p>',
                '<p><strong>Page4 Manual</strong></p><p>Custom root account operation update</p>',
                null,
                null,
                null,
                null,
                null
            );
        Test.stopTest();

        System.assertNotEquals(null, beforeSave);
        System.assertNotEquals(null, afterSave);
        System.assertEquals(result.meetingId, beforeSave.meetingId);
        System.assert(!String.isBlank(beforeSave.pageOneRichText));
        System.assert(!String.isBlank(beforeSave.pageThreeRichText));
        System.assert(afterSave.pageOneRichText.contains('Page1 Manual'));
        System.assert(afterSave.pageTwoRichText.contains('Page2 Manual'));
        System.assert(afterSave.pageThreeRichText.contains('Page3 Manual'));
        System.assert(afterSave.pageFourRichText.contains('Page4 Manual'));
        System.assertEquals('第1頁自訂標題', afterSave.pageOneTitle);
        System.assertEquals('第2頁自訂標題', afterSave.pageTwoTitle);
        System.assertEquals('第3頁自訂標題', afterSave.pageThreeTitle);
        System.assertEquals('第4頁自訂標題', afterSave.pageFourTitle);

        CM_QBR_Meeting__c meeting = [
            SELECT Slide_01_Content__c, Slide_02_Content__c,
                   Slide_03_Content__c, Slide_04_Content__c
            FROM CM_QBR_Meeting__c
            WHERE Id = :result.meetingId
            LIMIT 1
        ];
        System.assert(meeting.Slide_01_Content__c.contains('rich_text_content'));
        System.assert(meeting.Slide_02_Content__c.contains('rich_text_content'));
        System.assert(meeting.Slide_03_Content__c.contains('rich_text_content'));
        System.assert(meeting.Slide_04_Content__c.contains('rich_text_content'));

        CMQbrMeetingPrepController.testPromptResponse = null;
    }

    @IsTest
    static void saveEditableSlidesCanFilterSlideFiveAndSixRows() {
        Account focus = new Account(
            Name = 'Focus Company',
            CM_Is_Demo_Target__c = true
        );
        Account supplier = new Account(Name = 'Supplier For Table Filter', Industry = 'Electronics');
        insert new List<Account>{ focus, supplier };

        CMQbrMeetingPrepController.testPromptResponse = buildPromptResponse();
        CMQbrMeetingPrepController.GenerateResult result =
            CMQbrMeetingPrepController.generateMeetingPreparation(supplier.Id, '資材處', null);

        Test.startTest();
        CMQbrMeetingPrepController.EditableSlidesPayload payload =
            CMQbrMeetingPrepController.saveEditableSlides(
                result.meetingId,
                null,
                null,
                null,
                null,
                '第5頁自訂標題',
                '第6頁自訂標題',
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                new List<Integer>{ 1 },
                new List<Integer>{ 0 },
                null,
                null,
                null
            );
        Test.stopTest();

        System.assertNotEquals(null, payload);
        System.assertEquals(true, payload.pageFiveHasTable);
        System.assertEquals(true, payload.pageSixHasTable);
        System.assertEquals(1, payload.pageFiveSelectedRowIndexes.size());
        System.assertEquals(1, payload.pageSixSelectedRowIndexes.size());
        System.assertEquals(1, payload.pageFiveSelectedRowIndexes[0]);
        System.assertEquals(0, payload.pageSixSelectedRowIndexes[0]);
        System.assertEquals('第5頁自訂標題', payload.pageFiveTitle);
        System.assertEquals('第6頁自訂標題', payload.pageSixTitle);

        CM_QBR_Meeting__c meeting = [
            SELECT Slide_05_Content__c, Slide_06_Content__c
            FROM CM_QBR_Meeting__c
            WHERE Id = :result.meetingId
            LIMIT 1
        ];

        Map<String, Object> slideFive = (Map<String, Object>) JSON.deserializeUntyped(meeting.Slide_05_Content__c);
        Map<String, Object> slideSix = (Map<String, Object>) JSON.deserializeUntyped(meeting.Slide_06_Content__c);
        Map<String, Object> slideFiveTable = (Map<String, Object>) slideFive.get('table_data');
        Map<String, Object> slideSixTable = (Map<String, Object>) slideSix.get('table_data');

        List<Object> slideFiveRows = (List<Object>) slideFiveTable.get('rows');
        List<Object> slideSixRows = (List<Object>) slideSixTable.get('rows');
        List<Object> slideFiveIndexes = (List<Object>) slideFiveTable.get('selected_row_indexes');
        List<Object> slideSixIndexes = (List<Object>) slideSixTable.get('selected_row_indexes');

        System.assertEquals(1, slideFiveRows.size());
        System.assertEquals(1, slideSixRows.size());
        System.assertEquals(1, slideFiveIndexes.size());
        System.assertEquals(1, slideSixIndexes.size());
        System.assertEquals(1, Integer.valueOf(String.valueOf(slideFiveIndexes[0])));
        System.assertEquals(0, Integer.valueOf(String.valueOf(slideSixIndexes[0])));

        CMQbrMeetingPrepController.testPromptResponse = null;
    }

    @IsTest
    static void regenerateSupplierIntroFromFileUpdatesSlide2() {
        Account focus = new Account(
            Name = 'Focus Company',
            CM_Is_Demo_Target__c = true
        );
        Account supplier = new Account(Name = 'Supplier For File Prompt', Industry = 'Electronics');
        insert new List<Account>{ focus, supplier };

        CMQbrMeetingPrepController.testPromptResponse = buildPromptResponse();
        CMQbrMeetingPrepController.GenerateResult result =
            CMQbrMeetingPrepController.generateMeetingPreparation(supplier.Id, '資材處', null);

        ContentVersion fileVersion = new ContentVersion(
            Title = 'SupplierProfile',
            PathOnClient = 'supplier-profile.txt',
            VersionData = Blob.valueOf('Supplier file content for prompt generation')
        );
        insert fileVersion;
        fileVersion = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :fileVersion.Id
            LIMIT 1
        ];

        CMQbrMeetingPrepController.testSupplierIntroPromptResponse = JSON.serialize(
            new Map<String, Object>{
                'slide_title' => '供應商公司簡介（檔案版）',
                'bullet_points' => new List<String>{
                    '檔案重點一',
                    '檔案重點二',
                    '檔案重點三',
                    '檔案重點四'
                },
                'table_data' => new Map<String, Object>{
                    'has_table' => false,
                    'headers' => new List<String>(),
                    'rows' => new List<Object>()
                },
                'speaker_notes' => '由上傳檔案生成的供應商備忘'
            }
        );

        Test.startTest();
        CMQbrMeetingPrepController.EditableSlidesPayload payload =
            CMQbrMeetingPrepController.regenerateSupplierIntroFromFile(
                result.meetingId,
                fileVersion.ContentDocumentId
            );
        Test.stopTest();

        System.assertNotEquals(null, payload);
        System.assert(payload.pageTwoRichText.contains('供應商公司簡介（檔案版）'));
        System.assert(payload.pageTwoRichText.contains('檔案重點一'));

        CM_QBR_Meeting__c meeting = [
            SELECT Slide_02_Content__c
            FROM CM_QBR_Meeting__c
            WHERE Id = :result.meetingId
            LIMIT 1
        ];
        System.assert(meeting.Slide_02_Content__c.contains('供應商公司簡介（檔案版）'));

        CMQbrMeetingPrepController.testPromptResponse = null;
        CMQbrMeetingPrepController.testSupplierIntroPromptResponse = null;
    }

    @IsTest
    static void generateMeetingPreparationRequiresDemoTarget() {
        Account supplier = new Account(Name = 'Supplier B');
        insert supplier;

        Boolean thrown = false;

        Test.startTest();
        try {
            CMQbrMeetingPrepController.generateMeetingPreparation(supplier.Id, '資材處', null);
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void generateMeetingPreparationNormalizesIssueFiveAndSixOutput() {
        Account focus = new Account(
            Name = 'Focus Company',
            CM_Is_Demo_Target__c = true
        );
        Account supplier = new Account(Name = 'Supplier For Normalization', Industry = 'Electronics');
        insert new List<Account>{ focus, supplier };

        CMQbrMeetingPrepController.testPromptResponse = buildPromptResponseWithIssueFiveSixDefects();

        Test.startTest();
        CMQbrMeetingPrepController.GenerateResult result =
            CMQbrMeetingPrepController.generateMeetingPreparation(supplier.Id, '資材處', null);
        CMQbrMeetingPrepController.EditableSlidesPayload payload =
            CMQbrMeetingPrepController.getEditableSlides(result.meetingId);
        Test.stopTest();

        System.assertNotEquals(null, payload);
        System.assertEquals(true, payload.pageFiveHasTable);
        System.assertEquals(true, payload.pageSixHasTable);
        System.assert(payload.pageFiveAvailableRows.size() > 0);
        System.assert(payload.pageSixAvailableRows.size() > 0);
        System.assertEquals('商務項目', payload.pageSixTableHeaders[0]);

        CM_QBR_Meeting__c meeting = [
            SELECT Slide_05_Content__c, Slide_06_Content__c
            FROM CM_QBR_Meeting__c
            WHERE Id = :result.meetingId
            LIMIT 1
        ];

        Map<String, Object> slideFive = (Map<String, Object>) JSON.deserializeUntyped(meeting.Slide_05_Content__c);
        Map<String, Object> slideSix = (Map<String, Object>) JSON.deserializeUntyped(meeting.Slide_06_Content__c);
        Map<String, Object> slideFiveTable = (Map<String, Object>) slideFive.get('table_data');
        Map<String, Object> slideSixTable = (Map<String, Object>) slideSix.get('table_data');

        List<Object> slideFiveRows = (List<Object>) slideFiveTable.get('rows');
        List<Object> slideSixRows = (List<Object>) slideSixTable.get('rows');
        List<Object> slideSixHeaders = (List<Object>) slideSixTable.get('headers');

        System.assertEquals(true, (Boolean) slideFiveTable.get('has_table'));
        System.assertEquals(true, (Boolean) slideSixTable.get('has_table'));
        System.assert(slideFiveRows.size() > 0);
        System.assert(slideSixRows.size() > 0);
        System.assertEquals('商務項目', String.valueOf(slideSixHeaders[0]));

        CMQbrMeetingPrepController.testPromptResponse = null;
    }

    @IsTest
    static void getPresentationExportOptionsReturnsNineTopics() {
        Account focus = new Account(
            Name = 'Focus Company',
            CM_Is_Demo_Target__c = true
        );
        Account supplier = new Account(Name = 'Supplier For Export Options', Industry = 'Electronics');
        insert new List<Account>{ focus, supplier };

        CMQbrMeetingPrepController.testPromptResponse = buildPromptResponse();
        CMQbrMeetingPrepController.GenerateResult generated =
            CMQbrMeetingPrepController.generateMeetingPreparation(supplier.Id, '資材處', null);

        Test.startTest();
        CMQbrMeetingPrepController.PresentationExportOptionsPayload payload =
            CMQbrMeetingPrepController.getPresentationExportOptions(generated.meetingId);
        Test.stopTest();

        System.assertNotEquals(null, payload);
        System.assertEquals(generated.meetingId, payload.meetingId);
        System.assertEquals(9, payload.topics.size());
        System.assertEquals(1, payload.topics[0].slideNumber);
        System.assertEquals(true, payload.topics[0].selected);
        System.assertEquals('Focus Company公司簡介', payload.topics[0].topicTitle);
        System.assertEquals('Supplier For Export Options 公司簡介', payload.topics[1].topicTitle);
        System.assertEquals(
            'Focus Company公司營運概述暨新產品技術/組織變動簡介',
            payload.topics[2].topicTitle
        );
        System.assert(!String.isBlank(payload.topics[0].topicTitle));
        System.assert(!String.isBlank(payload.topics[0].slideTitle));

        CMQbrMeetingPrepController.testPromptResponse = null;
    }

    @IsTest
    static void generatePresentationFileCreatesSelectedSlidesContent() {
        Account focus = new Account(
            Name = 'Focus Company',
            CM_Is_Demo_Target__c = true
        );
        Account supplier = new Account(Name = 'Supplier For Export File', Industry = 'Electronics');
        insert new List<Account>{ focus, supplier };

        CMQbrMeetingPrepController.testPromptResponse = buildPromptResponse();
        CMQbrMeetingPrepController.testPptxTemplateBlob = buildPresentationTemplateBlob();
        CMQbrMeetingPrepController.GenerateResult generated =
            CMQbrMeetingPrepController.generateMeetingPreparation(supplier.Id, '資材處', null);

        Test.startTest();
        CMQbrMeetingPrepController.PresentationFilePayload filePayload =
            CMQbrMeetingPrepController.generatePresentationFile(
                generated.meetingId,
                new List<Integer>{ 1, 3, 6 }
            );
        Test.stopTest();

        System.assertNotEquals(null, filePayload);
        System.assertNotEquals(null, filePayload.contentVersionId);
        System.assertNotEquals(null, filePayload.contentDocumentId);
        System.assert(filePayload.fileName.endsWith('.pptx'));
        System.assert(filePayload.fileUrl.contains(String.valueOf(filePayload.contentDocumentId)));

        ContentVersion saved = [
            SELECT Id, VersionData
            FROM ContentVersion
            WHERE Id = :filePayload.contentVersionId
            LIMIT 1
        ];
        Compression.ZipReader reader = new Compression.ZipReader(saved.VersionData);
        Map<String, String> entryTextByName = new Map<String, String>();
        for (Compression.ZipEntry entry : reader.getEntries()) {
            String entryName = entry.getName();
            if (entryName.endsWith('.xml')) {
                entryTextByName.put(entryName, reader.extract(entry).toString());
            }
        }

        System.assert(entryTextByName.containsKey('ppt/slides/slide1.xml'));
        System.assert(entryTextByName.containsKey('ppt/slides/slide2.xml'));
        System.assert(entryTextByName.containsKey('ppt/slides/slide3.xml'));
        System.assert(entryTextByName.containsKey('ppt/slides/slide4.xml'));
        System.assert(entryTextByName.containsKey('ppt/notesSlides/notesSlide1.xml'));
        System.assert(entryTextByName.containsKey('ppt/notesSlides/notesSlide2.xml'));
        System.assert(entryTextByName.containsKey('ppt/notesSlides/notesSlide3.xml'));
        System.assert(entryTextByName.containsKey('ppt/notesSlides/notesSlide4.xml'));
        System.assert(!entryTextByName.containsKey('ppt/slides/slide5.xml'));
        System.assert(entryTextByName.get('ppt/slides/slide1.xml').contains('QBR Meeting Preparation'));
        System.assert(entryTextByName.get('ppt/slides/slide2.xml').contains('XXX公司簡介 - 測試標題'));
        System.assert(entryTextByName.get('ppt/slides/slide3.xml').contains('XXX公司營運概況暨XXX新產品技術、組織變動簡介 - 測試標題'));
        System.assert(entryTextByName.get('ppt/slides/slide4.xml').contains('雙方商務指標回顧 - 測試標題'));
        System.assert(!entryTextByName.get('ppt/slides/slide2.xml').contains('議題 1：'));
        System.assert(!entryTextByName.get('ppt/slides/slide2.xml').contains('Topic'));
        System.assert(!entryTextByName.get('ppt/slides/slide2.xml').contains('Speaker Notes (Summary)'));
        System.assert(entryTextByName.get('ppt/notesSlides/notesSlide2.xml').contains('備註內容 1'));
        System.assert(entryTextByName.get('ppt/notesSlides/notesSlide3.xml').contains('備註內容 3'));
        System.assert(entryTextByName.get('ppt/notesSlides/notesSlide4.xml').contains('備註內容 6'));
        System.assert(entryTextByName.get('[Content_Types].xml').contains('/ppt/slides/slide4.xml'));
        System.assert(!entryTextByName.get('[Content_Types].xml').contains('/ppt/slides/slide5.xml'));
        System.assert(entryTextByName.get('[Content_Types].xml').contains('/ppt/notesMasters/notesMaster1.xml'));
        System.assert(entryTextByName.get('[Content_Types].xml').contains('/ppt/notesSlides/notesSlide4.xml'));

        CMQbrMeetingPrepController.testPromptResponse = null;
        CMQbrMeetingPrepController.testPptxTemplateBlob = null;
    }

    private static String buildPromptResponse() {
        List<String> topics = new List<String>{
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

        List<Object> slides = new List<Object>();
        for (Integer index = 0; index < topics.size(); index++) {
            Integer slideNumber = index + 1;

            Map<String, Object> tableData = new Map<String, Object>();
            if (slideNumber == 5 || slideNumber == 6 || Math.mod(slideNumber, 2) == 0) {
                tableData.put('has_table', true);
                tableData.put('headers', new List<String>{ '項目', '內容' });
                tableData.put(
                    'rows',
                    new List<Object>{
                        new List<String>{ 'Row 1', 'Value ' + String.valueOf(slideNumber) + '-1' },
                        new List<String>{ 'Row 2', 'Value ' + String.valueOf(slideNumber) + '-2' }
                    }
                );
            } else {
                tableData.put('has_table', false);
                tableData.put('headers', new List<String>());
                tableData.put('rows', new List<Object>());
            }

            Map<String, Object> slide = new Map<String, Object>();
            slide.put('slide_number', slideNumber);
            slide.put('slide_title', topics[index] + ' - 測試標題');
            slide.put(
                'bullet_points',
                new List<String>{
                    '重點一 ' + String.valueOf(slideNumber),
                    '重點二 ' + String.valueOf(slideNumber),
                    '重點三 ' + String.valueOf(slideNumber)
                }
            );
            slide.put('table_data', tableData);
            slide.put('speaker_notes', '備註內容 ' + String.valueOf(slideNumber));
            slides.add(slide);
        }

        Map<String, Object> payload = new Map<String, Object>{
            'presentation_meta' => new Map<String, Object>{
                'focus_company' => 'Focus Company',
                'root_account' => 'Micron',
                'department' => '資材處'
            },
            'slides' => slides
        };
        return JSON.serialize(payload);
    }

    private static String buildPromptResponseWithIssueFiveSixDefects() {
        List<String> topics = new List<String>{
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

        List<Object> slides = new List<Object>();
        for (Integer index = 0; index < topics.size(); index++) {
            Integer slideNumber = index + 1;

            Map<String, Object> tableData = new Map<String, Object>{
                'has_table' => false,
                'headers' => new List<String>(),
                'rows' => new List<Object>()
            };
            List<String> bulletPoints = new List<String>{
                '重點一 ' + String.valueOf(slideNumber),
                '重點二 ' + String.valueOf(slideNumber),
                '重點三 ' + String.valueOf(slideNumber)
            };

            if (slideNumber == 5) {
                bulletPoints = new List<String>{
                    '交期延誤：已建立 VMI 每週追蹤機制',
                    'RMA 回覆時間過長：跨部門改善中',
                    '品質異常結案率提升：持續監控'
                };
            }

            if (slideNumber == 6) {
                bulletPoints = new List<String>{
                    'YTD 採購總金額達 $4,350 萬美金，YoY 成長 18%。',
                    '主要產品線佔比：5G 模組 55%、Wi-Fi AP 30%、其他 15%。',
                    '主要成長動能來自新產品導入與客戶需求提升。'
                };
                tableData = new Map<String, Object>{
                    'has_table' => true,
                    'headers' => new List<String>{ 'KPI 項目', '權重', '目標值', '實際值', '評分' },
                    'rows' => new List<Object>{
                        new List<String>{ 'OTD', '30%', '95%', '91%', 'B' },
                        new List<String>{ 'DPPM', '30%', '< 200', '180', 'A' },
                        new List<String>{ 'Cost', '25%', '-3%', '-1.2%', 'C' }
                    }
                };
            }

            Map<String, Object> slide = new Map<String, Object>();
            slide.put('slide_number', slideNumber);
            slide.put('slide_title', topics[index] + ' - 測試標題');
            slide.put('bullet_points', bulletPoints);
            slide.put('table_data', tableData);
            slide.put('speaker_notes', '備註內容 ' + String.valueOf(slideNumber));
            slides.add(slide);
        }

        Map<String, Object> payload = new Map<String, Object>{
            'presentation_meta' => new Map<String, Object>{
                'focus_company' => 'Focus Company',
                'root_account' => 'Micron',
                'department' => '資材處'
            },
            'slides' => slides
        };
        return JSON.serialize(payload);
    }

    private static Blob buildPresentationTemplateBlob() {
        Compression.ZipWriter writer = new Compression.ZipWriter();
        writer.addEntry(
            '[Content_Types].xml',
            Blob.valueOf(
                '<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\'?>'
                + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
                + '<Default Extension="bin" ContentType="application/vnd.openxmlformats-officedocument.presentationml.printerSettings"/>'
                + '<Default Extension="jpeg" ContentType="image/jpeg"/>'
                + '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
                + '<Default Extension="xml" ContentType="application/xml"/>'
                + '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
                + '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
                + '<Override PartName="/ppt/presProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presProps+xml"/>'
                + '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
                + '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
                + '<Override PartName="/ppt/slideLayouts/slideLayout2.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
                + '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>'
                + '<Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'
                + '<Override PartName="/ppt/tableStyles.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.tableStyles+xml"/>'
                + '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>'
                + '<Override PartName="/ppt/viewProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.viewProps+xml"/>'
                + '</Types>'
            )
        );
        writer.addEntry(
            '_rels/.rels',
            Blob.valueOf(
                '<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\'?>'
                + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                + '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>'
                + '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail" Target="docProps/thumbnail.jpeg"/>'
                + '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
                + '<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
                + '</Relationships>'
            )
        );
        writer.addEntry(
            'docProps/app.xml',
            Blob.valueOf(
                '<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\'?>'
                + '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" />'
            )
        );
        writer.addEntry(
            'docProps/core.xml',
            Blob.valueOf(
                '<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\'?>'
                + '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"/>'
            )
        );
        writer.addEntry(
            'docProps/thumbnail.jpeg',
            Blob.valueOf('thumbnail')
        );
        writer.addEntry(
            'ppt/presentation.xml',
            Blob.valueOf(
                '<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\'?>'
                + '<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"'
                + ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
                + ' xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
                + '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
                + '<p:sldIdLst><p:sldId id="256" r:id="rId7"/></p:sldIdLst>'
                + '<p:sldSz cx="9144000" cy="6858000" type="screen4x3"/>'
                + '<p:notesSz cx="6858000" cy="9144000"/>'
                + '<p:defaultTextStyle/>'
                + '</p:presentation>'
            )
        );
        writer.addEntry(
            'ppt/_rels/presentation.xml.rels',
            Blob.valueOf(
                '<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\'?>'
                + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                + '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>'
                + '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/printerSettings" Target="printerSettings/printerSettings1.bin"/>'
                + '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/presProps" Target="presProps.xml"/>'
                + '<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/viewProps" Target="viewProps.xml"/>'
                + '<Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>'
                + '<Relationship Id="rId6" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/tableStyles" Target="tableStyles.xml"/>'
                + '<Relationship Id="rId7" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/>'
                + '</Relationships>'
            )
        );
        writer.addEntry(
            'ppt/presProps.xml',
            Blob.valueOf('<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\'?><p:presentationPr xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"/>')
        );
        writer.addEntry(
            'ppt/viewProps.xml',
            Blob.valueOf('<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\'?><p:viewPr xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"/>')
        );
        writer.addEntry(
            'ppt/theme/theme1.xml',
            Blob.valueOf('<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\'?><a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Office"/>')
        );
        writer.addEntry(
            'ppt/tableStyles.xml',
            Blob.valueOf('<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\'?><a:tblStyleLst xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"/>')
        );
        writer.addEntry(
            'ppt/slideMasters/slideMaster1.xml',
            Blob.valueOf('<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\'?><p:sldMaster xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"/>')
        );
        writer.addEntry(
            'ppt/slideMasters/_rels/slideMaster1.xml.rels',
            Blob.valueOf('<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\'?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>')
        );
        writer.addEntry(
            'ppt/slideLayouts/slideLayout1.xml',
            Blob.valueOf('<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\'?><p:sldLayout xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"/>')
        );
        writer.addEntry(
            'ppt/slideLayouts/slideLayout2.xml',
            Blob.valueOf('<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\'?><p:sldLayout xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"/>')
        );
        writer.addEntry(
            'ppt/slides/slide1.xml',
            Blob.valueOf('<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\'?><p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"/>')
        );
        writer.addEntry(
            'ppt/slides/_rels/slide1.xml.rels',
            Blob.valueOf('<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\'?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>')
        );
        writer.addEntry(
            'ppt/printerSettings/printerSettings1.bin',
            Blob.valueOf('printer')
        );
        return writer.getArchive();
    }
}