public with sharing class CM_BusinessCard_LeadSource_Validator {
    public class Request {
        @InvocableVariable(required=true)
        public String leadSource;
    }

    public class Result {
        @InvocableVariable
        public Boolean isValid;
        @InvocableVariable
        public String normalized;
    }

    @InvocableMethod(
        label='Validate Lead Source'
        description='Validates LeadSource against active Lead picklist values.'
    )
    public static List<Result> validate(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null) {
            return results;
        }

        Map<String, String> normalizedByLower = new Map<String, String>();
        for (Schema.PicklistEntry pe : Lead.LeadSource.getDescribe().getPicklistValues()) {
            if (!pe.isActive()) {
                continue;
            }
            String val = pe.getValue();
            if (String.isBlank(val)) {
                continue;
            }
            String key = val.trim().toLowerCase();
            if (!normalizedByLower.containsKey(key)) {
                normalizedByLower.put(key, val.trim());
            }
        }

        for (Request req : requests) {
            Result res = new Result();
            String raw = req == null ? null : req.leadSource;
            String cleaned = String.isBlank(raw) ? null : raw.trim();
            if (cleaned != null) {
                String key = cleaned.toLowerCase();
                if (normalizedByLower.containsKey(key)) {
                    res.isValid = true;
                    res.normalized = normalizedByLower.get(key);
                    results.add(res);
                    continue;
                }
            }
            res.isValid = false;
            res.normalized = null;
            results.add(res);
        }
        return results;
    }
}