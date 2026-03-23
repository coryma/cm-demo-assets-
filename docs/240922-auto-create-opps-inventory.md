# 240922 Auto Create Opps Inventory

## Scope
- Org: `coryma@coryma-240922.demo`
- Feature label: `Auto-Create Opps ✨`
- Entry object: `EmailMessage`

## Component Inventory
- `QuickAction`: `EmailMessage.Auto_Create_Opps`
- `Flow`: `CM_Email_To_Opptys` (active version 12)
- `ApexClass`: `CM_EmailToOpptyPromptInvoker`
- `ApexClass`: `CM_EmailToOpptyCreator`
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

## Findings and Risks
### P1
- `CM_EmailToOpptyCreator` hardcodes pricebook id `01sal0000026PtpAAE`.
- Impact: cross-org deploy/runtime failure risk when target org has different pricebook id.

### P1
- LWC limits preview/edit to first 5 `line_items`, but Apex creator iterates all `line_items`.
- Impact: records beyond the first 5 can still be created without user review.

### P2
- Flow has no fault screens/connectors for action failures.
- Impact: unhandled `FlowException` degrades user experience and troubleshooting.

### P2
- No unit test class found for `CM_EmailToOpptyPromptInvoker` / `CM_EmailToOpptyCreator`.
- Impact: higher regression risk for parser/prompt/creation logic changes.

## Recommended Remediation
1. Replace hardcoded pricebook id with Custom Metadata or a deterministic lookup.
2. Align behavior between UI and backend:
   - Option A: limit Apex creation to first 5 line items.
   - Option B: show all lines in UI and keep backend as-is.
3. Add fault path screens in `CM_Email_To_Opptys` to show actionable error details.
4. Add tests:
   - Prompt invoker JSON extraction/normalization.
   - Creator success/failure branches, product match/no-match, account resolution.

## Feature Manifest
- Use `manifest/features/240922-auto-create-opps.xml` for retrieve/deploy baseline.
