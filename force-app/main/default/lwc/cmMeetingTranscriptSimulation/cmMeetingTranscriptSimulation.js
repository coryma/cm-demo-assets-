import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFocusContext from '@salesforce/apex/CMMeetingTranscriptSimulationController.getFocusContext';
import searchAccounts from '@salesforce/apex/CMMeetingTranscriptSimulationController.searchAccounts';
import startSimulation from '@salesforce/apex/CMMeetingTranscriptSimulationController.startSimulation';
import getBatchStatus from '@salesforce/apex/CMMeetingTranscriptSimulationController.getBatchStatus';

const SEARCH_DEBOUNCE_MS = 250;
const SEARCH_LIMIT = 100;

const ACCOUNT_COLUMNS = [
    { label: 'Account', fieldName: 'name' },
    { label: 'Industry', fieldName: 'industry' },
    { label: 'Type', fieldName: 'type' },
    {
        label: 'Last Modified',
        fieldName: 'lastModifiedDate',
        type: 'date',
        typeAttributes: {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit'
        }
    }
];

const RESULT_COLUMNS = [
    { label: 'Account', fieldName: 'accountName' },
    { label: 'Status', fieldName: 'status' },
    {
        label: 'Generated At',
        fieldName: 'generatedAt',
        type: 'date',
        typeAttributes: {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        }
    },
    { label: 'Summary', fieldName: 'summary', wrapText: true },
    {
        label: 'Record',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: {
            label: 'Open',
            target: '_blank'
        }
    }
];

export default class CmMeetingTranscriptSimulation extends LightningElement {
    accountColumns = ACCOUNT_COLUMNS;
    resultColumns = RESULT_COLUMNS;

    focusCompanyId;
    focusCompanyName = '';

    searchKey = '';
    accounts = [];
    selectedAccountIds = [];

    isLoadingContext = true;
    isLoadingAccounts = false;
    isGenerating = false;

    batchId = '';
    results = [];

    _searchTimer;

    connectedCallback() {
        this.initialize();
    }

    disconnectedCallback() {
        if (this._searchTimer) {
            clearTimeout(this._searchTimer);
        }
    }

    get hasFocusCompany() {
        return !!this.focusCompanyId;
    }

    get disableGenerate() {
        return (
            this.isLoadingContext ||
            this.isLoadingAccounts ||
            this.isGenerating ||
            !this.hasFocusCompany ||
            this.selectedAccountIds.length === 0
        );
    }

    get showNoAccounts() {
        return this.hasFocusCompany && !this.isLoadingAccounts && this.accounts.length === 0;
    }

    get hasResults() {
        return this.results.length > 0;
    }

    get selectedCountLabel() {
        return `${this.selectedAccountIds.length} account(s) selected`;
    }

    async initialize() {
        await this.loadFocusContext();
        await this.loadAccounts('');
    }

    async loadFocusContext() {
        this.isLoadingContext = true;
        try {
            const payload = await getFocusContext();
            this.focusCompanyId = payload?.focusCompanyId;
            this.focusCompanyName = payload?.focusCompanyName || '';
        } catch (error) {
            this.focusCompanyId = null;
            this.focusCompanyName = '';
            this.showToast('Load failed', this.reduceError(error), 'error');
        } finally {
            this.isLoadingContext = false;
        }
    }

    async loadAccounts(searchTerm) {
        if (!this.hasFocusCompany) {
            this.accounts = [];
            this.selectedAccountIds = [];
            return;
        }

        this.isLoadingAccounts = true;
        try {
            const rows = await searchAccounts({
                searchTerm,
                limitSize: SEARCH_LIMIT
            });
            this.accounts = rows || [];
            const availableIds = new Set(this.accounts.map((row) => row.id));
            this.selectedAccountIds = this.selectedAccountIds.filter((id) => availableIds.has(id));
        } catch (error) {
            this.accounts = [];
            this.selectedAccountIds = [];
            this.showToast('Load failed', this.reduceError(error), 'error');
        } finally {
            this.isLoadingAccounts = false;
        }
    }

    handleSearchChange(event) {
        this.searchKey = event.detail.value || '';
        if (this._searchTimer) {
            clearTimeout(this._searchTimer);
        }
        this._searchTimer = setTimeout(() => {
            this.loadAccounts(this.searchKey);
        }, SEARCH_DEBOUNCE_MS);
    }

    handleRowSelection(event) {
        const rows = event.detail.selectedRows || [];
        this.selectedAccountIds = rows.map((row) => row.id);
    }

    async handleGenerate() {
        if (this.disableGenerate) {
            return;
        }

        this.isGenerating = true;
        try {
            const started = await startSimulation({ accountIds: this.selectedAccountIds });
            this.batchId = started.batchId || '';

            const status = await getBatchStatus({ batchId: this.batchId });
            this.results = (status?.rows || []).map((row) => ({ ...row }));

            const count = started?.createdCount || 0;
            this.showToast('Completed', `Generated transcript for ${count} account(s).`, 'success');
        } catch (error) {
            this.showToast('Generation failed', this.reduceError(error), 'error');
        } finally {
            this.isGenerating = false;
        }
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unknown error';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
