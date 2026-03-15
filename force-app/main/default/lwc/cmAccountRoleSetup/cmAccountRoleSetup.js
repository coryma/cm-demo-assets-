import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchAccounts from '@salesforce/apex/CMAccountRoleSetupController.searchAccounts';
import saveAccountRoles from '@salesforce/apex/CMAccountRoleSetupController.saveAccountRoles';

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
    { label: 'Roles', fieldName: 'roleDisplay' },
    { label: 'Type', fieldName: 'typeLabel' },
    { label: 'Industry', fieldName: 'industryLabel' }
];

const ROLE_OPTIONS = [
    { label: '客戶 (Customer)', value: 'Customer' },
    { label: '供應商 (Supplier)', value: 'Supplier' },
    { label: '合作夥伴 (Partner)', value: 'Partner' }
];

const ROLE_DISPLAY = {
    Customer: '客戶 / Customer',
    Supplier: '供應商 / Supplier',
    Partner: '合作夥伴 / Partner'
};

export default class CmAccountRoleSetup extends LightningElement {
    columns = COLUMNS;
    roleOptions = ROLE_OPTIONS;
    accounts = [];
    searchKey = '';
    selectedRows = [];
    selectedAccountIds = [];
    selectedRoles = [];
    isSearching = false;
    isSaving = false;

    _searchTimer;

    connectedCallback() {
        this.runSearch('');
    }

    get showEmptyState() {
        return !this.isSearching && this.accounts.length === 0;
    }

    get selectionLabel() {
        const count = this.selectedAccountIds.length;
        return `${count} 已選 / Selected`;
    }

    get disableApplyButton() {
        return this.isSaving || this.selectedAccountIds.length === 0 || this.selectedRoles.length === 0;
    }

    get disableClearButton() {
        return this.isSaving || this.selectedAccountIds.length === 0;
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value;
        window.clearTimeout(this._searchTimer);
        this._searchTimer = window.setTimeout(() => this.runSearch(this.searchKey), 250);
    }

    handleRowSelection(event) {
        const rows = event.detail.selectedRows || [];
        this.selectedAccountIds = rows.map((row) => row.id);
        this.selectedRows = [...this.selectedAccountIds];
    }

    handleRoleChange(event) {
        this.selectedRoles = [...(event.detail.value || [])];
    }

    async handleApplyRoles() {
        await this.persistRoles(this.selectedRoles, 'Roles updated');
    }

    async handleClearRoles() {
        this.selectedRoles = [];
        await this.persistRoles([], 'Roles cleared');
    }

    async persistRoles(roles, successTitle) {
        if (this.selectedAccountIds.length === 0) {
            return;
        }

        this.isSaving = true;
        try {
            await saveAccountRoles({
                accountIds: this.selectedAccountIds,
                roles
            });
            await this.runSearch(this.searchKey);
            this.selectedRows = [...this.selectedAccountIds];

            const accountCount = this.selectedAccountIds.length;
            this.showToast(
                successTitle,
                `${accountCount} account${accountCount === 1 ? '' : 's'} updated.`,
                'success'
            );
        } catch (error) {
            this.showToast('Unable to update roles', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async runSearch(searchTerm) {
        this.isSearching = true;
        try {
            const data = await searchAccounts({ searchTerm });
            this.accounts = (data || []).map((row) => this.decorateAccount(row));
            const visibleIds = new Set(this.accounts.map((row) => row.id));
            this.selectedAccountIds = this.selectedAccountIds.filter((id) => visibleIds.has(id));
            this.selectedRows = [...this.selectedAccountIds];
        } catch (error) {
            this.accounts = [];
            this.showToast('Search failed', this.reduceError(error), 'error');
        } finally {
            this.isSearching = false;
        }
    }

    decorateAccount(row) {
        const roleValues = row.roleValues || [];
        return {
            ...row,
            recordUrl: `/${row.id}`,
            roleDisplay: this.formatRoleDisplay(roleValues),
            typeLabel: row.type || 'Not set',
            industryLabel: row.industry || 'Not set'
        };
    }

    formatRoleDisplay(roleValues) {
        if (!roleValues.length) {
            return '未設定 / Not set';
        }

        return roleValues
            .map((value) => ROLE_DISPLAY[value] || value)
            .join('、');
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
