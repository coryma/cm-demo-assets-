public with sharing class CM_BusinessCard_Image_Helper {
    @AuraEnabled(cacheable=true)
    public static Id getDocIdFromVersion(Id anyId) {
        if (anyId == null) return null;
        String p = String.valueOf(anyId).substring(0,3);
        if (p == '069') return anyId; // Already a Document Id
        if (p == '068') {
            List<ContentVersion> vs = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :anyId LIMIT 1];
            return vs.isEmpty() ? null : vs[0].ContentDocumentId;
        }
        // Other cases: try treating it as a Document Id
        List<ContentVersion> latest = [SELECT ContentDocumentId FROM ContentVersion WHERE ContentDocumentId = :anyId AND IsLatest = true LIMIT 1];
        return latest.isEmpty() ? null : latest[0].ContentDocumentId;
    }
}