import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getActiveDemoTarget from '@salesforce/apex/CMDemoTargetSetupController.getActiveDemoTarget';
import searchAccounts from '@salesforce/apex/CMDemoTargetSetupController.searchAccounts';
import setActiveDemoTarget from '@salesforce/apex/CMDemoTargetSetupController.setActiveDemoTarget';

const COLUMNS = [
    {
        label: 'Account',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: {
            label: { fieldName: 'name' },
            target: '_blank'
        }
    },
    { label: 'Industry', fieldName: 'industryLabel' },
    { label: 'Type', fieldName: 'typeLabel' },
    { label: 'Context', fieldName: 'contextStatus' }
];

export default class CmDemoTargetSetup extends NavigationMixin(LightningElement) {
    columns = COLUMNS;
    accounts = [];
    searchKey = '';
    selectedAccountId;
    selectedRows = [];
    activeTarget;
    isSearching = false;
    isSaving = false;

    _searchTimer;
    _wiredActiveTarget;

    connectedCallback() {
        this.runSearch('');
    }

    @wire(getActiveDemoTarget)
    wiredActiveTarget(value) {
        this._wiredActiveTarget = value;
        const { data, error } = value;

        if (data) {
            this.activeTarget = this.decorateAccount(data);
        } else if (error) {
            this.activeTarget = undefined;
            this.showToast('Demo target error', this.reduceError(error), 'error');
        }
    }

    get activeContextStatus() {
        return this.activeTarget?.contextStatus || 'Needs setup';
    }

    get disableSetButton() {
        return !this.selectedAccountId || this.isSaving;
    }

    get disableOpenButton() {
        return !this.selectedAccountId;
    }

    get showEmptyState() {
        return !this.isSearching && this.accounts.length === 0;
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value;
        window.clearTimeout(this._searchTimer);
        this._searchTimer = window.setTimeout(() => this.runSearch(this.searchKey), 250);
    }

    handleRowSelection(event) {
        const rows = event.detail.selectedRows || [];
        this.selectedAccountId = rows.length ? rows[0].id : null;
        this.selectedRows = this.selectedAccountId ? [this.selectedAccountId] : [];
    }

    async handleSetActive() {
        if (!this.selectedAccountId) {
            return;
        }

        this.isSaving = true;
        try {
            const result = await setActiveDemoTarget({ accountId: this.selectedAccountId });
            this.activeTarget = this.decorateAccount(result);
            await refreshApex(this._wiredActiveTarget);
            await this.runSearch(this.searchKey);

            const variant = result.missingContext ? 'warning' : 'success';
            const message = result.missingContext
                ? `Demo target updated. Complete the Account fields: ${result.missingContext}.`
                : 'Demo target updated.';

            this.showToast('Demo target saved', message, variant);
        } catch (error) {
            this.showToast('Unable to set demo target', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleOpenSelected() {
        if (!this.selectedAccountId) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.selectedAccountId,
                objectApiName: 'Account',
                actionName: 'view'
            }
        });
    }

    async runSearch(searchTerm) {
        this.isSearching = true;
        try {
            const data = await searchAccounts({ searchTerm });
            this.accounts = (data || []).map((row) => this.decorateAccount(row));
        } catch (error) {
            this.accounts = [];
            this.showToast('Search failed', this.reduceError(error), 'error');
        } finally {
            this.isSearching = false;
        }
    }

    decorateAccount(row) {
        return {
            ...row,
            recordUrl: `/${row.id}`,
            industryLabel: row.industry || 'Not set',
            typeLabel: row.type || 'Not set',
            contextStatus: row.hasContext ? 'Ready' : 'Needs setup'
        };
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
