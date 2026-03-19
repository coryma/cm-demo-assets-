import { LightningElement, api, wire } from 'lwc';
import LANG from '@salesforce/i18n/lang';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import getAccountContacts from '@salesforce/apex/CM_QBRFlowService.getAccountContacts';

export default class CmQbrContactPicker extends LightningElement {
    @api accountId;

    _selectedContactIds;
    hasInitializedSelection = false;

    rows = [];
    selectedRowIds = [];

    get isChinese() {
        return (LANG || '').toLowerCase().startsWith('zh');
    }

    get columns() {
        return [
            { label: this.isChinese ? '姓名' : 'Name', fieldName: 'name', type: 'text' },
            { label: this.isChinese ? '職稱' : 'Title', fieldName: 'title', type: 'text' },
            { label: this.isChinese ? '電子郵件' : 'Email', fieldName: 'email', type: 'email' },
            { label: this.isChinese ? '背景摘要' : 'Briefing Note', fieldName: 'description', type: 'text', wrapText: true }
        ];
    }

    @api
    get selectedContactIds() {
        return this._selectedContactIds;
    }

    set selectedContactIds(value) {
        this._selectedContactIds = value;
        const selectedIds = this.parseIds(value);
        if (this.rows.length) {
            if (!this.hasInitializedSelection && !selectedIds.length) {
                this.selectedRowIds = this.rows.map((row) => row.contactId);
                this.hasInitializedSelection = true;
            } else {
                this.selectedRowIds = selectedIds;
            }
            this.publishSelection();
        }
    }

    @wire(getAccountContacts, { accountId: '$accountId' })
    wiredContacts({ data }) {
        if (data) {
            this.rows = data.map((item) => ({
                contactId: item.contactId,
                name: item.name,
                title: item.title || '',
                email: item.email || '',
                description: this.normalizeDescription(item.description) || (this.isChinese ? '尚未建立聯絡人背景摘要。' : 'No stored contact briefing note.')
            }));

            const preselectedIds = this.parseIds(this._selectedContactIds);
            if (!this.hasInitializedSelection && !preselectedIds.length) {
                this.selectedRowIds = this.rows.map((row) => row.contactId);
            } else {
                this.selectedRowIds = preselectedIds;
            }
            this.hasInitializedSelection = true;
            this.publishSelection();
        }
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get emptyStateText() {
        return this.isChinese ? '此帳戶尚無聯絡人。' : 'No contacts found on this account.';
    }

    handleRowSelection(event) {
        this.selectedRowIds = event.detail.selectedRows.map((row) => row.contactId);
        this.publishSelection();
    }

    @api
    validate() {
        if (!this.hasRows) {
            return {
                isValid: false,
                errorMessage: this.isChinese
                    ? '此帳戶目前沒有可選擇的聯絡人。'
                    : 'This account does not have any contacts to select.'
            };
        }
        if (!this.selectedRowIds.length) {
            return {
                isValid: false,
                errorMessage: this.isChinese
                    ? '請至少選擇一位帳戶聯絡人。'
                    : 'Select at least one account contact.'
            };
        }
        return { isValid: true };
    }

    parseIds(rawValue) {
        if (!rawValue) {
            return [];
        }
        return rawValue
            .replaceAll(',', ';')
            .split(';')
            .map((value) => value.trim())
            .filter((value) => Boolean(value));
    }

    normalizeDescription(rawValue) {
        if (!rawValue) {
            return '';
        }
        return rawValue
            .replace(/^QBR 模擬聯絡人：\s*/u, '')
            .replace(/^QBR Simulation Contact:\s*/iu, '')
            .trim();
    }

    publishSelection() {
        this._selectedContactIds = this.selectedRowIds.join(';');
        this.notifyChange('selectedContactIds', this._selectedContactIds);
    }

    notifyChange(attributeName, value) {
        this.dispatchEvent(new FlowAttributeChangeEvent(attributeName, value));
    }
}