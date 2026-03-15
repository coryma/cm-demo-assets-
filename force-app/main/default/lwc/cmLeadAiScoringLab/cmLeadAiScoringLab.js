import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDemoTargetSummary from '@salesforce/apex/CM_LeadAIScoringDemoController.getDemoTargetSummary';
import searchLeads from '@salesforce/apex/CM_LeadAIScoringDemoController.searchLeads';
import generateDescriptionsAndScore from '@salesforce/apex/CM_LeadAIScoringDemoController.generateDescriptionsAndScore';

const MAX_GENERATION_COUNT = 10;
const QUALITY_TIERS = ['Very High', 'High', 'Medium', 'Low', 'Very Low'];

const LEAD_COLUMNS = [
    {
        label: 'Lead',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'name' }, target: '_blank' }
    },
    { label: 'Company', fieldName: 'company' },
    { label: 'Current Score', fieldName: 'aiScoreDisplay' },
    { label: 'Current Classification', fieldName: 'aiClassification' },
    { label: 'Description Preview', fieldName: 'descriptionPreview', wrapText: true }
];

const RESULT_COLUMNS = [
    {
        label: 'Lead',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'name' }, target: '_blank' }
    },
    { label: 'Quality Tier', fieldName: 'qualityTier' },
    { label: 'Score', fieldName: 'aiScoreDisplay' },
    { label: 'Classification', fieldName: 'aiClassification' },
    { label: 'Generated Description', fieldName: 'generatedDescriptionPreview', wrapText: true },
    { label: 'Reason', fieldName: 'aiReason', wrapText: true }
];

const QUALITY_TIER_OPTIONS = QUALITY_TIERS.map((tier) => ({
    label: tier,
    value: tier
}));

export default class CmLeadAiScoringLab extends LightningElement {
    leadColumns = LEAD_COLUMNS;
    resultColumns = RESULT_COLUMNS;
    qualityTierOptions = QUALITY_TIER_OPTIONS;

    leads = [];
    results = [];
    selectedLeadRows = [];
    selectedLeadIds = [];
    searchKey = '';
    isSearching = false;
    isGenerating = false;
    demoTarget;

    _searchTimer;

    connectedCallback() {
        this.loadDemoTarget();
        this.runSearch('');
    }

    get selectedCountLabel() {
        return `${this.selectedLeadIds.length} / ${MAX_GENERATION_COUNT} selected`;
    }

    get canGenerate() {
        return (
            this.selectedLeadRows.length > 0 &&
            this.selectedLeadRows.length <= MAX_GENERATION_COUNT &&
            this.selectedLeadRows.every((row) => Boolean(row.qualityTier)) &&
            !this.isGenerating
        );
    }

    get disableGenerateButton() {
        return !this.canGenerate;
    }

    get hasResults() {
        return this.results.length > 0;
    }

    get hasDemoTarget() {
        return Boolean(this.demoTarget);
    }

    get demoTargetStatus() {
        if (!this.demoTarget) {
            return 'Not configured';
        }
        return this.demoTarget.hasContext ? 'Ready' : 'Needs context fields';
    }

    get hasSelectedLeadPreview() {
        return this.selectedLeadRows.length > 0;
    }

    get selectedLeadPreview() {
        return this.selectedLeadRows.map((row) => ({
            ...row,
            id: row.recordId,
            company: row.company || 'Not set'
        }));
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value || '';
        window.clearTimeout(this._searchTimer);
        this._searchTimer = window.setTimeout(() => {
            this.runSearch(this.searchKey);
        }, 250);
    }

    handleRowSelection(event) {
        const rows = event.detail.selectedRows || [];
        const previousTierById = new Map(
            this.selectedLeadRows.map((row) => [row.recordId, row.qualityTier])
        );

        this.selectedLeadRows = rows
            .map((row, index) => this.normalizeSelectedRow(row, index, previousTierById))
            .filter((row) => Boolean(row?.recordId));
        this.selectedLeadIds = this.selectedLeadRows.map((row) => row.recordId);
    }

    handleQualityTierChange(event) {
        const leadId = event.target.dataset.id;
        const value = event.detail.value;
        this.selectedLeadRows = this.selectedLeadRows.map((row) =>
            row.recordId === leadId ? { ...row, qualityTier: value } : row
        );
    }

    defaultTierByIndex(index) {
        return QUALITY_TIERS[index % QUALITY_TIERS.length];
    }

    normalizeSelectedRow(row, index, previousTierById) {
        const rowId = this.resolveLeadId(row);
        return {
            recordId: rowId,
            name: row?.name || row?.Name,
            company: row?.company || row?.Company,
            qualityTier: previousTierById.get(rowId) || this.defaultTierByIndex(index)
        };
    }

    resolveLeadId(row) {
        const directId = row?.recordId || row?.id || row?.Id;
        if (directId) {
            return directId;
        }

        const recordUrl = row?.recordUrl || '';
        const match = recordUrl.match(/\/Lead\/([a-zA-Z0-9]{15,18})\//);
        if (match && match[1]) {
            return match[1];
        }

        if (recordUrl.startsWith('/') && recordUrl.length >= 16) {
            const possibleId = recordUrl.substring(1, 19);
            if (/^[a-zA-Z0-9]{15,18}$/.test(possibleId)) {
                return possibleId;
            }
        }

        return null;
    }

    syncSelectionFromDatatable() {
        const datatable = this.template.querySelector('lightning-datatable');
        if (!datatable) {
            return;
        }

        const selectedRows = datatable.getSelectedRows() || [];
        if (!selectedRows.length) {
            return;
        }

        const previousTierById = new Map(
            this.selectedLeadRows.map((row) => [row.recordId, row.qualityTier])
        );
        this.selectedLeadRows = selectedRows
            .map((row, index) => this.normalizeSelectedRow(row, index, previousTierById))
            .filter((row) => Boolean(row?.recordId));
        this.selectedLeadIds = this.selectedLeadRows.map((row) => row.recordId);
    }

    async handleGenerateClick() {
        this.syncSelectionFromDatatable();

        if (!this.selectedLeadRows.length) {
            this.showToast('Lead AI Scoring', 'Please select at least 1 Lead.', 'warning');
            return;
        }
        if (this.selectedLeadRows.length > MAX_GENERATION_COUNT) {
            this.showToast('Lead AI Scoring', 'You can generate up to 10 Leads at a time.', 'warning');
            return;
        }

        this.isGenerating = true;
        try {
            const leadInputs = this.selectedLeadRows.map((row) => ({
                leadId: row.recordId,
                id: row.recordId,
                qualityTier: row.qualityTier
            }));
            const leadIds = this.selectedLeadRows.map((row) => row.recordId);

            const payload = await generateDescriptionsAndScore({ leadInputs, leadIds });
            this.results = (payload || []).map((row) => this.decorateResult(row));
            await this.runSearch(this.searchKey);
            await this.loadDemoTarget();

            this.showToast(
                'Lead AI Scoring',
                `Generated ${this.results.length} descriptions and refreshed Lead AI scores.`,
                'success'
            );
        } catch (error) {
            this.showToast('Lead AI Scoring failed', this.reduceError(error), 'error');
        } finally {
            this.isGenerating = false;
        }
    }

    async runSearch(searchTerm) {
        this.isSearching = true;
        try {
            const rows = await searchLeads({ searchTerm });
            this.leads = (rows || []).map((row) => this.decorateLead(row));
        } catch (error) {
            this.leads = [];
            this.showToast('Lead search failed', this.reduceError(error), 'error');
        } finally {
            this.isSearching = false;
        }
    }

    async loadDemoTarget() {
        try {
            const data = await getDemoTargetSummary();
            this.demoTarget = data
                ? {
                      ...data,
                      recordUrl: `/${data.id}`
                  }
                : null;
        } catch (error) {
            this.demoTarget = null;
            this.showToast('Demo target unavailable', this.reduceError(error), 'error');
        }
    }

    decorateLead(row) {
        const recordId = this.resolveLeadId(row);
        return {
            ...row,
            recordId,
            aiClassification: row.aiClassification || '-',
            aiScoreDisplay: row.aiScore === null || row.aiScore === undefined ? '-' : `${row.aiScore}`,
            descriptionPreview: this.toPreview(row.description, 140)
        };
    }

    decorateResult(row) {
        const recordId = this.resolveLeadId(row);
        return {
            ...row,
            recordId,
            aiClassification: row.aiClassification || '-',
            aiReason: row.aiReason || '-',
            aiScoreDisplay: row.aiScore === null || row.aiScore === undefined ? '-' : `${row.aiScore}`,
            generatedDescriptionPreview: this.toPreview(row.generatedDescription, 220)
        };
    }

    toPreview(value, maxLength) {
        if (!value) {
            return '-';
        }
        if (value.length <= maxLength) {
            return value;
        }
        return `${value.slice(0, maxLength)}...`;
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unknown error';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}
