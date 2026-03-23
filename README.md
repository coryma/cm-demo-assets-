# cm-demo-assets

Salesforce demo metadata repository for Cory Ma.

## Inventory Scope

This inventory is based on **tracked files in this Git repo** (`git ls-files`).

- Included: code and metadata under `force-app/main/default`
- Excluded: local untracked files and ad hoc retrieve output

## Metadata Snapshot (Repo-Tracked)

- Apex classes: 40 (`80` files including `-meta.xml`)
- LWC bundles: 26 (`100` files)
- Flows: 7
- GenAI prompt templates: 20
- Custom objects: 9
- FlexiPages: 12
- Quick Actions: 4
- Permission Sets: 2
- Static Resources: 2 bundles (`cytoscape`, `CM_QBR_PPTX_Template`)

## Feature Inventory

### Focus Features (User-Facing)

#### 1) Lead AI Scoring (Frontstage)

- User value: score the current Lead content and show a lead scoring table on Home
- Entry: `CM_Lead_AI_Scoring`, `MFG_HOME_DISCRETE_MCO`
- Core assets: `cmLatestLeads`, `cmLeadAiScoringLab`, `CM_LeadAIScoringInvoker`, `CM_LeadAIJsonParser`, `CM_LatestLeadsController`

#### 2) Activity Scorecard (Frontstage)

- User value: show 30-day activity scorecard for current context
- Entry: `MFG_HOME_DISCRETE_MCO` (Home), `MFG_ACCOUNT_DISCRETE_ALL` (Account Record)
- Core assets: `cmActivityScorecard`, `CMActivityScorecardController`
- Verified in server org `260312` on 2026-03-23

#### 3) Identity Banner (Frontstage)

- User value: show account role/supplier identity context on account-facing pages
- Entry: `MFG_ACCOUNT_DISCRETE_ALL`
- Core assets: `cmAccountRoleIdentityBanner`, `cmSupplierIdentityBanner`

#### 4) Supply Network Analysis (Frontstage)

- User value: visualize supplier/customer network graph for the selected account
- Entry: `MFG_ACCOUNT_DISCRETE_ALL`
- Core assets: `cmSupplyNetworkGraph`, `CMSupplyNetworkGraphController`, `cytoscape`

#### 5) QBR Meeting Preparation (Frontstage)

- User value: prepare and edit AI-generated QBR meeting content, then export presentation file
- Entry: `Account.Prepare_QBR` button on `MFG_ACCOUNT_DISCRETE_ALL` (Account page)
- Core assets: `Account.Prepare_QBR`, `CM_Prepare_Account_QBR`, `cmQbrSetupPanel`, `cmQbrReviewBriefing`, `cmQbrDraftEmail`, `cmQbrPresentationExport`

#### 6) Account Plan Enhancement (Includes SWOT Generation)

- User value: enhance account plan with SWOT output and relationship context
- Entry: `Account_Plan_Record_Page`
- Core assets: `CM_Generate_AccountPlan_SWOT`, `AccountPlan.Generate_SWOT`, `cmQbrSwotDecision`, `CM_AccountPlanSWOTInvoker`, `CM_QBRSwotInspector`, `CM_SWOT_Analysis`, `cmRelationshipMapLauncher`

#### 7) QBR Meeting Follow-up (Frontstage)

- User value: generate follow-up summary, tasks, and draft outputs after meeting intake
- Entry: `Account.AI_Meeting_Follow_Up`
- Dependency: Backstage feature `Meeting Transcript Simulation` is required
- Core assets: `CM_AI_Advisor_Meeting_Screenflow`, `CMQBRAsyncEmailDraftService`, `CMQBRMeetingAnalysisService`, `CMQBRTranscriptResolver`, `CMFlowRecordCreator`

#### 8) Business Card OCR to Lead (Frontstage)

- User value: turn business card input into lead-ready structured data
- Core assets: `CM_BusinessCard_To_Lead`, `cmBusinessCardOcrUpload`, `cmBusinessCardReviewAsync`, `cmBusinessCardDisplayImageInFlow`, `CM_BusinessCard_*`

#### 9) Email to Opportunity Auto-Creation (Frontstage)

- User value: generate Opportunity candidates from an Email, review/edit line items, then create opportunities in one flow
- Entry: `EmailMessage.Auto_Create_Opps` quick action on EmailMessage
- Core assets: `CM_Email_To_Opptys`, `CM_EmailToOpptyPromptInvoker`, `CM_EmailToOpptyCreator`, `cmEmailOpptyJsonReview`, prompt `CM_Email_To_Opptys`, field `Opportunity.SourceEmailId__c`
- Install pack: `240922-auto-create-opps`

#### 10) Sample Request Submission (Frontstage)

- User value: create sample request records from an Opportunity and route by sample type
- Entry: `Opportunity.CM_Sample_Submission` quick action on Opportunity
- Core assets: `CM_Sample_Request_Flow`, `SampleRequest__c`, `Sample_Request`, `SampleRequestPath2`, `SampleRequestInStockPath`, `CM_Sample_Request_Access`
- Install pack: `sample-request`

### Backstage Setup and Simulation (Admin/Operations)

#### 1) Demo Setup (Foundation, install first)

- Purpose: choose active demo target account and maintain base account context
- Entry: `CM_Demo_Setup`
- Core assets: `CMDemoTargetSetupController`, `cmDemoTargetSetup`, `Account.CM_Is_Demo_Target__c`, `Account.CM_Supply_Scenario_Catalog__c`

#### 2) Account Role Setup (Backstage)

- Purpose: maintain account role configuration used by downstream frontstage views
- Entry: `CM_Account_Role_Setup`
- Core assets: `CMAccountRoleSetupController`, `cmAccountRoleSetup`

#### 3) News Setup and Account Targeting (Backstage)

- Purpose: configure which accounts should generate news and maintain news context data
- Entry: `CM_News_Setup`
- Core assets: `CM_Get_News_Prompt_Template_Flow`, `CM_Get_News_BY_API`, `cmNewsSetup`, prompts `CM_Account_News`, `CM_Account_News_Update`
- External endpoints: `GDELT_API`, `GNEWS_API`, `GOOGLE_NEWS_RSS`, `NEWS_API`

#### 4) Email Simulation (Backstage-only)

- Purpose: simulate email activity dataset for demo environments
- Entry: `CM_Email_Simulation`
- Core assets: `CM_Generate_Simulated_Emails`, `CMEmailSimulationController`, `CMEmailTimelineSimulationService`, `cmEmailSimulationSetup`, `cmEmailSimulationManager`

#### 5) Meeting Transcript Simulation (Backstage-only)

- Purpose: prepare synthetic transcript content/context for follow-up workflows
- Entry: `CM_Meeting_Transcript_Simulation`
- Core assets: `CMMeetingTranscriptSimulationController`, `cmMeetingTranscriptSimulation`, prompt `CM_Meeting_Transcript_Simulation_Gen`, object `CM_Meeting_Transcript__c`

#### 6) Lead AI Scoring Batch Simulation (Backstage)

- Purpose: simulate/update lead scoring context in bulk for demo readiness
- Core assets: `CM_Update_Lead_AI_Related_Fields`, prompt `CM_Lead_Auto_Screening_Demo`

#### 7) QBR Meeting Preparation Generation (Backstage)

- Purpose: configure participant companies and generate default QBR preparation content
- Entry: `CM_QBR_Setup`
- Core assets: `CM_Prepare_Account_QBR`, `CMQbrMeetingPrepController`, `CMQbrSetupController`, `cmQbrSetup`, `CM_QBRFlowService`, prompts `CM_CrossRole_MeetingBrief_Gen`, `CM_QBR_Supplier_Intro_From_File`, `CM_QBR_Follow_Up_Email_Draft`

## Manifest-Driven Feature Packs

Baseline packs (managed by `docs/install-plan.json`):

- `demo-setup`
- `account-role-setup`
- `email-simulation`
- `lead-ai-scoring`
- `supply-network-core`
- `supply-network-page`
- `qbr-preparation`

Optional packs (manual deploy when needed):

- `homepage-sync`
- `240922-auto-create-opps`
- `sample-request`

## New Org Installation Playbook

This section is the source of truth for installing this repo into a brand-new org.

- Human/AI readable guide: `docs/AI_INSTALL_PLAYBOOK.md`
- Machine-readable plan: `docs/install-plan.json`
- Plan execution script: `scripts/install-by-plan.sh`
- Plan validation script: `scripts/verify-install-plan.sh`

### 1) Prerequisites

- Salesforce CLI (`sf`) installed
- Authenticated target org alias (example: `new-demo-org`)
- Run from this repo root

Authenticate target org:

```bash
sf org login web --alias <target-org-alias>
sf org display --target-org <target-org-alias>
```

### 2) Install Order and Execution

Do not hardcode install order in prompts. Always read and execute `docs/install-plan.json`.

Validate plan:

```bash
./scripts/verify-install-plan.sh docs/install-plan.json
```

Dry-run install:

```bash
./scripts/install-by-plan.sh <target-org-alias> --dry-run
```

Production install:

```bash
./scripts/install-by-plan.sh <target-org-alias>
```

If target org already has customization on shared pages (`MFG_HOME_DISCRETE_MCO`, `MFG_ACCOUNT_DISCRETE_ALL`):

```bash
./scripts/install-by-plan.sh <target-org-alias> --sync-shared-pages
```

### 2.5) Optional Pack Installation (Manual)

Install optional custom packs outside baseline plan:

```bash
./scripts/deploy-feature.sh 240922-auto-create-opps <target-org-alias> --dry-run
./scripts/deploy-feature.sh 240922-auto-create-opps <target-org-alias>

./scripts/deploy-feature.sh sample-request <target-org-alias> --dry-run
./scripts/deploy-feature.sh sample-request <target-org-alias>

./scripts/deploy-feature.sh homepage-sync <target-org-alias> --dry-run
./scripts/deploy-feature.sh homepage-sync <target-org-alias>
```

### 3) Demo Setup Validation (Immediately After Step 1)

Open the setup page:

```bash
sf org open --target-org <target-org-alias> --path lightning/n/CM_Demo_Setup
```

Expected result:

- You can search/select an Account in `Demo Setup`
- Saving updates `CM_Is_Demo_Target__c`
- Saving updates `Industry`, `Website`, `Description`, and `CM_Supply_Scenario_Catalog__c`

### 3.5) One-Time HomePage Sync (260312 baseline to new org)

Use this when target org Home page must match `coryma-260312` (`MFG_HOME_DISCRETE_MCO`).

Dry-run:

```bash
sf project deploy start \
  --manifest manifest/features/homepage-sync.xml \
  --target-org <target-org-alias> \
  --dry-run \
  --wait 30
```

Apply:

```bash
sf project deploy start \
  --manifest manifest/features/homepage-sync.xml \
  --target-org <target-org-alias> \
  --wait 30
```

Post-check:

```bash
sf project retrieve start \
  --target-org <target-org-alias> \
  --metadata FlexiPage:MFG_HOME_DISCRETE_MCO \
  --output-dir /tmp/home-verify
diff -u force-app/main/default/flexipages/MFG_HOME_DISCRETE_MCO.flexipage-meta.xml \
  /tmp/home-verify/flexipages/MFG_HOME_DISCRETE_MCO.flexipage-meta.xml
```

### 4) One-Shot Install (Optional)

If you want everything in one deployment instead of modular order:

```bash
sf project deploy start \
  --source-dir force-app \
  --target-org <target-org-alias> \
  --wait 60
```

### 5) AI Execution Notes

- Always install `demo-setup` first before any feature that depends on active demo target context.
- Always install `Meeting Transcript Simulation` before using `QBR Meeting Follow-up`.
- Follow the exact module order in `docs/install-plan.json` unless a human explicitly changes it.
- If a step fails, stop and report the failing module name plus CLI error output; do not skip ahead.
- Optional packs (`240922-auto-create-opps`, `sample-request`, `homepage-sync`) are manual and not part of baseline `install-plan`.
- Deploying `FlexiPage` metadata is page-level overwrite behavior; if repo `Home`/`Account` pages are older than org, deployment can remove newer custom components.
- Sync rule for shared pages (`MFG_HOME_DISCRETE_MCO`, `MFG_ACCOUNT_DISCRETE_ALL`): retrieve latest from org first, then commit, then deploy.

## Org Verification (2026-03-23)

- `MFG_HOME_DISCRETE_MCO` includes `cmActivityScorecard` (Home page).
- `MFG_ACCOUNT_DISCRETE_ALL` includes `cmActivityScorecard` (Account record page).
- `MFG_Sales_Console` maps `standard-home` to `MFG_HOME_DISCRETE_MCO` and `Account` view to `MFG_ACCOUNT_DISCRETE_ALL`.

## Repo Rules

- Treat org snapshot sync commits as baseline updates.
- Keep this repo focused on demo-ready assets.
- Do not commit auth files, temp files, or retrieve ZIP outputs.

## Common Commands

Retrieve one feature pack:

```bash
./scripts/retrieve-feature.sh demo-setup <target-org-alias>
./scripts/retrieve-feature.sh lead-ai-scoring <target-org-alias>
./scripts/retrieve-feature.sh qbr-preparation <target-org-alias>
./scripts/retrieve-feature.sh 240922-auto-create-opps <target-org-alias>
./scripts/retrieve-feature.sh sample-request <target-org-alias>
```

Deploy one feature pack:

```bash
./scripts/deploy-feature.sh demo-setup <target-org-alias>
./scripts/deploy-feature.sh lead-ai-scoring <target-org-alias>
./scripts/deploy-feature.sh qbr-preparation <target-org-alias>
./scripts/deploy-feature.sh 240922-auto-create-opps <target-org-alias>
./scripts/deploy-feature.sh sample-request <target-org-alias>
```

Install by plan:

```bash
./scripts/verify-install-plan.sh docs/install-plan.json
./scripts/install-by-plan.sh <target-org-alias> --dry-run
./scripts/install-by-plan.sh <target-org-alias>
```
