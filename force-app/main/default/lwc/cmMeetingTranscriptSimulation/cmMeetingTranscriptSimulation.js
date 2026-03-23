import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFocusContext from '@salesforce/apex/CMMeetingTranscriptSimulationController.getFocusContext';
import searchAccounts from '@salesforce/apex/CMMeetingTranscriptSimulationController.searchAccounts';
import startSimulation from '@salesforce/apex/CMMeetingTranscriptSimulationController.startSimulation';
import getBatchStatus from '@salesforce/apex/CMMeetingTranscriptSimulationController.getBatchStatus';

const SEARCH_DEBOUNCE_MS = 250;
const SEARCH_LIMIT = 100;
const STATUS_POLL_INTERVAL_MS = 2000;

const ACCOUNT_COLUMNS = [
    { label: 'Account', fieldName: 'name' },
    {
        label: 'Has Meeting Record',
        fieldName: 'hasMeetingRecord',
        type: 'boolean'
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
    _statusTimer;

    connectedCallback() {
        this.initialize();
    }

    disconnectedCallback() {
        if (this._searchTimer) {
            clearTimeout(this._searchTimer);
        }
        this.clearStatusPoll();
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
        this.clearStatusPoll();
        try {
            const started = await startSimulation({ accountIds: this.selectedAccountIds });
            this.batchId = started.batchId || '';
            this.results = [];

            const count = started?.createdCount || 0;
            this.showToast('Queued', `Queued ${count} account(s) for background generation.`, 'info');
            await this.pollBatchStatus();
        } catch (error) {
            this.showToast('Generation failed', this.reduceError(error), 'error');
            this.isGenerating = false;
            this.clearStatusPoll();
        }
    }

    async pollBatchStatus() {
        if (!this.batchId) {
            this.isGenerating = false;
            return;
        }

        try {
            const status = await getBatchStatus({ batchId: this.batchId });
            this.results = (status?.rows || []).map((row) => ({ ...row }));

            if (status?.done) {
                this.isGenerating = false;
                this.clearStatusPoll();
                await this.loadAccounts(this.searchKey);
                const completedCount = status?.completedCount || 0;
                const failedCount = status?.failedCount || 0;
                this.showToast(
                    'Completed',
                    `Completed ${completedCount} account(s), failed ${failedCount} account(s).`,
                    failedCount > 0 ? 'warning' : 'success'
                );
                return;
            }

            this.scheduleStatusPoll();
        } catch (error) {
            this.isGenerating = false;
            this.clearStatusPoll();
            this.showToast('Status check failed', this.reduceError(error), 'error');
        }
    }

    scheduleStatusPoll() {
        this.clearStatusPoll();
        this._statusTimer = setTimeout(() => {
            this.pollBatchStatus();
        }, STATUS_POLL_INTERVAL_MS);
    }

    clearStatusPoll() {
        if (this._statusTimer) {
            clearTimeout(this._statusTimer);
            this._statusTimer = null;
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