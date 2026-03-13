public with sharing class CM_LatestLeadsController {
    @AuraEnabled(cacheable=false)
    public static List<LeadDTO> fetchLatestLeads(Integer limitSize) {
        if (limitSize == null || limitSize <= 0) limitSize = 20;

        List<Lead> leads = [
            SELECT Id, Name, Company, Phone, Status, CreatedDate,
                   AI_Score__c, AI_Classification__c, AI_Reason__c,
                   AI_KeyTopics__c, AI_ReplyRecommendation__c
            FROM Lead
            WHERE IsDeleted = FALSE
            ORDER BY CreatedDate DESC, AI_Score__c DESC NULLS LAST
            LIMIT :limitSize
        ];

        List<LeadDTO> outList = new List<LeadDTO>();
        for (Lead l : leads) {
            LeadDTO d = new LeadDTO();
            d.id = l.Id;
            d.name = l.Name;
            d.company = l.Company;
            d.phone = l.Phone;
            d.status = l.Status;
            d.createdDate = l.CreatedDate;
            d.aiScore = l.AI_Score__c;
            d.recordUrl = '/lightning/r/Lead/' + l.Id + '/view';

            // ✅ 將 __c 欄位映射到乾淨名稱
            d.aiClassification       = l.AI_Classification__c;
            d.aiReason               = l.AI_Reason__c;
            d.aiKeyTopics            = l.AI_KeyTopics__c;
            d.aiReplyRecommendation  = l.AI_ReplyRecommendation__c;

            outList.add(d);
        }
        return outList;
    }

    public class LeadDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String company;
        @AuraEnabled public String phone;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Decimal aiScore;
        @AuraEnabled public String recordUrl;

        // ✅ 乾淨變數名稱（不能含 __c）
        @AuraEnabled public String aiClassification;
        @AuraEnabled public String aiReason;
        @AuraEnabled public String aiKeyTopics;
        @AuraEnabled public String aiReplyRecommendation;
    }
}