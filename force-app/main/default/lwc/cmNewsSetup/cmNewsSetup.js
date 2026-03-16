import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchAccounts from '@salesforce/apex/CMNewsSetupController.searchAccounts';
import saveQueryConfigs from '@salesforce/apex/CMNewsSetupController.saveQueryConfigs';
import generateNews from '@salesforce/apex/CMNewsSetupController.generateNews';
import testNewsQuery from '@salesforce/apex/CMNewsSetupController.testNewsQuery';

const API_OPTIONS = [
    { label: 'Google News RSS', value: 'GOOGLE_NEWS_RSS' },
    { label: 'GDELT', value: 'GDELT' },
    { label: 'NEWS API', value: 'NEWS_API' },
    { label: 'GNews API', value: 'GNEWS_API' }
];

const TEST_LANGUAGE_OPTIONS = [
    { label: 'Any', value: 'ANY' },
    { label: 'English', value: 'ENGLISH' },
    { label: 'Chinese', value: 'CHINESE' },
    { label: 'Japanese', value: 'JAPANESE' }
];

const GENERATE_LANGUAGE_OPTIONS = [
    { label: 'Auto', value: 'ANY' },
    { label: 'Traditional Chinese (Taiwan)', value: 'CHINESE' },
    { label: 'English (US)', value: 'ENGLISH' },
    { label: 'Japanese (JP)', value: 'JAPANESE' }
];

const ACCOUNT_COLUMNS = [
    {
        label: 'Account',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: {
            label: { fieldName: 'name' },
            target: '_blank'
        }
    },
    {
        label: 'Account News Query',
        fieldName: 'accountNewsQueryInput',
        type: 'text',
        editable: true
    },
    {
        label: 'Related News Query',
        fieldName: 'relatedNewsQueryInput',
        type: 'text',
        editable: true
    },
    { label: 'Has Account News', fieldName: 'hasNewsLabel' },
    { label: 'Has Related News', fieldName: 'hasRelatedNewsLabel' },
    { label: 'Last Modified', fieldName: 'lastModifiedLabel' }
];

const TEST_COLUMNS = [
    { label: 'Title', fieldName: 'title' },
    {
        label: 'URL',
        fieldName: 'url',
        type: 'url',
        typeAttributes: { label: { fieldName: 'url' }, target: '_blank' }
    },
    { label: 'Date', fieldName: 'publishedDate' }
];

export default class CmNewsSetup extends LightningElement {
    accountColumns = ACCOUNT_COLUMNS;
    testColumns = TEST_COLUMNS;
    apiOptions = API_OPTIONS;
    testLanguageOptions = TEST_LANGUAGE_OPTIONS;
    generateLanguageOptions = GENERATE_LANGUAGE_OPTIONS;

    accounts = [];
    draftValues = [];
    selectedAccountIds = [];
    searchKey = '';
    isSearching = false;
    isSavingQueries = false;

    generateApiProvider = 'GOOGLE_NEWS_RSS';
    generateLanguage = 'ANY';
    generateApiAuth = '';
    isGenerating = false;

    testQuery = '';
    testLanguage = 'ANY';
    testApiProvider = 'GOOGLE_NEWS_RSS';
    testApiAuth = '';
    isTesting = false;
    testRows = [];
    rawPayload = '';

    _searchTimer;

    connectedCallback() {
        this.runSearch('');
    }

    get selectedCountLabel() {
        return `${this.selectedAccountIds.length} selected`;
    }

    get hasTestRows() {
        return this.testRows.length > 0;
    }

    get isGenerateAuthRequired() {
        return this.generateApiProvider === 'NEWS_API' || this.generateApiProvider === 'GNEWS_API';
    }

    get isTestAuthRequired() {
        return this.testApiProvider === 'NEWS_API' || this.testApiProvider === 'GNEWS_API';
    }

    get disableGenerateSelectedButton() {
        return (
            this.isGenerating ||
            this.selectedAccountIds.length === 0 ||
            this.isSavingQueries ||
            (this.isGenerateAuthRequired && !this.generateApiAuth?.trim())
        );
    }

    get disableGenerateAllButton() {
        return (
            this.isGenerating ||
            this.accounts.length === 0 ||
            this.isSavingQueries ||
            (this.isGenerateAuthRequired && !this.generateApiAuth?.trim())
        );
    }

    get disableTestButton() {
        return this.isTesting || !this.testQuery?.trim() || (this.isTestAuthRequired && !this.testApiAuth?.trim());
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value;
        window.clearTimeout(this._searchTimer);
        this._searchTimer = window.setTimeout(() => this.runSearch(this.searchKey), 250);
    }

    async runSearch(searchTerm) {
        this.isSearching = true;
        try {
            const rows = await searchAccounts({ searchTerm });
            this.accounts = (rows || []).map((row) => this.decorateAccount(row));
            this.draftValues = [];
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
            accountNewsQueryInput: row.accountNewsQuery || row.name || '',
            relatedNewsQueryInput: row.relatedNewsQuery || '',
            hasNewsLabel: row.hasNews ? 'Yes' : 'No',
            hasRelatedNewsLabel: row.hasRelatedNews ? 'Yes' : 'No',
            lastModifiedLabel: row.lastModifiedDate ? new Date(row.lastModifiedDate).toLocaleString() : ''
        };
    }

    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows || [];
        this.selectedAccountIds = selectedRows.map((row) => row.id);
    }

    handleCellChange(event) {
        this.mergeDraftValues(event.detail.draftValues || []);
    }

    async handleInlineSave(event) {
        this.mergeDraftValues(event.detail.draftValues || []);
        await this.saveDraftValues();
    }

    mergeDraftValues(newDrafts) {
        const draftById = new Map();
        [...this.draftValues, ...newDrafts].forEach((draft) => {
            if (!draft?.id) {
                return;
            }
            const existing = draftById.get(draft.id) || { id: draft.id };
            draftById.set(draft.id, { ...existing, ...draft });
        });
        this.draftValues = Array.from(draftById.values());
    }

    async flushInlineEditingState() {
        const active = this.template.activeElement || document.activeElement;
        if (active && typeof active.blur === 'function') {
            active.blur();
        }
        await Promise.resolve();
        await new Promise((resolve) => window.setTimeout(resolve, 100));
        const datatable = this.template.querySelector('lightning-datatable');
        if (datatable?.draftValues?.length) {
            this.mergeDraftValues(datatable.draftValues);
        }
    }

    async saveDraftValues(accountIdsFilter = null) {
        await this.flushInlineEditingState();

        if (this.draftValues.length === 0) {
            return true;
        }

        const rowById = new Map((this.accounts || []).map((row) => [row.id, row]));
        const filterSet = Array.isArray(accountIdsFilter) ? new Set(accountIdsFilter.filter(Boolean)) : null;
        const configs = this.draftValues
            .filter((draft) => !!draft?.id)
            .filter((draft) => !filterSet || filterSet.has(draft.id))
            .map((draft) => {
                const current = rowById.get(draft.id) || {};
                return {
                    accountId: draft.id,
                    accountNewsQuery:
                        draft.accountNewsQueryInput !== undefined
                            ? draft.accountNewsQueryInput
                            : current.accountNewsQueryInput,
                    relatedNewsQuery:
                        draft.relatedNewsQueryInput !== undefined
                            ? draft.relatedNewsQueryInput
                            : current.relatedNewsQueryInput
                };
            });

        if (configs.length === 0) {
            return true;
        }

        this.isSavingQueries = true;
        try {
            const savedItems = await saveQueryConfigs({
                configsJson: JSON.stringify(configs)
            });
            const updatedIds = this.applySavedQueryConfigs(savedItems);
            this.clearSavedDraftValues(updatedIds.length > 0 ? updatedIds : configs.map((item) => item.accountId));
            this.showToast('Saved', 'News query changes saved.', 'success');
            return true;
        } catch (error) {
            this.showToast('Save failed', this.reduceError(error), 'error');
            return false;
        } finally {
            this.isSavingQueries = false;
        }
    }

    applySavedQueryConfigs(savedItems) {
        const byId = new Map();
        (savedItems || []).forEach((item) => {
            if (item?.accountId) {
                byId.set(item.accountId, item);
            }
        });
        if (byId.size === 0) {
            return [];
        }

        this.accounts = (this.accounts || []).map((row) => {
            const saved = byId.get(row.id);
            if (!saved) {
                return row;
            }

            const accountNewsQuery = saved.accountNewsQuery || '';
            const relatedNewsQuery = saved.relatedNewsQuery || '';
            const hasNews = !!saved.hasNews;
            const hasRelatedNews = !!saved.hasRelatedNews;
            const lastModifiedDate = saved.lastModifiedDate || row.lastModifiedDate;

            return {
                ...row,
                accountNewsQuery,
                relatedNewsQuery,
                accountNewsQueryInput: accountNewsQuery || row.name || '',
                relatedNewsQueryInput: relatedNewsQuery,
                hasNews,
                hasRelatedNews,
                hasNewsLabel: hasNews ? 'Yes' : 'No',
                hasRelatedNewsLabel: hasRelatedNews ? 'Yes' : 'No',
                lastModifiedDate,
                lastModifiedLabel: lastModifiedDate ? new Date(lastModifiedDate).toLocaleString() : ''
            };
        });

        return Array.from(byId.keys());
    }

    clearSavedDraftValues(accountIds) {
        const idSet = new Set((accountIds || []).filter(Boolean));
        if (idSet.size === 0) {
            return;
        }
        this.draftValues = (this.draftValues || []).filter((draft) => !idSet.has(draft.id));
    }

    handleGenerateApiProviderChange(event) {
        this.generateApiProvider = event.detail.value;
    }

    handleGenerateApiAuthChange(event) {
        this.generateApiAuth = event.detail.value;
    }

    handleGenerateLanguageChange(event) {
        this.generateLanguage = event.detail.value;
    }

    async handleGenerateSelected() {
        await this.generateForAccounts(this.selectedAccountIds);
    }

    async handleGenerateAll() {
        await this.generateForAccounts(this.accounts.map((row) => row.id));
    }

    async generateForAccounts(accountIds) {
        const ids = (accountIds || []).filter(Boolean);
        if (ids.length === 0) {
            return;
        }

        const saved = await this.saveDraftValues(ids);
        if (!saved) {
            return;
        }

        this.isGenerating = true;
        try {
            const result = await generateNews({
                accountIds: ids,
                apiProvider: this.generateApiProvider,
                apiAuth: this.generateApiAuth,
                language: this.generateLanguage
            });

            await this.runSearch(this.searchKey);
            this.showToast(
                'News generation completed',
                `Updated Accounts: ${result.accountNewsSuccessCount}, Updated Related: ${result.relatedNewsSuccessCount}, Failed: ${result.failureCount}`,
                result.failureCount > 0 ? 'warning' : 'success'
            );
        } catch (error) {
            this.showToast('News generation failed', this.reduceError(error), 'error');
        } finally {
            this.isGenerating = false;
        }
    }

    handleTestQueryChange(event) {
        this.testQuery = event.detail.value;
    }

    handleTestLanguageChange(event) {
        this.testLanguage = event.detail.value;
    }

    handleTestApiProviderChange(event) {
        this.testApiProvider = event.detail.value;
    }

    handleTestApiAuthChange(event) {
        this.testApiAuth = event.detail.value;
    }

    async handleTestQuery() {
        this.isTesting = true;
        try {
            const result = await testNewsQuery({
                queryString: this.testQuery,
                language: this.testLanguage,
                apiProvider: this.testApiProvider,
                apiAuth: this.testApiAuth
            });
            this.rawPayload = result.rawPayload || '';
            this.testRows = (result.entries || []).map((item, index) => ({
                id: `${index}`,
                title: item.title,
                url: item.url,
                publishedDate: item.publishedDate
            }));
            this.showToast('API test completed', `Entries: ${result.entryCount}`, 'success');
        } catch (error) {
            this.rawPayload = '';
            this.testRows = [];
            this.showToast('API test failed', this.reduceError(error), 'error');
        } finally {
            this.isTesting = false;
        }
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
