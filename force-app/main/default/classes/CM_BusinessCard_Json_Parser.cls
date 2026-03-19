public with sharing class CM_BusinessCard_Json_Parser {
    @InvocableMethod(label='Parse Business Card JSON to Events' description='Parses a JSON string of business cards into a collection of Business Card Processed platform events.')
    public static List<List<Business_Card_Processed__e>> parseJsonToEvents(List<String> jsonStrings) {
        List<List<Business_Card_Processed__e>> outputs = new List<List<Business_Card_Processed__e>>();
        if (jsonStrings == null || jsonStrings.isEmpty()) {
            outputs.add(new List<Business_Card_Processed__e>());
            return outputs;
        }

        Integer position = 0;
        for (String rawJson : jsonStrings) {
            position++;
            List<Business_Card_Processed__e> events = new List<Business_Card_Processed__e>();

            if (String.isBlank(rawJson)) {
                outputs.add(events);
                continue;
            }

            try {
                List<CM_BusinessCard_Controller.CM_CardData> cardDataList =
                    (List<CM_BusinessCard_Controller.CM_CardData>) JSON.deserialize(
                        rawJson,
                        List<CM_BusinessCard_Controller.CM_CardData>.class
                    );

                if (cardDataList != null) {
                    for (CM_BusinessCard_Controller.CM_CardData card : cardDataList) {
                        if (card == null) {
                            continue;
                        }
                        events.add(buildEvent(card));
                    }
                }
            } catch (Exception ex) {
                throw new FlowException(String.format(
                    Label.CM_BC_Err_JsonParseFailed,
                    new List<String>{ String.valueOf(position), String.valueOf(ex.getMessage()) }
                ));
            }

            outputs.add(events);
        }

        return outputs;
    }

    private static Business_Card_Processed__e buildEvent(CM_BusinessCard_Controller.CM_CardData card) {
        Business_Card_Processed__e eventRecord = new Business_Card_Processed__e();
        eventRecord.FirstName__c = trimToField(clean(card.FirstName), Business_Card_Processed__e.FirstName__c);
        eventRecord.LastName__c = trimToField(fallbackLastName(card), Business_Card_Processed__e.LastName__c);
        eventRecord.Company__c = trimToField(fallbackCompany(card), Business_Card_Processed__e.Company__c);
        eventRecord.Title__c = trimToField(clean(card.Title), Business_Card_Processed__e.Title__c);
        eventRecord.Email__c = trimToField(clean(card.Email), Business_Card_Processed__e.Email__c);
        eventRecord.Phone__c = trimToField(clean(card.Phone), Business_Card_Processed__e.Phone__c);
        eventRecord.MobilePhone__c = trimToField(clean(card.MobilePhone), Business_Card_Processed__e.MobilePhone__c);
        eventRecord.Street__c = trimToField(clean(card.Street), Business_Card_Processed__e.Street__c);
        eventRecord.City__c = trimToField(clean(card.City), Business_Card_Processed__e.City__c);
        eventRecord.State__c = trimToField(clean(card.State), Business_Card_Processed__e.State__c);
        eventRecord.PostalCode__c = trimToField(clean(card.PostalCode), Business_Card_Processed__e.PostalCode__c);
        eventRecord.Country__c = trimToField(clean(card.Country), Business_Card_Processed__e.Country__c);
        eventRecord.Description__c = trimToField(buildDescription(card), Business_Card_Processed__e.Description__c);
        String createAs = resolveCreateAs(card);
        eventRecord.Create_As__c = trimToField(createAs, Business_Card_Processed__e.Create_As__c);
        eventRecord.LeadSource__c = trimToField(clean(card.LeadSource), Business_Card_Processed__e.LeadSource__c);
        eventRecord.Matched_Account_Id__c = 'Contact'.equalsIgnoreCase(createAs)
            ? trimToField(clean(card.ExistingAccountId), Business_Card_Processed__e.Matched_Account_Id__c)
            : null;
        return eventRecord;
    }

    private static String clean(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static String trimToField(String value, Schema.SObjectField fieldRef) {
        if (String.isBlank(value) || fieldRef == null) {
            return value == null ? null : value.trim();
        }
        Integer maxLen = fieldRef.getDescribe().getLength();
        String trimmed = value.trim();
        if (maxLen == null || maxLen <= 0 || trimmed.length() <= maxLen) {
            return trimmed;
        }
        return trimmed.substring(0, maxLen);
    }

    private static String buildDescription(CM_BusinessCard_Controller.CM_CardData card) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(card.Remark)) {
            parts.add(String.format(
                Label.CM_BC_Remark_Prefix,
                new List<String>{ card.Remark.trim() }
            ));
        }
        if (String.isNotBlank(card.Description)) {
            parts.add(card.Description.trim());
        }
        return parts.isEmpty() ? null : String.join(parts, '\n---\n');
    }

    private static String resolveCreateAs(CM_BusinessCard_Controller.CM_CardData card) {
        String desired = clean(card.CreateAs);
        if (desired == null) {
            return 'Lead';
        }
        if ('Contact'.equalsIgnoreCase(desired) && String.isNotBlank(card.ExistingAccountId)) {
            return 'Contact';
        }
        return 'Lead';
    }

    private static String fallbackLastName(CM_BusinessCard_Controller.CM_CardData card) {
        String lastName = clean(card.LastName);
        if (lastName != null) {
            return lastName;
        }
        String firstName = clean(card.FirstName);
        if (firstName != null) {
            return firstName;
        }
        String company = clean(card.Company);
        if (company != null) {
            return company;
        }
        return Label.CM_BC_Fallback_BusinessCard;
    }

    private static String fallbackCompany(CM_BusinessCard_Controller.CM_CardData card) {
        String company = clean(card.Company);
        if (company != null) {
            return company;
        }
        String lastName = clean(card.LastName);
        if (lastName != null) {
            return lastName;
        }
        String firstName = clean(card.FirstName);
        if (firstName != null) {
            return firstName;
        }
        return Label.CM_BC_Fallback_BusinessCard;
    }
}