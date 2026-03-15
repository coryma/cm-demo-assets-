import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDemoTargetSummary from '@salesforce/apex/CM_LeadAIScoringDemoController.getDemoTargetSummary';
import searchLeads from '@salesforce/apex/CM_LeadAIScoringDemoController.searchLeads';
import generateDescriptionsAndScore from '@salesforce/apex/CM_LeadAIScoringDemoController.generateDescriptionsAndScore';

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

const QUALITY_TIERS = ['Very High', 'High', 'Medium', 'Low', 'Very Low'];

export default class CmLeadAiScoringLab extends LightningElement {
    leadColumns = LEAD_COLUMNS;
    resultColumns = RESULT_COLUMNS;
    leads = [];
    results = [];
    selectedLeadIds = [];
    selectedLeadRows = [];
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
        return `${this.selectedLeadIds.length} / 5 selected`;
    }

    get canGenerate() {
        return this.selectedLeadIds.length === 5 && !this.isGenerating;
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

    get selectedLeadPreview() {
        return this.selectedLeadRows.map((row, index) => ({
            id: row.id,
            name: row.name || row.id,
            company: row.company || 'Not set',
            qualityTier: QUALITY_TIERS[index] || '-'
        }));
    }

    get hasSelectedLeadPreview() {
        return this.selectedLeadPreview.length > 0;
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
        this.selectedLeadRows = rows.map((row) => ({
            id: row.id,
            name: row.name,
            company: row.company
        }));
        this.selectedLeadIds = this.selectedLeadRows.map((row) => row.id);
    }

    async handleGenerateClick() {
        if (this.selectedLeadIds.length !== 5) {
            this.showToast('Lead AI Scoring', 'Please select exactly 5 Leads.', 'warning');
            return;
        }

        this.isGenerating = true;
        try {
            const payload = await generateDescriptionsAndScore({ leadIds: this.selectedLeadIds });
            this.results = (payload || []).map((row) => this.decorateResult(row));
            await this.runSearch(this.searchKey);
            await this.loadDemoTarget();
            this.showToast(
                'Lead AI Scoring',
                'Generated 5 quality-tier descriptions and refreshed Lead AI scores.',
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
        return {
            ...row,
            aiClassification: row.aiClassification || '-',
            aiScoreDisplay: row.aiScore === null || row.aiScore === undefined ? '-' : `${row.aiScore}`,
            descriptionPreview: this.toPreview(row.description, 140)
        };
    }

    decorateResult(row) {
        return {
            ...row,
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
