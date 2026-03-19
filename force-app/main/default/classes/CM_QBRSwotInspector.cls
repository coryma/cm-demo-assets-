public with sharing class CM_QBRSwotInspector {

    public class Request {
        @InvocableVariable(required=true)
        public Id accountId;
    }

    public class Result {
        @InvocableVariable public Boolean hasAccountPlan;
        @InvocableVariable public Boolean hasExistingSwot;
        @InvocableVariable public Boolean isCompleteSwot;
        @InvocableVariable public Boolean canGenerate;
        @InvocableVariable public Id accountPlanId;
        @InvocableVariable public String accountPlanName;
        @InvocableVariable public String lastModifiedLabel;
        @InvocableVariable public String statusMessage;
        @InvocableVariable public String strengthsPreviewHtml;
        @InvocableVariable public String weaknessesPreviewHtml;
        @InvocableVariable public String opportunitiesPreviewHtml;
        @InvocableVariable public String threatsPreviewHtml;
    }

    @InvocableMethod(label='Inspect Latest Account SWOT' description='Inspect the latest AccountPlan SWOT content for the selected Account')
    public static List<Result> inspect(List<Request> requests) {
        List<Result> results = new List<Result>();
        Boolean useChinese = isChineseLanguage();
        if (requests == null || requests.isEmpty()) {
            results.add(buildEmptyResult(useChinese));
            return results;
        }

        Set<Id> accountIds = new Set<Id>();
        for (Request request : requests) {
            if (request != null && request.accountId != null) {
                accountIds.add(request.accountId);
            }
        }

        Map<Id, AccountPlan> latestPlanByAccountId = new Map<Id, AccountPlan>();
        if (!accountIds.isEmpty()) {
            for (AccountPlan plan : [
                SELECT Id, AccountId, Name, LastModifiedDate,
                       RelationshipStrengths, RelationshipWeaknesses,
                       RelationshipOpportunities, RelationshipThreats
                FROM AccountPlan
                WHERE AccountId IN :accountIds
                ORDER BY AccountId, LastModifiedDate DESC
                LIMIT 200
            ]) {
                if (!latestPlanByAccountId.containsKey(plan.AccountId)) {
                    latestPlanByAccountId.put(plan.AccountId, plan);
                }
            }
        }

        for (Request request : requests) {
            Result result = new Result();
            if (request == null || request.accountId == null) {
                results.add(buildEmptyResult(useChinese));
                continue;
            }

            AccountPlan latestPlan = latestPlanByAccountId.get(request.accountId);
            if (latestPlan == null) {
                result.hasAccountPlan = false;
                result.hasExistingSwot = false;
                result.isCompleteSwot = false;
                result.canGenerate = false;
                result.statusMessage = useChinese
                    ? '目前找不到可用的客戶經營計劃，因此無法產生或套用 SWOT。此次將略過 SWOT。'
                    : 'No Account Plan was found. SWOT cannot be generated or applied in this run.';
                result.strengthsPreviewHtml = emptyPreview(useChinese);
                result.weaknessesPreviewHtml = emptyPreview(useChinese);
                result.opportunitiesPreviewHtml = emptyPreview(useChinese);
                result.threatsPreviewHtml = emptyPreview(useChinese);
                results.add(result);
                continue;
            }

            Boolean hasStrengths = !String.isBlank(latestPlan.RelationshipStrengths);
            Boolean hasWeaknesses = !String.isBlank(latestPlan.RelationshipWeaknesses);
            Boolean hasOpportunities = !String.isBlank(latestPlan.RelationshipOpportunities);
            Boolean hasThreats = !String.isBlank(latestPlan.RelationshipThreats);
            Boolean hasAny = hasStrengths || hasWeaknesses || hasOpportunities || hasThreats;
            Boolean hasAll = hasStrengths && hasWeaknesses && hasOpportunities && hasThreats;

            result.hasAccountPlan = true;
            result.hasExistingSwot = hasAny;
            result.isCompleteSwot = hasAll;
            result.canGenerate = true;
            result.accountPlanId = latestPlan.Id;
            result.accountPlanName = latestPlan.Name;
            result.lastModifiedLabel = formatDateTime(latestPlan.LastModifiedDate);
            result.statusMessage = buildStatusMessage(hasAny, hasAll, useChinese);
            result.strengthsPreviewHtml = previewOrEmpty(latestPlan.RelationshipStrengths, useChinese);
            result.weaknessesPreviewHtml = previewOrEmpty(latestPlan.RelationshipWeaknesses, useChinese);
            result.opportunitiesPreviewHtml = previewOrEmpty(latestPlan.RelationshipOpportunities, useChinese);
            result.threatsPreviewHtml = previewOrEmpty(latestPlan.RelationshipThreats, useChinese);
            results.add(result);
        }

        return results;
    }

    private static Result buildEmptyResult(Boolean useChinese) {
        Result result = new Result();
        result.hasAccountPlan = false;
        result.hasExistingSwot = false;
        result.isCompleteSwot = false;
        result.canGenerate = false;
        result.statusMessage = useChinese ? '未收到 SWOT 檢查請求。' : 'No SWOT inspection request payload.';
        result.strengthsPreviewHtml = emptyPreview(useChinese);
        result.weaknessesPreviewHtml = emptyPreview(useChinese);
        result.opportunitiesPreviewHtml = emptyPreview(useChinese);
        result.threatsPreviewHtml = emptyPreview(useChinese);
        return result;
    }

    private static String buildStatusMessage(Boolean hasAny, Boolean hasAll, Boolean useChinese) {
        if (!hasAny) {
            return useChinese
                ? '目前尚未建立 SWOT。你可以立即產生，或略過後直接繼續 QBR 準備。'
                : 'No SWOT content was found. You can generate it now or skip SWOT for this QBR.';
        }
        if (!hasAll) {
            return useChinese
                ? '已找到部分 SWOT 內容。你可以直接使用、重新產生並覆蓋，或本次略過。'
                : 'Partial SWOT content was found. You can use it, regenerate and overwrite it, or skip it for this QBR.';
        }
        return useChinese
            ? '已找到可用的 SWOT 內容。請確認是否沿用目前版本，或重新產生並覆蓋。'
            : 'Usable SWOT content was found. Confirm whether to keep it or regenerate and overwrite it.';
    }

    private static String previewOrEmpty(String sourceHtml, Boolean useChinese) {
        return String.isBlank(sourceHtml) ? emptyPreview(useChinese) : sourceHtml;
    }

    private static String emptyPreview(Boolean useChinese) {
        return useChinese
            ? '<p><i>目前尚未填寫。</i></p>'
            : '<p><i>No content yet.</i></p>';
    }

    private static String formatDateTime(Datetime value) {
        if (value == null) {
            return null;
        }
        return value.format('yyyy-MM-dd HH:mm');
    }

    private static Boolean isChineseLanguage() {
        String language = UserInfo.getLanguage();
        return !String.isBlank(language) && language.toLowerCase().startsWith('zh');
    }
}