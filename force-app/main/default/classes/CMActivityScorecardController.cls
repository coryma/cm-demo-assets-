public with sharing class CMActivityScorecardController {
    private static final Integer DEFAULT_LOOKBACK_DAYS = 30;
    private static final Integer MAX_LOOKBACK_DAYS = 365;
    private static final Set<String> CALL_TASK_TYPES = new Set<String>{'Call', 'Phone', 'Call Log', 'Outbound Call', 'Inbound Call'};
    private static final Set<String> CALL_TASK_SUBTYPES = new Set<String>{'Call'};

    public class ScorecardResponse {
        @AuraEnabled public String headerLabel;
        @AuraEnabled public List<SummaryItem> summary = new List<SummaryItem>();
        @AuraEnabled public List<ActivityItem> activities = new List<ActivityItem>();
    }

    public class SummaryItem {
        @AuraEnabled public String label;
        @AuraEnabled public Integer value;
        @AuraEnabled public String variant;
        @AuraEnabled public String detail;

        public SummaryItem(String label, Integer value, String variant, String detail) {
            this.label = label;
            this.value = value;
            this.variant = variant;
            this.detail = detail;
        }
    }

    public class ActivityItem {
        @AuraEnabled public String label;
        @AuraEnabled public Integer value;
        @AuraEnabled public Integer personalBest;
        @AuraEnabled public String iconName;
        @AuraEnabled public String theme;
        @AuraEnabled public Boolean isNewPersonalBest;

        public ActivityItem(String label, Integer value, Integer personalBest, String iconName, String theme, Boolean isNewPersonalBest) {
            this.label = label;
            this.value = value;
            this.personalBest = personalBest;
            this.iconName = iconName;
            this.theme = theme;
            this.isNewPersonalBest = isNewPersonalBest;
        }
    }

    @AuraEnabled(cacheable=true)
    public static ScorecardResponse loadScorecard(Id accountId, Integer lookbackDays) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }

        Boolean useChineseLabels = shouldUseChineseLabels();
        Integer windowDays = sanitizeWindow(lookbackDays);
        Date windowStartDate = Date.today().addDays(1 - windowDays);
        DateTime windowStartDateTime = DateTime.newInstance(windowStartDate, Time.newInstance(0, 0, 0, 0));
        Date windowEndDate = Date.today();
        DateTime windowEndDateTime = System.now();

        Account accountRecord = fetchAccount(accountId);

        ScorecardResponse response = new ScorecardResponse();
        response.headerLabel = buildAccountHeader(accountRecord, windowDays, useChineseLabels);

        addSummary(response, new Set<Id>{ accountId }, windowStartDate, windowEndDate, windowDays, useChineseLabels);
        addActivities(response, new Set<Id>{ accountId }, windowStartDateTime, windowEndDateTime, useChineseLabels);

        return response;
    }

    @AuraEnabled(cacheable=true)
    public static ScorecardResponse loadScorecardForUser(Id userId, Integer lookbackDays) {
        Id targetUserId = userId != null ? userId : UserInfo.getUserId();

        Boolean useChineseLabels = shouldUseChineseLabels();
        Integer windowDays = sanitizeWindow(lookbackDays);
        Date windowStartDate = Date.today().addDays(1 - windowDays);
        DateTime windowStartDateTime = DateTime.newInstance(windowStartDate, Time.newInstance(0, 0, 0, 0));
        Date windowEndDate = Date.today();
        DateTime windowEndDateTime = System.now();

        List<Account> ownedAccounts = [SELECT Id FROM Account WHERE OwnerId = :targetUserId];
        Set<Id> accountIds = new Set<Id>();
        for (Account acct : ownedAccounts) {
            accountIds.add(acct.Id);
        }

        ScorecardResponse response = new ScorecardResponse();
        response.headerLabel = buildUserHeader(targetUserId, windowDays, useChineseLabels);

        addSummary(response, accountIds, windowStartDate, windowEndDate, windowDays, useChineseLabels);
        addActivities(response, accountIds, windowStartDateTime, windowEndDateTime, useChineseLabels);

        return response;
    }

    private static Integer sanitizeWindow(Integer lookbackDays) {
        Integer window = lookbackDays;
        if (window == null || window <= 0) {
            window = DEFAULT_LOOKBACK_DAYS;
        }
        return Math.min(window, MAX_LOOKBACK_DAYS);
    }

    private static Account fetchAccount(Id accountId) {
        List<Account> accounts = [SELECT Name FROM Account WHERE Id = :accountId LIMIT 1];
        if (accounts.isEmpty()) {
            throw new AuraHandledException('Account not found.');
        }
        return accounts[0];
    }

    private static String buildAccountHeader(Account accountRecord, Integer windowDays, Boolean useChineseLabels) {
        String baseTemplate = getLocalizedLabel(
            useChineseLabels,
            System.Label.CM_ActivityScorecard_BaseHeader,
            System.Label.CM_ActivityScorecard_BaseHeader_ZH_TW
        );
        String base = String.format(baseTemplate, new List<String>{ String.valueOf(windowDays) });
        if (String.isNotBlank(accountRecord.Name)) {
            return accountRecord.Name + ' · ' + base;
        }
        return base;
    }

    private static String buildUserHeader(Id userId, Integer windowDays, Boolean useChineseLabels) {
        String baseTemplate = getLocalizedLabel(
            useChineseLabels,
            System.Label.CM_ActivityScorecard_UserHeader,
            System.Label.CM_ActivityScorecard_UserHeader_ZH_TW
        );
        String base = String.format(baseTemplate, new List<String>{ String.valueOf(windowDays) });
        if (userId == null) {
            return base;
        }

        List<User> users = [SELECT Name FROM User WHERE Id = :userId LIMIT 1];
        if (!users.isEmpty() && String.isNotBlank(users[0].Name)) {
            return users[0].Name + ' · ' + base;
        }
        return base;
    }

    private static void addSummary(ScorecardResponse response, Set<Id> accountIds, Date windowStartDate, Date windowEndDate, Integer windowDays, Boolean useChineseLabels) {
        Integer dealsWon = 0;
        Integer dealsLost = 0;

        if (!accountIds.isEmpty()) {
            for (AggregateResult aggregate : [
                SELECT IsWon, COUNT(Id) total
                FROM Opportunity
                WHERE AccountId IN :accountIds
                    AND IsClosed = true
                    AND CloseDate >= :windowStartDate
                    AND CloseDate <= :windowEndDate
                GROUP BY IsWon
            ]) {
                Boolean isWon = (Boolean) aggregate.get('IsWon');
                Integer total = ((Decimal) aggregate.get('total')).intValue();
                if (isWon != null && isWon) {
                    dealsWon = total;
                } else {
                    dealsLost = total;
                }
            }
        }

        String summaryDetailTemplate = getLocalizedLabel(
            useChineseLabels,
            System.Label.CM_ActivityScorecard_SummaryDetail,
            System.Label.CM_ActivityScorecard_SummaryDetail_ZH_TW
        );
        String detailText = String.format(summaryDetailTemplate, new List<String>{ String.valueOf(windowDays) });
        response.summary.add(new SummaryItem(
            getLocalizedLabel(
                useChineseLabels,
                System.Label.CM_ActivityScorecard_DealsWon,
                System.Label.CM_ActivityScorecard_DealsWon_ZH_TW
            ),
            dealsWon,
            'success',
            detailText
        ));
        response.summary.add(new SummaryItem(
            getLocalizedLabel(
                useChineseLabels,
                System.Label.CM_ActivityScorecard_DealsLost,
                System.Label.CM_ActivityScorecard_DealsLost_ZH_TW
            ),
            dealsLost,
            'danger',
            detailText
        ));
    }

    private static void addActivities(ScorecardResponse response, Set<Id> accountIds, DateTime windowStartDateTime, DateTime windowEndDateTime, Boolean useChineseLabels) {
        Integer completedTasks = 0;
        Integer callsLogged = 0;
        Integer emailsSent = 0;
        Integer eventsLogged = 0;

        if (!accountIds.isEmpty()) {
            completedTasks = [
                SELECT COUNT()
                FROM Task
                WHERE AccountId IN :accountIds
                    AND Status = 'Completed'
                    AND IsDeleted = false
                    AND CreatedDate >= :windowStartDateTime
                    AND CreatedDate <= :windowEndDateTime
            ];

            callsLogged = [
                SELECT COUNT()
                FROM Task
                WHERE AccountId IN :accountIds
                    AND IsDeleted = false
                    AND CreatedDate >= :windowStartDateTime
                    AND CreatedDate <= :windowEndDateTime
                    AND (
                        Type IN :CALL_TASK_TYPES
                        OR TaskSubtype IN :CALL_TASK_SUBTYPES
                    )
            ];

            emailsSent = [
                SELECT COUNT()
                FROM EmailMessage
                WHERE RelatedToId IN :accountIds
                    AND IsDeleted = false
                    AND MessageDate >= :windowStartDateTime
                    AND MessageDate <= :windowEndDateTime
                    AND (Incoming = false OR Incoming = null)
            ];

            eventsLogged = [
                SELECT COUNT()
                FROM Event
                WHERE AccountId IN :accountIds
                    AND IsDeleted = false
                    AND StartDateTime >= :windowStartDateTime
                    AND StartDateTime <= :windowEndDateTime
            ];
        }

        response.activities.add(new ActivityItem(
            getLocalizedLabel(
                useChineseLabels,
                System.Label.CM_ActivityScorecard_TasksCompleted,
                System.Label.CM_ActivityScorecard_TasksCompleted_ZH_TW
            ),
            completedTasks,
            completedTasks,
            'utility:task',
            'success',
            false
        ));
        response.activities.add(new ActivityItem(
            getLocalizedLabel(
                useChineseLabels,
                System.Label.CM_ActivityScorecard_CallsLogged,
                System.Label.CM_ActivityScorecard_CallsLogged_ZH_TW
            ),
            callsLogged,
            callsLogged,
            'utility:call',
            'teal',
            false
        ));
        response.activities.add(new ActivityItem(
            getLocalizedLabel(
                useChineseLabels,
                System.Label.CM_ActivityScorecard_EmailsSent,
                System.Label.CM_ActivityScorecard_EmailsSent_ZH_TW
            ),
            emailsSent,
            emailsSent,
            'utility:email',
            'slate',
            false
        ));
        response.activities.add(new ActivityItem(
            getLocalizedLabel(
                useChineseLabels,
                System.Label.CM_ActivityScorecard_EventsLogged,
                System.Label.CM_ActivityScorecard_EventsLogged_ZH_TW
            ),
            eventsLogged,
            eventsLogged,
            'utility:event',
            'magenta',
            false
        ));
    }

    private static Boolean shouldUseChineseLabels() {
        String language = UserInfo.getLanguage();
        return String.isNotBlank(language) && language.toLowerCase().startsWith('zh');
    }

    private static String getLocalizedLabel(Boolean useChineseLabels, String englishLabel, String chineseLabel) {
        if (useChineseLabels && String.isNotBlank(chineseLabel)) {
            return chineseLabel;
        }
        return englishLabel;
    }
}