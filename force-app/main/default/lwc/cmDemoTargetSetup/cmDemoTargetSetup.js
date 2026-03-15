import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import ACCOUNT_OBJECT from '@salesforce/schema/Account';
import INDUSTRY_FIELD from '@salesforce/schema/Account.Industry';
import getActiveDemoTarget from '@salesforce/apex/CMDemoTargetSetupController.getActiveDemoTarget';
import searchAccounts from '@salesforce/apex/CMDemoTargetSetupController.searchAccounts';
import saveDemoTarget from '@salesforce/apex/CMDemoTargetSetupController.saveDemoTarget';

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
    { label: 'Status', fieldName: 'selectionStatus' }
];

export default class CmDemoTargetSetup extends NavigationMixin(LightningElement) {
    columns = COLUMNS;
    accounts = [];
    searchKey = '';
    selectedAccountId;
    selectedRows = [];
    activeTarget;
    editorAccount;
    industryOptions = [];
    isSearching = false;
    isSaving = false;

    _searchTimer;
    _wiredActiveTarget;

    @wire(getObjectInfo, { objectApiName: ACCOUNT_OBJECT })
    objectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$defaultRecordTypeId',
        fieldApiName: INDUSTRY_FIELD
    })
    wiredIndustryValues({ data, error }) {
        if (data) {
            this.industryOptions = data.values.map((item) => ({
                label: item.label,
                value: item.value
            }));
            this.accounts = this.accounts.map((row) => this.decorateAccount(row));
            if (this.activeTarget) {
                this.activeTarget = this.decorateAccount(this.activeTarget);
            }
            if (this.editorAccount) {
                this.editorAccount = this.decorateAccount(this.editorAccount);
            }
        } else if (error) {
            this.showToast('Industry options unavailable', this.reduceError(error), 'error');
        }
    }

    connectedCallback() {
        this.runSearch('');
    }

    @wire(getActiveDemoTarget)
    wiredActiveTarget(value) {
        this._wiredActiveTarget = value;
        const { data, error } = value;

        if (data) {
            this.activeTarget = this.decorateAccount(data);
            if (!this.editorAccount) {
                this.selectAccount(this.activeTarget);
            }
        } else if (error) {
            this.activeTarget = undefined;
            this.showToast('Demo target error', this.reduceError(error), 'error');
        }
    }

    get defaultRecordTypeId() {
        return this.objectInfo?.data?.defaultRecordTypeId;
    }

    get activeContextStatus() {
        if (!this.activeTarget) {
            return 'Not set';
        }
        return this.activeTarget.hasContext ? 'Active - Ready' : 'Active - Needs setup';
    }

    get editorContextStatus() {
        if (!this.editorAccount) {
            return 'Select an account';
        }
        return this.editorAccount.hasContext ? 'Ready' : 'Needs setup';
    }

    get disableSaveButton() {
        return !this.editorAccount?.id || this.isSaving;
    }

    get disableOpenButton() {
        return !this.editorAccount?.id;
    }

    get showEmptyState() {
        return !this.isSearching && this.accounts.length === 0;
    }

    get hasEditorAccount() {
        return Boolean(this.editorAccount);
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value;
        window.clearTimeout(this._searchTimer);
        this._searchTimer = window.setTimeout(() => this.runSearch(this.searchKey), 250);
    }

    handleRowSelection(event) {
        const rows = event.detail.selectedRows || [];
        if (rows.length) {
            this.selectAccount(rows[0]);
        } else {
            this.selectedAccountId = null;
            this.selectedRows = [];
            this.editorAccount = null;
        }
    }

    handleFieldChange(event) {
        const fieldName = event.target.dataset.field;
        this.editorAccount = this.decorateAccount({
            ...this.editorAccount,
            [fieldName]: event.detail?.value ?? event.target.value
        });
    }

    async handleSaveDemoTarget() {
        if (!this.editorAccount?.id) {
            return;
        }

        this.isSaving = true;
        try {
            const result = await saveDemoTarget({
                accountId: this.editorAccount.id,
                industry: this.editorAccount.industry,
                website: this.editorAccount.website,
                description: this.editorAccount.description
            });
            const decorated = this.decorateAccount(result);
            this.activeTarget = decorated;
            this.selectAccount(decorated);
            await refreshApex(this._wiredActiveTarget);
            await this.runSearch(this.searchKey);

            const variant = result.missingContext ? 'warning' : 'success';
            const message = result.missingContext
                ? `Demo target updated. Complete the Account fields: ${result.missingContext}.`
                : 'Demo target updated and activated.';

            this.showToast('Demo target saved', message, variant);
        } catch (error) {
            this.showToast('Unable to save demo target', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleOpenSelected() {
        if (!this.editorAccount?.id) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.editorAccount.id,
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
            if (this.selectedAccountId) {
                this.selectedRows = [this.selectedAccountId];
            }
        } catch (error) {
            this.accounts = [];
            this.showToast('Search failed', this.reduceError(error), 'error');
        } finally {
            this.isSearching = false;
        }
    }

    selectAccount(row) {
        const decorated = this.decorateAccount(row);
        this.selectedAccountId = decorated.id;
        this.selectedRows = [decorated.id];
        this.editorAccount = decorated;
    }

    decorateAccount(row) {
        const missingContext = this.getMissingContext(row);
        return {
            ...row,
            industry: row.industry || '',
            website: row.website || '',
            description: row.description || '',
            recordUrl: `/${row.id}`,
            industryLabel: row.industry ? this.getIndustryLabel(row.industry) : 'Not set',
            typeLabel: row.type || 'Not set',
            hasContext: missingContext.length === 0,
            missingContext: missingContext.join(', '),
            contextStatus: missingContext.length === 0 ? 'Ready' : 'Needs setup',
            selectionStatus: row.isDemoTarget ? 'Active' : missingContext.length === 0 ? 'Ready' : 'Needs setup'
        };
    }

    getIndustryLabel(value) {
        const match = this.industryOptions.find((item) => item.value === value);
        return match?.label || value;
    }

    getMissingContext(row) {
        const missing = [];
        if (!row?.industry) {
            missing.push('Industry');
        }
        if (!row?.website) {
            missing.push('Website');
        }
        if (!row?.description) {
            missing.push('Description');
        }
        return missing;
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
