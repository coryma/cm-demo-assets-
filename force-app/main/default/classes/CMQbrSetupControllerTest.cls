@IsTest
private class CMQbrSetupControllerTest {
    @IsTest
    static void getSetupFallsBackToDefaultWhenNoRecord() {
        Test.startTest();
        CMQbrSetupController.SetupPayload payload = CMQbrSetupController.getSetup();
        Test.stopTest();

        System.assertNotEquals(null, payload);
        System.assertEquals(true, payload.isDefault);
        System.assertEquals(9, payload.topics.size());
        System.assert(payload.englishTopics.contains('Review of last QBR action items'));
    }

    @IsTest
    static void saveSetupNormalizesAndReturnsTopics() {
        String english = 'Topic A\n\n Topic B  ';
        String chinese = '議題甲\n\n 議題乙  ';

        Test.startTest();
        CMQbrSetupController.SetupPayload payload = CMQbrSetupController.saveSetup(english, chinese);
        Test.stopTest();

        System.assertEquals(false, payload.isDefault);
        System.assertEquals('Topic A\nTopic B', payload.englishTopics);
        System.assertEquals('議題甲\n議題乙', payload.chineseTopics);
        System.assertEquals(2, payload.topics.size());

        CM_QBR_Setup__c saved = [
            SELECT English_Topics__c, Chinese_Topics__c, Is_Active__c
            FROM CM_QBR_Setup__c
            LIMIT 1
        ];
        System.assertEquals('Topic A\nTopic B', saved.English_Topics__c);
        System.assertEquals('議題甲\n議題乙', saved.Chinese_Topics__c);
        System.assertEquals(true, saved.Is_Active__c);
    }

    @IsTest
    static void saveSetupRejectsMismatchedLineCounts() {
        Boolean thrown = false;

        Test.startTest();
        try {
            CMQbrSetupController.saveSetup('A\nB', '甲');
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void generateBriefingFileCreatesContentVersionFromSetup() {
        CMQbrSetupController.saveSetup('Topic A\nTopic B', '議題甲\n議題乙');

        Test.startTest();
        CMQbrSetupController.GeneratedFilePayload payload = CMQbrSetupController.generateBriefingFile();
        Test.stopTest();

        System.assertNotEquals(null, payload);
        System.assertNotEquals(null, payload.contentVersionId);
        System.assertNotEquals(null, payload.contentDocumentId);
        System.assert(payload.fileName.endsWith('.html'));
        System.assert(payload.fileUrl.contains(String.valueOf(payload.contentDocumentId)));

        ContentVersion version = [
            SELECT Id, ContentDocumentId, PathOnClient, Title, VersionData
            FROM ContentVersion
            WHERE Id = :payload.contentVersionId
            LIMIT 1
        ];
        String html = version.VersionData.toString();
        System.assertEquals(payload.contentDocumentId, version.ContentDocumentId);
        System.assert(version.PathOnClient.endsWith('.html'));
        System.assert(html.contains('Topic A'));
        System.assert(html.contains('議題甲'));
    }
}