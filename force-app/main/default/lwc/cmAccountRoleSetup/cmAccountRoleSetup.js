import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import lang from '@salesforce/i18n/lang';
import locale from '@salesforce/i18n/locale';
import searchAccounts from '@salesforce/apex/CMAccountRoleSetupController.searchAccounts';
import saveAccountRoles from '@salesforce/apex/CMAccountRoleSetupController.saveAccountRoles';

const ROLE_VALUES = ['Customer', 'Supplier', 'Partner'];

const I18N = {
    zh: {
        cardTitle: '帳戶角色設定',
        intro: '可批次設定一或多個帳戶角色，支援客戶、供應商與合作夥伴。',
        chooseAccounts: '選擇帳戶',
        searchLabel: '搜尋帳戶',
        searchPlaceholder: '以帳戶名稱搜尋',
        searchingAccounts: '正在搜尋帳戶',
        noMatchingAccounts: '找不到符合條件的帳戶。',
        rolesToApply: '要套用的角色',
        accountRoles: '帳戶角色',
        availableRoles: '可選角色',
        selectedRoles: '已選角色',
        hintText: '套用後會覆寫所選帳戶的 CM Account Roles。',
        applyRoles: '套用角色',
        clearRoles: '清除角色',
        selectedCount: (count) => `${count} 已選`,
        notSet: '未設定',
        roleSeparator: '、',
        roleLabels: {
            Customer: '客戶',
            Supplier: '供應商',
            Partner: '合作夥伴'
        },
        roleDisplay: {
            Customer: '客戶',
            Supplier: '供應商',
            Partner: '合作夥伴'
        },
        columns: {
            account: '帳戶',
            roles: '角色',
            type: '類型',
            industry: '產業'
        },
        rolesUpdatedTitle: '角色已更新',
        rolesClearedTitle: '角色已清除',
        updatedCount: (count) => `已更新 ${count} 筆帳戶。`,
        updateFailedTitle: '無法更新角色',
        searchFailedTitle: '搜尋失敗',
        unknownError: '未知錯誤'
    },
    en: {
        cardTitle: 'Account Role Setup',
        intro: 'Set one or more Account identity roles in batch for demo use cases.',
        chooseAccounts: 'Choose Accounts',
        searchLabel: 'Search Account',
        searchPlaceholder: 'Search by account name',
        searchingAccounts: 'Searching accounts',
        noMatchingAccounts: 'No matching accounts found.',
        rolesToApply: 'Roles To Apply',
        accountRoles: 'Account roles',
        availableRoles: 'Available roles',
        selectedRoles: 'Selected roles',
        hintText: 'Apply overwrites CM Account Roles for all selected accounts.',
        applyRoles: 'Apply Roles',
        clearRoles: 'Clear Roles',
        selectedCount: (count) => `${count} selected`,
        notSet: 'Not set',
        roleSeparator: ', ',
        roleLabels: {
            Customer: 'Customer',
            Supplier: 'Supplier',
            Partner: 'Partner'
        },
        roleDisplay: {
            Customer: 'Customer',
            Supplier: 'Supplier',
            Partner: 'Partner'
        },
        columns: {
            account: 'Account',
            roles: 'Roles',
            type: 'Type',
            industry: 'Industry'
        },
        rolesUpdatedTitle: 'Roles updated',
        rolesClearedTitle: 'Roles cleared',
        updatedCount: (count) => `${count} account${count === 1 ? '' : 's'} updated.`,
        updateFailedTitle: 'Unable to update roles',
        searchFailedTitle: 'Search failed',
        unknownError: 'Unknown error'
    }
};

function isTraditionalChineseLocale() {
    const normalizedLang = (lang || '').toLowerCase().replace('_', '-');
    const normalizedLocale = (locale || '').toLowerCase().replace('_', '-');
    const code = normalizedLang || normalizedLocale;

    return (
        code.startsWith('zh-hant') ||
        code.startsWith('zh-tw') ||
        code.startsWith('zh-hk') ||
        code.startsWith('zh-mo')
    );
}

export default class CmAccountRoleSetup extends LightningElement {
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

    get i18n() {
        return isTraditionalChineseLocale() ? I18N.zh : I18N.en;
    }

    get columns() {
        const { columns } = this.i18n;
        return [
            {
                label: columns.account,
                fieldName: 'recordUrl',
                type: 'url',
                typeAttributes: {
                    label: { fieldName: 'name' },
                    target: '_blank'
                }
            },
            { label: columns.roles, fieldName: 'roleDisplay' },
            { label: columns.type, fieldName: 'typeLabel' },
            { label: columns.industry, fieldName: 'industryLabel' }
        ];
    }

    get roleOptions() {
        const { roleLabels } = this.i18n;
        return ROLE_VALUES.map((value) => ({
            label: roleLabels[value] || value,
            value
        }));
    }

    get showEmptyState() {
        return !this.isSearching && this.accounts.length === 0;
    }

    get selectionLabel() {
        return this.i18n.selectedCount(this.selectedAccountIds.length);
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
        await this.persistRoles(this.selectedRoles, this.i18n.rolesUpdatedTitle);
    }

    async handleClearRoles() {
        this.selectedRoles = [];
        await this.persistRoles([], this.i18n.rolesClearedTitle);
    }

    async persistRoles(roles, successTitle) {
        if (this.selectedAccountIds.length === 0) {
            return;
        }

        this.isSaving = true;
        try {
            const updatedRows = await saveAccountRoles({
                accountIds: this.selectedAccountIds,
                roles
            });
            this.applyUpdatedRows(updatedRows);
            this.selectedRows = [...this.selectedAccountIds];

            const accountCount = this.selectedAccountIds.length;
            this.showToast(successTitle, this.i18n.updatedCount(accountCount), 'success');
        } catch (error) {
            this.showToast(this.i18n.updateFailedTitle, this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    applyUpdatedRows(rows) {
        const updatesById = new Map((rows || []).map((row) => [row.id, this.decorateAccount(row)]));
        if (updatesById.size === 0) {
            return;
        }

        this.accounts = this.accounts.map((row) => updatesById.get(row.id) || row);
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
            this.showToast(this.i18n.searchFailedTitle, this.reduceError(error), 'error');
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
            typeLabel: row.type || this.i18n.notSet,
            industryLabel: row.industry || this.i18n.notSet
        };
    }

    formatRoleDisplay(roleValues) {
        if (!roleValues.length) {
            return this.i18n.notSet;
        }

        return roleValues
            .map((value) => this.i18n.roleDisplay[value] || value)
            .join(this.i18n.roleSeparator);
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || this.i18n.unknownError;
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