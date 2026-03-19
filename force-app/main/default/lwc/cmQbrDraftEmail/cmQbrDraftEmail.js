import { LightningElement, api, wire } from 'lwc';
import LANG from '@salesforce/i18n/lang';
import USER_ID from '@salesforce/user/Id';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import getAccountContacts from '@salesforce/apex/CM_QBRFlowService.getAccountContacts';
import getContactsByIds from '@salesforce/apex/CM_QBRFlowService.getContactsByIds';
import getActiveUsers from '@salesforce/apex/CM_QBRFlowService.getActiveUsers';
import sendDraftEmail from '@salesforce/apex/CM_QBRFlowService.sendDraftEmail';
import getDraftState from '@salesforce/apex/CMQBRAsyncEmailDraftService.getDraftState';

const MAX_SUGGESTIONS = 8;
const DRAFT_POLL_INTERVAL_MS = 1500;
const DRAFT_POLL_MAX_ATTEMPTS = 20;

export default class CmQbrDraftEmail extends LightningElement {
    @api accountId;
    @api selectedContactIds;
    @api briefingHtml;
    @api outputMode;
    @api recipientContactIds;
    @api ccRecipientContactIds;
    @api internalRecipients;
    @api selectedUserIds;
    @api ccSelectedUserIds;
    @api emailSubject;
    @api emailBody;
    @api includeActionItems;
    @api includePricingAsks;
    @api includeRiskAlerts;
    @api autoSelectAllExternalRecipients;
    @api summaryModeLabelOverride;
    @api hideReviewFlags;

    @api editedEmailSubject;
    @api editedEmailBody;
    @api sendStatusMessage;
    @api emailSent;

    contactOptions = [];
    userOptions = [];
    contactIdsForWire = [];

    selectedContactValues = [];
    ccContactValues = [];
    selectedUserValues = [];
    ccUserValues = [];

    toSearchTerm = '';
    ccSearchTerm = '';
    isSending = false;
    isDraftLoading = false;
    draftPollAttempts = 0;
    draftPollHandle;
    subjectTouched = false;
    bodyTouched = false;
    _draftBufferId;

    @api
    get draftBufferId() {
        return this._draftBufferId;
    }

    set draftBufferId(value) {
        const nextValue = value || '';
        const hasChanged = nextValue !== this._draftBufferId;
        this._draftBufferId = nextValue;

        if (hasChanged && this.isConnected && nextValue) {
            this.startDraftPolling();
        }
    }

    get isChinese() {
        return (LANG || '').toLowerCase().startsWith('zh');
    }

    connectedCallback() {
        this.editedEmailSubject = this.editedEmailSubject || this.emailSubject || '';
        this.editedEmailBody = this.normalizeBodyForEditor(this.editedEmailBody || this.emailBody || '');
        this.contactIdsForWire = this.parseIds(this.selectedContactIds);
        this.selectedContactValues = this.parseIds(this.recipientContactIds);
        this.ccContactValues = this.parseIds(this.ccRecipientContactIds);
        this.selectedUserValues = this.parseIds(this.selectedUserIds);
        this.ccUserValues = this.parseIds(this.ccSelectedUserIds);

        this.notifyChange('editedEmailSubject', this.editedEmailSubject);
        this.notifyChange('editedEmailBody', this.editedEmailBody);
        if (this.emailSent === undefined || this.emailSent === null) {
            this.emailSent = false;
            this.notifyChange('emailSent', this.emailSent);
        }

        if (this.draftBufferId) {
            this.startDraftPolling();
        }
    }

    disconnectedCallback() {
        this.clearDraftPolling();
    }

    @wire(getContactsByIds, { contactIds: '$contactIdsForWire' })
    wiredContactsByIds({ data }) {
        if (!data || !this.contactIdsForWire.length) {
            return;
        }
        this.applyContactOptions(data);
    }

    @wire(getAccountContacts, { accountId: '$accountId' })
    wiredAccountContacts({ data }) {
        if (!data || this.contactIdsForWire.length) {
            return;
        }
        this.applyContactOptions(data);
    }

    @wire(getActiveUsers)
    wiredUsers({ data }) {
        if (!data) {
            return;
        }

        this.userOptions = data.map((item) => this.normalizeUserOption(item));

        if (
            !this.isExternalMode &&
            !this.selectedContactValues.length &&
            !this.ccContactValues.length &&
            !this.selectedUserValues.length &&
            !this.ccUserValues.length &&
            this.userOptions.some((option) => option.value === USER_ID)
        ) {
            this.selectedUserValues = [USER_ID];
        }

        this.commitSelections();
    }

    get isExternalMode() {
        return this.outputMode === 'External Agenda';
    }

    get outputModeSummary() {
        if (this.summaryModeLabelOverride) {
            return this.summaryModeLabelOverride;
        }
        if (this.isExternalMode) {
            return this.isChinese ? '外部議程' : 'External Agenda';
        }
        return this.isChinese ? '內部簡報' : 'Internal Briefing';
    }

    get primaryRecipientSummary() {
        const labels = this.toRecipientPills.map((pill) => pill.label);
        if (!labels.length) {
            return this.isChinese
                ? '尚未選擇收件者。'
                : 'No primary recipients selected.';
        }
        return labels.join(this.isChinese ? '、' : ', ');
    }

    get ccRecipientSummary() {
        const labels = this.ccRecipientPills.map((pill) => pill.label);
        if (!labels.length) {
            return this.isChinese
                ? '未設定副本。'
                : 'No CC recipients selected.';
        }
        return labels.join(this.isChinese ? '、' : ', ');
    }

    get coverageSummary() {
        const selectedFlags = [];
        if (this.includeActionItems) {
            selectedFlags.push(this.isChinese ? '行動事項' : 'Action Items');
        }
        if (this.includePricingAsks) {
            selectedFlags.push(this.isChinese ? '價格訴求' : 'Pricing Asks');
        }
        if (this.includeRiskAlerts) {
            selectedFlags.push(this.isChinese ? '風險提醒' : 'Risk Alerts');
        }
        return selectedFlags.length
            ? selectedFlags.join(this.isChinese ? '、' : ', ')
            : (this.isChinese ? '尚未勾選檢視項目。' : 'No review flags selected.');
    }

    get outputModeLabel() {
        return this.isChinese ? '輸出模式' : 'Output Mode';
    }

    get toSummaryLabel() {
        return this.isChinese ? '收件者' : 'To';
    }

    get ccSummaryLabel() {
        return this.isChinese ? '副本' : 'Cc';
    }

    get reviewFlagsLabel() {
        return this.isChinese ? '檢視項目' : 'Review Flags';
    }

    get showReviewFlagsSummary() {
        return !this.isTrue(this.hideReviewFlags);
    }

    get sectionDescription() {
        return this.isChinese
            ? '可從內部使用者與此 Account 的聯絡人中選擇收件者與副本。'
            : 'Select To and Cc recipients from active users and this account’s contacts.';
    }

    get toFieldLabel() {
        return this.isChinese ? '收件者' : 'To';
    }

    get ccFieldLabel() {
        return this.isChinese ? '副本' : 'Cc';
    }

    get searchPlaceholder() {
        return this.isChinese
            ? '輸入姓名、職稱或 Email'
            : 'Search by name, title, or email';
    }

    get addedRecipientsLabel() {
        return this.isChinese ? '已加入' : 'Selected';
    }

    get suggestionTitle() {
        return this.isChinese ? '建議名單' : 'Suggested Matches';
    }

    get emailSubjectLabel() {
        return this.isChinese ? '郵件主旨' : 'Email Subject';
    }

    get emailBodyLabel() {
        return this.isChinese ? '郵件草稿內容' : 'Draft Email Body';
    }

    get sendButtonLabel() {
        if (this.isSending) {
            return this.isChinese ? '寄送中...' : 'Sending...';
        }
        if (this.isDraftLoading) {
            return this.isChinese ? '草稿產生中...' : 'Draft pending...';
        }
        return this.isChinese ? '送出郵件' : 'Send Email';
    }

    get isSendDisabled() {
        return this.isSending || this.isDraftLoading;
    }

    get draftStatusText() {
        return this.isChinese
            ? 'AI 正在背景產生郵件草稿，完成後會自動帶入。'
            : 'AI is generating the draft in the background and will auto-fill when ready.';
    }

    get statusClassName() {
        if (this.emailSent) {
            return 'slds-text-color_success slds-m-top_small';
        }
        if (this.sendStatusMessage) {
            return 'slds-text-color_error slds-m-top_small';
        }
        return 'slds-hide';
    }

    get recipientPool() {
        return [...this.userOptions, ...this.contactOptions];
    }

    get toRecipientPills() {
        return this.buildPills(this.primarySelectedValues);
    }

    get ccRecipientPills() {
        return this.buildPills(this.ccSelectedValues);
    }

    get hasToRecipients() {
        return this.toRecipientPills.length > 0;
    }

    get hasCcRecipients() {
        return this.ccRecipientPills.length > 0;
    }

    get toFilteredOptions() {
        return this.buildFilteredOptions(this.toSearchTerm);
    }

    get ccFilteredOptions() {
        return this.buildFilteredOptions(this.ccSearchTerm);
    }

    get hasToMatches() {
        return this.toFilteredOptions.length > 0;
    }

    get hasCcMatches() {
        return this.ccFilteredOptions.length > 0;
    }

    get showToSuggestionPanel() {
        return Boolean((this.toSearchTerm || '').trim());
    }

    get showCcSuggestionPanel() {
        return Boolean((this.ccSearchTerm || '').trim());
    }

    get noMatchesText() {
        return this.isChinese
            ? '沒有符合的名單，請調整搜尋條件。'
            : 'No matching recipients. Adjust the search term.';
    }

    get primarySelectedValues() {
        return [...this.selectedUserValues, ...this.selectedContactValues];
    }

    get ccSelectedValues() {
        return [...this.ccUserValues, ...this.ccContactValues];
    }

    handleRecipientSearchChange(event) {
        const listName = event.target.dataset.list;
        const nextValue = event.detail.value;
        if (listName === 'cc') {
            this.ccSearchTerm = nextValue;
            return;
        }
        this.toSearchTerm = nextValue;
    }

    handleRecipientSelect(event) {
        const recipientId = event.currentTarget.dataset.recipientId;
        const listName = event.currentTarget.dataset.list || 'to';
        if (!recipientId) {
            return;
        }

        if (listName === 'cc') {
            if (!this.ccSelectedValues.includes(recipientId) && !this.primarySelectedValues.includes(recipientId)) {
                if (this.isContactId(recipientId)) {
                    this.ccContactValues = [...this.ccContactValues, recipientId];
                } else {
                    this.ccUserValues = [...this.ccUserValues, recipientId];
                }
                this.commitSelections();
            }
            this.ccSearchTerm = '';
            return;
        }

        if (!this.primarySelectedValues.includes(recipientId) && !this.ccSelectedValues.includes(recipientId)) {
            if (this.isContactId(recipientId)) {
                this.selectedContactValues = [...this.selectedContactValues, recipientId];
            } else {
                this.selectedUserValues = [...this.selectedUserValues, recipientId];
            }
            this.commitSelections();
        }
        this.toSearchTerm = '';
    }

    handleToRecipientRemove(event) {
        this.removeRecipient(event, 'to');
    }

    handleCcRecipientRemove(event) {
        this.removeRecipient(event, 'cc');
    }

    removeRecipient(event, listName) {
        const recipientId = event.currentTarget.name || event.target.name;
        if (!recipientId) {
            return;
        }

        if (listName === 'cc') {
            if (this.isContactId(recipientId)) {
                this.ccContactValues = this.ccContactValues.filter((value) => value !== recipientId);
            } else {
                this.ccUserValues = this.ccUserValues.filter((value) => value !== recipientId);
            }
            this.commitSelections();
            return;
        }

        if (this.isContactId(recipientId)) {
            this.selectedContactValues = this.selectedContactValues.filter((value) => value !== recipientId);
        } else {
            this.selectedUserValues = this.selectedUserValues.filter((value) => value !== recipientId);
        }
        this.commitSelections();
    }

    handleSubjectChange(event) {
        this.subjectTouched = true;
        this.editedEmailSubject = event.detail.value;
        this.resetSendState();
        this.notifyChange('editedEmailSubject', this.editedEmailSubject);
    }

    handleBodyChange(event) {
        this.bodyTouched = true;
        this.editedEmailBody = event.detail && event.detail.value !== undefined
            ? event.detail.value
            : event.target.value;
        this.resetSendState();
        this.notifyChange('editedEmailBody', this.editedEmailBody);
    }

    async handleSendClick() {
        const validation = this.validate();
        if (!validation.isValid) {
            this.sendStatusMessage = validation.errorMessage;
            this.emailSent = false;
            this.notifyChange('sendStatusMessage', this.sendStatusMessage);
            this.notifyChange('emailSent', this.emailSent);
            return;
        }

        this.isSending = true;
        try {
            const response = await sendDraftEmail({
                outputMode: this.outputMode,
                recipientContactIds: this.recipientContactIds,
                recipientUserIds: this.selectedUserIds,
                ccRecipientContactIds: this.ccRecipientContactIds,
                ccRecipientUserIds: this.ccSelectedUserIds,
                emailSubject: this.editedEmailSubject,
                emailBody: this.editedEmailBody
            });
            this.emailSent = Boolean(response && response.success);
            this.sendStatusMessage = response && response.message
                ? response.message
                : (this.isChinese ? '郵件送出完成。' : 'Email sent.');
            this.notifyChange('emailSent', this.emailSent);
            this.notifyChange('sendStatusMessage', this.sendStatusMessage);
        } catch (error) {
            this.emailSent = false;
            this.sendStatusMessage = this.extractErrorMessage(error);
            this.notifyChange('emailSent', this.emailSent);
            this.notifyChange('sendStatusMessage', this.sendStatusMessage);
        } finally {
            this.isSending = false;
        }
    }

    @api
    validate() {
        if (!this.editedEmailSubject || !this.editedEmailBody) {
            return {
                isValid: false,
                errorMessage: this.isChinese
                    ? '郵件主旨與內容皆為必填。'
                    : 'Email subject and body are required.'
            };
        }
        if (!this.primarySelectedValues.length) {
            return {
                isValid: false,
                errorMessage: this.isChinese
                    ? '請至少選擇一位收件者。'
                    : 'Select at least one primary recipient.'
            };
        }
        return { isValid: true };
    }

    normalizeContactOption(item) {
        const label = item.label || item.name || '';
        const searchSegments = [
            item.name,
            item.title,
            item.email,
            item.description,
            label
        ].filter((value) => Boolean(value));
        return {
            label,
            value: item.contactId,
            primaryText: item.name || label,
            secondaryText: item.email || '',
            supportingText: this.buildSupportingText(item.title || item.description, this.isChinese ? '聯絡人' : 'Contact'),
            searchText: searchSegments.join(' ').toLowerCase(),
            iconName: 'standard:contact'
        };
    }

    normalizeUserOption(item) {
        const label = item.label || item.name || '';
        const searchSegments = [item.name, item.email, label].filter((value) => Boolean(value));
        return {
            label,
            value: item.userId,
            primaryText: item.name || label,
            secondaryText: item.email || '',
            supportingText: this.isChinese ? '使用者' : 'User',
            searchText: searchSegments.join(' ').toLowerCase(),
            iconName: 'standard:user'
        };
    }

    applyContactOptions(records) {
        this.contactOptions = records.map((item) => this.normalizeContactOption(item));

        this.commitSelections();
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

    get shouldAutoSelectExternalRecipients() {
        return !this.isFalse(this.autoSelectAllExternalRecipients);
    }

    isContactId(recordId) {
        return this.contactOptions.some((option) => option.value === recordId);
    }

    isTrue(value) {
        return value === true || value === 'true';
    }

    isFalse(value) {
        return value === false || value === 'false';
    }

    buildPills(selectedValues) {
        const labelsById = new Map(this.recipientPool.map((option) => [option.value, option.label]));
        return selectedValues
            .map((value) => ({
                name: value,
                label: labelsById.get(value) || value
            }))
            .filter((pill) => Boolean(pill.label));
    }

    buildFilteredOptions(searchTerm) {
        const selectedSet = new Set([...this.primarySelectedValues, ...this.ccSelectedValues]);
        const term = (searchTerm || '').trim().toLowerCase();

        return this.recipientPool
            .filter((option) => !selectedSet.has(option.value))
            .filter((option) => !term || option.searchText.includes(term))
            .slice(0, MAX_SUGGESTIONS);
    }

    commitSelections() {
        this.selectedContactValues = this.filterSelections(this.selectedContactValues, this.contactOptions);
        this.selectedUserValues = this.filterSelections(this.selectedUserValues, this.userOptions);

        const selectedToSet = new Set([...this.selectedContactValues, ...this.selectedUserValues]);

        this.ccContactValues = this.filterSelections(
            this.ccContactValues,
            this.contactOptions,
            selectedToSet
        );
        this.ccUserValues = this.filterSelections(
            this.ccUserValues,
            this.userOptions,
            selectedToSet
        );

        this.recipientContactIds = this.selectedContactValues.join(';');
        this.ccRecipientContactIds = this.ccContactValues.join(';');
        this.selectedUserIds = this.selectedUserValues.join(';');
        this.ccSelectedUserIds = this.ccUserValues.join(';');

        this.notifyChange('recipientContactIds', this.recipientContactIds);
        this.notifyChange('ccRecipientContactIds', this.ccRecipientContactIds);
        this.notifyChange('selectedUserIds', this.selectedUserIds);
        this.notifyChange('ccSelectedUserIds', this.ccSelectedUserIds);
        this.resetSendState();
    }

    filterSelections(values, options, excludedValues = new Set()) {
        const validValues = new Set(options.map((option) => option.value));
        return [...new Set(values)]
            .filter((value) => validValues.has(value))
            .filter((value) => !excludedValues.has(value));
    }

    buildSupportingText(baseText, typeLabel) {
        if (baseText) {
            return baseText + ' · ' + typeLabel;
        }
        return typeLabel;
    }

    resetSendState() {
        this.emailSent = false;
        this.sendStatusMessage = '';
        this.notifyChange('emailSent', this.emailSent);
        this.notifyChange('sendStatusMessage', this.sendStatusMessage);
    }

    extractErrorMessage(error) {
        const defaultMessage = this.isChinese ? '郵件送出失敗。' : 'Failed to send the email.';
        if (!error) {
            return defaultMessage;
        }
        if (error.body && error.body.message) {
            return error.body.message;
        }
        if (error.message) {
            return error.message;
        }
        return defaultMessage;
    }

    normalizeBodyForEditor(rawBody) {
        const nextValue = rawBody || '';
        if (!nextValue) {
            return '';
        }
        if (/<[a-z][\s\S]*>/i.test(nextValue)) {
            return nextValue;
        }

        const escaped = nextValue
            .replaceAll('&', '&amp;')
            .replaceAll('<', '&lt;')
            .replaceAll('>', '&gt;')
            .replaceAll('"', '&quot;')
            .replaceAll("'", '&#39;');

        const paragraphs = escaped
            .split(/\r?\n\r?\n/)
            .map((block) => block.replace(/\r?\n/g, '<br/>'))
            .filter((block) => Boolean(block));

        if (!paragraphs.length) {
            return '<p></p>';
        }

        return paragraphs.map((block) => `<p>${block}</p>`).join('');
    }

    startDraftPolling() {
        this.draftPollAttempts = 0;
        this.isDraftLoading = true;
        this.loadDraftState();
    }

    clearDraftPolling() {
        if (this.draftPollHandle) {
            clearTimeout(this.draftPollHandle);
            this.draftPollHandle = null;
        }
    }

    async loadDraftState() {
        if (!this.draftBufferId) {
            this.isDraftLoading = false;
            return;
        }

        this.clearDraftPolling();

        try {
            const response = await getDraftState({ bufferId: this.draftBufferId });
            const status = response && response.status ? response.status : '';

            if (response && !this.subjectTouched && response.subject) {
                this.editedEmailSubject = response.subject;
                this.notifyChange('editedEmailSubject', this.editedEmailSubject);
            }
            if (response && !this.bodyTouched && response.body) {
                this.editedEmailBody = this.normalizeBodyForEditor(response.body);
                this.notifyChange('editedEmailBody', this.editedEmailBody);
            }

            if (status === 'Completed') {
                this.isDraftLoading = false;
                if (response && response.errorMessage) {
                    this.sendStatusMessage = this.isChinese
                        ? '草稿已以 fallback 內容完成：' + response.errorMessage
                        : 'Draft completed with fallback content: ' + response.errorMessage;
                    this.notifyChange('sendStatusMessage', this.sendStatusMessage);
                }
                return;
            }

            if (status === 'Failed') {
                this.isDraftLoading = false;
                this.sendStatusMessage = response && response.errorMessage
                    ? response.errorMessage
                    : (this.isChinese ? '背景草稿產生失敗。' : 'Background draft generation failed.');
                this.notifyChange('sendStatusMessage', this.sendStatusMessage);
                return;
            }

            this.draftPollAttempts += 1;
            if (this.draftPollAttempts < DRAFT_POLL_MAX_ATTEMPTS) {
                this.draftPollHandle = setTimeout(
                    () => this.loadDraftState(),
                    DRAFT_POLL_INTERVAL_MS
                );
                return;
            }

            this.isDraftLoading = false;
            this.sendStatusMessage = this.isChinese
                ? '背景草稿仍在處理中，請稍後再試。'
                : 'The background draft is still processing. Please wait a moment and try again.';
            this.notifyChange('sendStatusMessage', this.sendStatusMessage);
        } catch (error) {
            this.isDraftLoading = false;
            this.sendStatusMessage = this.extractErrorMessage(error);
            this.notifyChange('sendStatusMessage', this.sendStatusMessage);
        }
    }

    notifyChange(attributeName, value) {
        this.dispatchEvent(new FlowAttributeChangeEvent(attributeName, value));
    }
}