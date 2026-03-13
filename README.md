# cm-demo-assets

Salesforce demo component repository for Cory Ma.

This repo is intended to maintain demo-ready custom metadata that is actively used for sales demos. The source of truth for the first baseline is `coryma@coryma-240922.demo`.

## Current Baseline

Imported and verified:

- `Lead AI Scoring`
  - Trigger flow: `CM_Update_Lead_AI_Related_Fields`
  - Prompt template: `CM_Lead_Auto_Screening`
  - Apex parser/controller: `CM_LeadAIJsonParser`, `CM_LatestLeadsController`
  - Home component: `cmLatestLeads`
  - UI metadata: Lead layouts, Lead record pages, `MFG_HOME_DISCRETE_MCO`
  - Fields: `Lead.AI_Classification__c`, `Lead.AI_KeyTopics__c`, `Lead.AI_Reason__c`, `Lead.AI_ReplyRecommendation__c`, `Lead.AI_Score__c`

Planned demo features to add next:

- Business Card OCR / Lead conversion
- Email to Opportunity
- Account identity banner
- Supply network analysis
- Account news / Brave Search
- QBR preparation
- Meeting AI follow-up
- Email simulation
- Account SWOT analysis
- Activity scorecard

## Repo Rules

- Keep this repo limited to demo-ready components.
- Retrieve from org first; do not treat ad hoc local files as source of truth.
- When a feature needs UI, include both backend metadata and page/layout metadata.
- Do not commit auth files, retrieve ZIPs, or temporary folders.

## Common Commands

Retrieve one curated feature manifest:

```bash
./scripts/retrieve-feature.sh lead-ai-scoring coryma@coryma-240922.demo
```

Deploy one curated feature manifest:

```bash
./scripts/deploy-feature.sh lead-ai-scoring coryma-250312-demo
```
