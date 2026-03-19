public with sharing class CMQbrSetupController {
    private static final List<String> DEFAULT_ENGLISH_LINES = new List<String>{
        'XXX brief company profile update',
        'Vendor brief company profile update',
        'XXX update business position / new products / new technology / organization change etc.',
        'Vendor update main customer / new products / new technology / capacity etc.',
        'Review of last QBR action items',
        'Mutual financial index update (ex: revenue ratio, growth rate by component base and major models per quarter or half year)',
        'Quality Issue Discussion',
        'Forecast for next quarter (or next half year)',
        'Critical highlight with support needed'
    };

    private static final List<String> DEFAULT_CHINESE_LINES = new List<String>{
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

    public class TopicPair {
        @AuraEnabled public String key;
        @AuraEnabled public String englishLabel;
        @AuraEnabled public String chineseLabel;
    }

    public class SetupPayload {
        @AuraEnabled public String englishTopics;
        @AuraEnabled public String chineseTopics;
        @AuraEnabled public List<TopicPair> topics;
        @AuraEnabled public Boolean isDefault;
    }

    public class GeneratedFilePayload {
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public String fileName;
        @AuraEnabled public String fileUrl;
    }

    @AuraEnabled(cacheable=true)
    public static SetupPayload getSetup() {
        CM_QBR_Setup__c setupRecord = getPreferredSetup();
        if (setupRecord == null) {
            return buildDefaultPayload();
        }

        List<String> englishLines = normalizeTopicLines(setupRecord.English_Topics__c);
        List<String> chineseLines = normalizeTopicLines(setupRecord.Chinese_Topics__c);
        if (englishLines.isEmpty() || chineseLines.isEmpty() || englishLines.size() != chineseLines.size()) {
            return buildDefaultPayload();
        }

        return buildPayload(englishLines, chineseLines, false);
    }

    @AuraEnabled
    public static SetupPayload saveSetup(String englishTopics, String chineseTopics) {
        List<String> englishLines = normalizeTopicLines(englishTopics);
        List<String> chineseLines = normalizeTopicLines(chineseTopics);

        if (englishLines.isEmpty()) {
            throw new AuraHandledException('English topics cannot be empty.');
        }
        if (chineseLines.isEmpty()) {
            throw new AuraHandledException('Chinese topics cannot be empty.');
        }
        if (englishLines.size() != chineseLines.size()) {
            throw new AuraHandledException('English and Chinese topic counts must match line by line.');
        }

        String normalizedEnglish = String.join(englishLines, '\n');
        String normalizedChinese = String.join(chineseLines, '\n');

        List<CM_QBR_Setup__c> activeSetups = [
            SELECT Id, Is_Active__c
            FROM CM_QBR_Setup__c
            WHERE Is_Active__c = true
            ORDER BY LastModifiedDate DESC
            LIMIT 200
        ];

        CM_QBR_Setup__c target;
        if (!activeSetups.isEmpty()) {
            target = activeSetups[0];
            target.English_Topics__c = normalizedEnglish;
            target.Chinese_Topics__c = normalizedChinese;
            target.Is_Active__c = true;
            update target;
        } else {
            target = new CM_QBR_Setup__c(
                English_Topics__c = normalizedEnglish,
                Chinese_Topics__c = normalizedChinese,
                Is_Active__c = true
            );
            insert target;
        }

        List<CM_QBR_Setup__c> inactiveUpdates = new List<CM_QBR_Setup__c>();
        for (CM_QBR_Setup__c extra : activeSetups) {
            if (extra.Id == target.Id) {
                continue;
            }
            extra.Is_Active__c = false;
            inactiveUpdates.add(extra);
        }
        if (!inactiveUpdates.isEmpty()) {
            update inactiveUpdates;
        }

        return buildPayload(englishLines, chineseLines, false);
    }

    @AuraEnabled
    public static GeneratedFilePayload generateBriefingFile() {
        SetupPayload setup = getSetup();
        List<String> englishLines = normalizeTopicLines(setup.englishTopics);
        List<String> chineseLines = normalizeTopicLines(setup.chineseTopics);

        if (englishLines.isEmpty() || chineseLines.isEmpty() || englishLines.size() != chineseLines.size()) {
            throw new AuraHandledException('QBR topics are not configured correctly.');
        }

        String quarter = deriveQuarter(Date.today());
        String timestamp = Datetime.now().format('yyyyMMdd_HHmmss');
        String fileTitle = 'QBR_Briefing_' + quarter.replace(' ', '_') + '_' + timestamp;
        String fileName = fileTitle + '.html';

        ContentVersion newFileVersion = new ContentVersion();
        newFileVersion.Title = fileTitle;
        newFileVersion.PathOnClient = fileName;
        newFileVersion.VersionData = Blob.valueOf(
            buildBriefingHtmlDocument(quarter, englishLines, chineseLines)
        );
        insert newFileVersion;

        ContentVersion savedFileVersion = [
            SELECT Id, ContentDocumentId, PathOnClient
            FROM ContentVersion
            WHERE Id = :newFileVersion.Id
            LIMIT 1
        ];

        GeneratedFilePayload payload = new GeneratedFilePayload();
        payload.contentVersionId = savedFileVersion.Id;
        payload.contentDocumentId = savedFileVersion.ContentDocumentId;
        payload.fileName = savedFileVersion.PathOnClient;
        payload.fileUrl = '/lightning/r/ContentDocument/' + String.valueOf(savedFileVersion.ContentDocumentId) + '/view';
        return payload;
    }

    private static CM_QBR_Setup__c getPreferredSetup() {
        List<CM_QBR_Setup__c> active = [
            SELECT Id, English_Topics__c, Chinese_Topics__c, Is_Active__c
            FROM CM_QBR_Setup__c
            WHERE Is_Active__c = true
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (!active.isEmpty()) {
            return active[0];
        }

        List<CM_QBR_Setup__c> latest = [
            SELECT Id, English_Topics__c, Chinese_Topics__c, Is_Active__c
            FROM CM_QBR_Setup__c
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return latest.isEmpty() ? null : latest[0];
    }

    private static SetupPayload buildDefaultPayload() {
        return buildPayload(DEFAULT_ENGLISH_LINES, DEFAULT_CHINESE_LINES, true);
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

    private static String buildBriefingHtmlDocument(
        String quarter,
        List<String> englishLines,
        List<String> chineseLines
    ) {
        String generatedAt = Datetime.now().format('yyyy-MM-dd HH:mm');
        String html = '';
        html += '<!DOCTYPE html><html><head><meta charset="UTF-8" />';
        html += '<title>QBR Briefing</title>';
        html += '<style>';
        html += 'body{font-family:Arial,sans-serif;margin:32px;color:#1f2933;}';
        html += 'h1{font-size:28px;margin-bottom:8px;}';
        html += 'p.meta{color:#52606d;margin-top:0;}';
        html += 'table{width:100%;border-collapse:collapse;margin-top:20px;}';
        html += 'th,td{border:1px solid #d9e2ec;padding:10px;vertical-align:top;}';
        html += 'th{background:#f5f7fa;text-align:left;}';
        html += '</style></head><body>';
        html += '<h1>' + escapeHtml(quarter) + ' QBR Briefing Template</h1>';
        html += '<p class="meta">Generated at ' + escapeHtml(generatedAt) + '</p>';
        html += '<table><thead><tr>';
        html += '<th style="width:56px;">#</th><th>English Topic</th><th>中文議題</th>';
        html += '</tr></thead><tbody>';

        for (Integer index = 0; index < englishLines.size(); index++) {
            html += '<tr><td>' + String.valueOf(index + 1) + '</td><td>';
            html += escapeHtml(englishLines[index]) + '</td><td>';
            html += escapeHtml(chineseLines[index]) + '</td></tr>';
        }

        html += '</tbody></table>';
        html += '</body></html>';
        return html;
    }

    private static SetupPayload buildPayload(
        List<String> englishLines,
        List<String> chineseLines,
        Boolean isDefault
    ) {
        SetupPayload payload = new SetupPayload();
        payload.englishTopics = String.join(englishLines, '\n');
        payload.chineseTopics = String.join(chineseLines, '\n');
        payload.isDefault = isDefault;
        payload.topics = new List<TopicPair>();

        for (Integer index = 0; index < englishLines.size(); index++) {
            TopicPair pair = new TopicPair();
            pair.key = 'TOPIC_' + String.valueOf(index + 1);
            pair.englishLabel = englishLines[index];
            pair.chineseLabel = chineseLines[index];
            payload.topics.add(pair);
        }
        return payload;
    }

    private static List<String> normalizeTopicLines(String raw) {
        List<String> lines = new List<String>();
        if (String.isBlank(raw)) {
            return lines;
        }

        String normalized = raw.replace('\r\n', '\n').replace('\r', '\n');
        for (String line : normalized.split('\n')) {
            if (String.isBlank(line)) {
                continue;
            }
            lines.add(line.trim());
        }
        return lines;
    }

    private static String escapeHtml(String value) {
        if (value == null) {
            return '';
        }
        return value.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;');
    }
}