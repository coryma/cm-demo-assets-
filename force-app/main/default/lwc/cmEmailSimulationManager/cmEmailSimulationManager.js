import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchAccounts from '@salesforce/apex/CMEmailSimulationController.searchAccounts';
import runSimulation from '@salesforce/apex/CMEmailSimulationController.runSimulation';

const ACCOUNT_COLUMNS = [
    { label: 'Account', fieldName: 'name' },
    { label: 'Industry', fieldName: 'industry' },
    { label: 'Type', fieldName: 'type' },
    { label: 'Email Activities', fieldName: 'emailActivityCount', type: 'number' }
];

const RESULT_COLUMNS = [
    { label: 'Account', fieldName: 'accountName' },
    { label: 'Deleted', fieldName: 'deletedCount', type: 'number' },
    { label: 'Created', fieldName: 'createdCount', type: 'number' },
    { label: 'Status', fieldName: 'status' },
    { label: 'Message', fieldName: 'message' }
];

export default class CmEmailSimulationManager extends LightningElement {
    accountColumns = ACCOUNT_COLUMNS;
    resultColumns = RESULT_COLUMNS;
    accounts = [];
    selectedAccountIds = [];
    results = [];

    searchKey = '';
    emailCount = 3;
    simulationDirection = 'MIXED';
    department = 'GSCM';
    startDate;
    endDate;
    confirmDelete = false;

    isLoadingAccounts = false;
    isRunning = false;

    connectedCallback() {
        const today = new Date();
        this.endDate = today.toISOString().slice(0, 10);
        const start = new Date(today);
        start.setDate(start.getDate() - 30);
        this.startDate = start.toISOString().slice(0, 10);
        this.loadAccounts('');
    }

    get hasResults() {
        return this.results.length > 0;
    }

    get directionOptions() {
        return [
            { label: 'Outbound only', value: 'OUTBOUND_ONLY' },
            { label: 'Inbound only', value: 'INBOUND_ONLY' },
            { label: 'Inbound + Outbound', value: 'MIXED' }
        ];
    }

    get disableRun() {
        return this.isRunning || this.selectedAccountIds.length === 0 || !this.confirmDelete;
    }

    async loadAccounts(searchTerm) {
        this.isLoadingAccounts = true;
        try {
            this.accounts = await searchAccounts({ searchTerm });
        } catch (error) {
            this.accounts = [];
            this.showToast('Load failed', this.reduceError(error), 'error');
        } finally {
            this.isLoadingAccounts = false;
        }
    }

    handleSearchChange(event) {
        this.searchKey = event.detail.value;
        this.loadAccounts(this.searchKey);
    }

    handleRowSelection(event) {
        const rows = event.detail.selectedRows || [];
        this.selectedAccountIds = rows.map((row) => row.id);
    }

    handleEmailCountChange(event) {
        const parsed = Number(event.detail.value);
        this.emailCount = Number.isNaN(parsed) ? null : parsed;
    }

    handleDirectionChange(event) {
        this.simulationDirection = event.detail.value;
    }

    handleDepartmentChange(event) {
        this.department = event.detail.value;
    }

    handleStartDateChange(event) {
        this.startDate = event.detail.value;
    }

    handleEndDateChange(event) {
        this.endDate = event.detail.value;
    }

    handleConfirmDeleteChange(event) {
        this.confirmDelete = event.detail.checked;
    }

    async handleRun() {
        if (!this.validateInputs()) {
            return;
        }

        this.isRunning = true;
        try {
            this.results = await runSimulation({
                accountIds: this.selectedAccountIds,
                emailCount: this.emailCount,
                simulationDirection: this.simulationDirection,
                department: this.department,
                startDate: this.startDate,
                endDate: this.endDate
            });
            await this.loadAccounts(this.searchKey);
            this.showToast('Completed', `Processed ${this.results.length} account(s).`, 'success');
        } catch (error) {
            this.showToast('Run failed', this.reduceError(error), 'error');
        } finally {
            this.isRunning = false;
        }
    }

    validateInputs() {
        if (this.selectedAccountIds.length === 0) {
            this.showToast('Missing account', 'Select at least one account.', 'error');
            return false;
        }
        if (!this.startDate || !this.endDate) {
            this.showToast('Missing date', 'Start date and end date are required.', 'error');
            return false;
        }
        if (this.endDate < this.startDate) {
            this.showToast('Invalid date range', 'End date cannot be earlier than start date.', 'error');
            return false;
        }
        if (!this.emailCount || this.emailCount < 1 || this.emailCount > 10) {
            this.showToast('Invalid count', 'Email count must be between 1 and 10.', 'error');
            return false;
        }
        if (!this.department || !this.department.trim()) {
            this.showToast('Missing department', 'Department is required.', 'error');
            return false;
        }
        if (!this.confirmDelete) {
            this.showToast('Confirmation required', 'You must confirm email activity deletion before running.', 'warning');
            return false;
        }
        return true;
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
