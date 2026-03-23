# Email to Opportunity Inventory

## Scope
- Source org baseline: `coryma@coryma-260312.demo`
- Feature label: `Auto-Create Opps ✨`
- Entry object: `EmailMessage`

## Component Inventory
- `QuickAction`: `EmailMessage.Auto_Create_Opps`
- `Flow`: `CM_Email_To_Opptys`
- `ApexClass`: `CM_EmailToOpptyPromptInvoker`
- `ApexClass`: `CM_EmailToOpptyCreator`
- `ApexClass`: `CM_EmailToOpptyPromptInvokerTest`
- `ApexClass`: `CM_EmailToOpptyCreatorTest`
- `LightningComponentBundle`: `cmEmailOpptyJsonReview`
- `GenAiPromptTemplate`: `CM_Email_To_Opptys`
- `Layout`: `EmailMessage-Email Message Layout` (action list contains `EmailMessage.Auto_Create_Opps`)
- `CustomField`: `Opportunity.SourceEmailId__c`

## Runtime Flow
1. User clicks `Auto-Create Opps ✨` on EmailMessage record.
2. Flow calls `CM_EmailToOpptyPromptInvoker` to generate prompt JSON from email content.
3. Screen LWC (`cmEmailOpptyJsonReview`) displays up to 5 editable lines.
4. Flow calls `CM_EmailToOpptyCreator` with edited JSON to create Opportunity records.
5. Flow displays created/failed counts and detail message.

## Feature Manifest
- Use `manifest/features/email-to-opportunity.xml` for retrieve/deploy baseline.
