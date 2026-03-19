import { LightningElement, api, wire } from 'lwc';
import LANG from '@salesforce/i18n/lang';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import getContactsByIds from '@salesforce/apex/CM_QBRFlowService.getContactsByIds';

export default class CmQbrRecipientPicker extends LightningElement {
    _outputMode;
    _selectedContactIds;

    @api recipientContactIds;
    @api internalRecipients;

    recipientOptions = [];
    selectedValues = [];
    contactIdsForWire = [];

    get isChinese() {
        return (LANG || '').toLowerCase().startsWith('zh');
    }

    @api
    get outputMode() {
        return this._outputMode;
    }

    set outputMode(value) {
        this._outputMode = value || 'Internal Briefing';
        this.initializeDefaults();
    }

    @api
    get selectedContactIds() {
        return this._selectedContactIds;
    }

    set selectedContactIds(value) {
        this._selectedContactIds = value;
        this.contactIdsForWire = this.parseIds(value);
    }

    @wire(getContactsByIds, { contactIds: '$contactIdsForWire' })
    wiredRecipients({ data }) {
        if (data) {
            this.recipientOptions = data.map((item) => ({
                label: item.label,
                value: item.contactId
            }));
            if (this.isExternalMode && !this.selectedValues.length) {
                this.selectedValues = this.recipientOptions.map((option) => option.value);
                this.publishExternalSelection();
            }
        }
    }

    connectedCallback() {
        this.initializeDefaults();
    }

    get isExternalMode() {
        return this._outputMode === 'External Agenda';
    }

    get hasExternalOptions() {
        return this.recipientOptions.length > 0;
    }

    get externalIntroText() {
        return this.isChinese
            ? '請選擇要接收中性版外部議程草稿的收件人。'
            : 'Select the external recipients who should receive the neutral agenda draft.';
    }

    get externalRecipientsLabel() {
        return this.isChinese ? '外部收件人' : 'External Recipients';
    }

    get availableLabel() {
        return this.isChinese ? '可選擇' : 'Available';
    }

    get selectedLabel() {
        return this.isChinese ? '已選擇' : 'Selected';
    }

    get noExternalOptionsText() {
        return this.isChinese
            ? '目前沒有可用於外部發送的已選聯絡人。'
            : 'No selected contacts are available for external distribution.';
    }

    get internalIntroText() {
        return this.isChinese
            ? '請輸入要接收會前簡報的內部收件人。'
            : 'Enter the internal recipients who should receive the briefing pre-read.';
    }

    get internalRecipientsLabel() {
        return this.isChinese ? '內部收件人' : 'Internal Recipients';
    }

    get internalRecipientsPlaceholder() {
        return this.isChinese ? 'Arthur；Claire；Ian' : 'Arthur; Claire; Ian';
    }

    handleRecipientChange(event) {
        this.selectedValues = [...event.detail.value];
        this.publishExternalSelection();
    }

    handleInternalRecipientChange(event) {
        this.internalRecipients = event.detail.value;
        this.notifyChange('internalRecipients', this.internalRecipients);
    }

    @api
    validate() {
        if (this.isExternalMode) {
            if (!this.selectedValues.length) {
                return {
                    isValid: false,
                    errorMessage: this.isChinese
                        ? '請至少選擇一位外部收件人。'
                        : 'Select at least one external recipient.'
                };
            }
            return { isValid: true };
        }

        if (!this.internalRecipients) {
            return {
                isValid: false,
                errorMessage: this.isChinese
                    ? '請至少填寫一位內部收件人。'
                    : 'Provide at least one internal recipient.'
            };
        }
        return { isValid: true };
    }

    initializeDefaults() {
        if (this.isExternalMode) {
            this.internalRecipients = '';
            this.notifyChange('internalRecipients', this.internalRecipients);
            if (this.recipientOptions.length && !this.selectedValues.length) {
                this.selectedValues = this.recipientOptions.map((option) => option.value);
                this.publishExternalSelection();
            }
            return;
        }

        this.selectedValues = [];
        this.recipientContactIds = '';
        this.notifyChange('recipientContactIds', this.recipientContactIds);
        if (!this.internalRecipients) {
            this.internalRecipients = this.isChinese ? 'Arthur；Claire；Ian' : 'Arthur; Claire; Ian';
            this.notifyChange('internalRecipients', this.internalRecipients);
        }
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

    publishExternalSelection() {
        this.recipientContactIds = this.selectedValues.join(';');
        this.notifyChange('recipientContactIds', this.recipientContactIds);
    }

    notifyChange(attributeName, value) {
        this.dispatchEvent(new FlowAttributeChangeEvent(attributeName, value));
    }
}