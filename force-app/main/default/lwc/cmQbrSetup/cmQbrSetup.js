import { LightningElement } from 'lwc';
import LANG from '@salesforce/i18n/lang';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFocusContext from '@salesforce/apex/CMQbrMeetingPrepController.getFocusContext';
import searchRootAccounts from '@salesforce/apex/CMQbrMeetingPrepController.searchRootAccounts';
import generateMeetingPreparation from '@salesforce/apex/CMQbrMeetingPrepController.generateMeetingPreparation';
import getEditableSlides from '@salesforce/apex/CMQbrMeetingPrepController.getEditableSlides';
import saveEditableSlides from '@salesforce/apex/CMQbrMeetingPrepController.saveEditableSlides';
import regenerateSupplierIntroFromFile from '@salesforce/apex/CMQbrMeetingPrepController.regenerateSupplierIntroFromFile';

const SEARCH_DEBOUNCE_MS = 250;
const SEARCH_LIMIT = 50;

export default class CmQbrSetup extends LightningElement {
    searchKey = '';
    focusCompanyId;
    focusCompanyName = '';
    focusDepartment = '';
    fixedTopics = [];

    accounts = [];
    selectedRootAccountId;
    selectedRows = [];

    isLoadingContext = true;
    isSearching = false;
    isGenerating = false;

    generatedMeetingId = '';
    generatedMeetingName = '';
    generatedMeetingUrl = '';
    generatedAt = '';

    isLoadingSlides = false;
    isSavingSlides = false;
    isRegeneratingSupplierSlide = false;

    pageOneTitle = '';
    pageTwoTitle = '';
    pageOneRichText = '';
    pageTwoRichText = '';

    uploadedSupplierFileId = '';
    uploadedSupplierFileName = '';

    _searchTimer;

    connectedCallback() {
        this.initialize();
    }

    get isChinese() {
        return (LANG || '').toLowerCase().startsWith('zh');
    }

    get cardTitle() {
        return this.isChinese ? 'QBR 會議準備生成' : 'QBR Meeting Preparation Generator';
    }

    get descriptionText() {
        return this.isChinese
            ? '系統會根據固定 9 個議題，為選定的 Account 全量生成 QBR 會議準備內容。'
            : 'The system generates full QBR meeting prep for 9 fixed topics for the selected Account.';
    }

    get focusCompanyLabel() {
        return this.isChinese ? 'FocusCompany（唯讀）' : 'FocusCompany (Read-only)';
    }

    get focusDepartmentLabel() {
        return this.isChinese ? 'FocusDepartment' : 'FocusDepartment';
    }

    get focusDepartmentPlaceholder() {
        return this.isChinese ? '例如：資材處、業務部' : 'Example: GSCM, Sales';
    }

    get accountSearchLabel() {
        return this.isChinese ? '搜尋 RootAccount' : 'Search RootAccount';
    }

    get accountSearchPlaceholder() {
        return this.isChinese ? '輸入 Account 名稱' : 'Enter account name';
    }

    get columns() {
        return [
            {
                label: this.isChinese ? 'Account' : 'Account',
                fieldName: 'recordUrl',
                type: 'url',
                typeAttributes: {
                    label: { fieldName: 'name' },
                    target: '_blank'
                }
            },
            {
                label: this.isChinese ? '產業' : 'Industry',
                fieldName: 'industry'
            },
            {
                label: this.isChinese ? '類型' : 'Type',
                fieldName: 'type'
            },
            {
                label: this.isChinese ? '最後更新' : 'Last Modified',
                fieldName: 'lastModifiedDate',
                type: 'date',
                typeAttributes: {
                    year: 'numeric',
                    month: '2-digit',
                    day: '2-digit'
                }
            }
        ];
    }

    get notSetText() {
        return this.isChinese ? '未設定' : 'Not set';
    }

    get hasFocusCompany() {
        return !!this.focusCompanyId;
    }

    get showFocusCompanyMissing() {
        return !this.isLoadingContext && !this.hasFocusCompany;
    }

    get focusCompanyMissingText() {
        return this.isChinese
            ? '尚未設定 Demo Target Account，請先到 Demo Setup 設定 FocusCompany。'
            : 'Demo target account is not configured. Please set FocusCompany in Demo Setup first.';
    }

    get fixedTopicsLabel() {
        return this.isChinese ? '固定議題（系統全生成）' : 'Fixed Topics (Always Fully Generated)';
    }

    get fixedTopicRows() {
        return (this.fixedTopics || []).map((topic, index) => ({
            key: `TOPIC_${index + 1}`,
            label: `${index + 1}. ${topic}`
        }));
    }

    get generateLabel() {
        return this.isChinese ? '產生 QBR 會議準備' : 'Generate QBR Meeting Prep';
    }

    get disableDepartmentInput() {
        return this.isGenerating || !this.hasFocusCompany;
    }

    get disableGenerate() {
        return (
            this.isLoadingContext ||
            this.isSearching ||
            this.isGenerating ||
            this.isLoadingSlides ||
            this.isSavingSlides ||
            this.isRegeneratingSupplierSlide ||
            !this.hasFocusCompany ||
            !this.selectedRootAccountId ||
            !this.focusDepartment?.trim()
        );
    }

    get showNoAccounts() {
        return !this.isSearching && this.accounts.length === 0;
    }

    get noAccountsText() {
        return this.isChinese ? '查無符合的 Account。' : 'No matching accounts found.';
    }

    get hasGeneratedMeeting() {
        return !!this.generatedMeetingUrl;
    }

    get generatedHintText() {
        return this.isChinese
            ? '已成功生成 QBR Meeting，請開啟記錄查看內容。'
            : 'QBR Meeting content generated. Open the record to review.';
    }

    get openMeetingLabel() {
        return this.isChinese ? '開啟 QBR Meeting' : 'Open QBR Meeting';
    }

    get generatedAtLabel() {
        if (!this.generatedAt) {
            return '';
        }
        return this.isChinese
            ? `生成時間：${this.generatedAt}`
            : `Generated at: ${this.generatedAt}`;
    }

    get slideEditorTitle() {
        return this.isChinese ? '第1頁 / 第2頁內容編輯' : 'Slide 1 / Slide 2 Editor';
    }

    get slideEditorHint() {
        return this.isChinese
            ? '可直接調整 AI 產生內容。第 2 頁可上傳檔案後重生供應商公司簡介。'
            : 'You can edit generated content directly. For Slide 2, upload a file to regenerate supplier intro.';
    }

    get pageOneLabel() {
        return this.pageOneTitle || (this.isChinese ? '第1頁：XXX公司簡介' : 'Slide 1: Focus Company Intro');
    }

    get pageTwoLabel() {
        return this.pageTwoTitle || (this.isChinese ? '第2頁：供應商公司簡介' : 'Slide 2: Supplier Intro');
    }

    get saveSlidesLabel() {
        return this.isChinese ? '儲存第1/第2頁內容' : 'Save Slide 1 / Slide 2';
    }

    get isBusySlides() {
        return this.isLoadingSlides || this.isSavingSlides || this.isRegeneratingSupplierSlide;
    }

    get disableSlideSave() {
        return this.isBusySlides || !this.generatedMeetingId;
    }

    get supplierUploadLabel() {
        return this.isChinese ? '上傳檔案（重生第2頁）' : 'Upload File (Regenerate Slide 2)';
    }

    get supplierUploadHint() {
        if (!this.uploadedSupplierFileName) {
            return this.isChinese ? '支援 PDF、PPT、DOC、圖片。上傳後會直接呼叫 prompt。' : 'Supports PDF, PPT, DOC, and image files. Prompt runs after upload.';
        }
        return this.isChinese
            ? `已上傳：${this.uploadedSupplierFileName}`
            : `Uploaded: ${this.uploadedSupplierFileName}`;
    }

    get supplierFileAccept() {
        return '.pdf,.ppt,.pptx,.doc,.docx,.txt,.png,.jpg,.jpeg';
    }

    get showSlideEditor() {
        return !!this.generatedMeetingId;
    }

    async initialize() {
        await this.loadFocusContext();
        await this.runSearch('');
    }

    async loadFocusContext() {
        this.isLoadingContext = true;
        try {
            const payload = await getFocusContext();
            this.focusCompanyId = payload?.focusCompanyId;
            this.focusCompanyName = payload?.focusCompanyName || '';
            this.fixedTopics = payload?.fixedTopics || [];
        } catch (error) {
            this.showToast(
                this.isChinese ? '讀取失敗' : 'Load failed',
                this.reduceError(error),
                'error'
            );
        } finally {
            this.isLoadingContext = false;
        }
    }

    handleDepartmentChange(event) {
        this.focusDepartment = event.detail.value || '';
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value || '';
        window.clearTimeout(this._searchTimer);
        this._searchTimer = window.setTimeout(() => {
            this.runSearch(this.searchKey);
        }, SEARCH_DEBOUNCE_MS);
    }

    async runSearch(searchTerm) {
        this.isSearching = true;
        try {
            const rows = await searchRootAccounts({
                searchTerm,
                limitSize: SEARCH_LIMIT
            });

            this.accounts = (rows || []).map((row) => ({
                ...row,
                recordUrl: `/${row.id}`,
                industry: row.industry || this.notSetText,
                type: row.type || this.notSetText
            }));

            if (this.selectedRootAccountId) {
                const stillExists = this.accounts.some(
                    (row) => row.id === this.selectedRootAccountId
                );
                if (stillExists) {
                    this.selectedRows = [this.selectedRootAccountId];
                } else {
                    this.selectedRootAccountId = null;
                    this.selectedRows = [];
                }
            }
        } catch (error) {
            this.accounts = [];
            this.showToast(
                this.isChinese ? '查詢失敗' : 'Search failed',
                this.reduceError(error),
                'error'
            );
        } finally {
            this.isSearching = false;
        }
    }

    handleRowSelection(event) {
        const rows = event.detail.selectedRows || [];
        if (!rows.length) {
            this.selectedRootAccountId = null;
            this.selectedRows = [];
            return;
        }
        this.selectedRootAccountId = rows[0].id;
        this.selectedRows = [rows[0].id];
    }

    async handleGenerate() {
        if (!this.hasFocusCompany) {
            this.showToast(
                this.isChinese ? '無法產生' : 'Unable to generate',
                this.focusCompanyMissingText,
                'error'
            );
            return;
        }

        if (!this.focusDepartment?.trim()) {
            this.showToast(
                this.isChinese ? '無法產生' : 'Unable to generate',
                this.isChinese
                    ? '請先輸入 FocusDepartment。'
                    : 'Please fill in FocusDepartment.',
                'error'
            );
            return;
        }

        if (!this.selectedRootAccountId) {
            this.showToast(
                this.isChinese ? '無法產生' : 'Unable to generate',
                this.isChinese
                    ? '請先選擇 RootAccount。'
                    : 'Please select a RootAccount.',
                'error'
            );
            return;
        }

        this.isGenerating = true;
        try {
            const result = await generateMeetingPreparation({
                rootAccountId: this.selectedRootAccountId,
                focusDepartment: this.focusDepartment
            });

            this.generatedMeetingId = result?.meetingId || '';
            this.generatedMeetingName = result?.meetingName || '';
            this.generatedMeetingUrl = result?.meetingUrl || '';
            this.generatedAt = result?.generatedAt || '';

            this.uploadedSupplierFileId = '';
            this.uploadedSupplierFileName = '';

            await this.loadEditableSlides(this.generatedMeetingId);

            this.showToast(
                this.isChinese ? '生成完成' : 'Generation completed',
                this.isChinese
                    ? 'QBR 會議準備已成功生成並寫入 QBR Meeting。'
                    : 'QBR meeting preparation generated and saved to QBR Meeting.',
                'success'
            );
        } catch (error) {
            this.showToast(
                this.isChinese ? '生成失敗' : 'Generation failed',
                this.reduceError(error),
                'error'
            );
        } finally {
            this.isGenerating = false;
        }
    }

    async loadEditableSlides(meetingId) {
        if (!meetingId) {
            return;
        }

        this.isLoadingSlides = true;
        try {
            const payload = await getEditableSlides({ meetingId });
            this.applyEditablePayload(payload);
        } catch (error) {
            this.showToast(
                this.isChinese ? '載入頁面內容失敗' : 'Failed to load slide content',
                this.reduceError(error),
                'error'
            );
        } finally {
            this.isLoadingSlides = false;
        }
    }

    applyEditablePayload(payload) {
        this.pageOneTitle = payload?.pageOneTitle || '';
        this.pageTwoTitle = payload?.pageTwoTitle || '';
        this.pageOneRichText = payload?.pageOneRichText || '';
        this.pageTwoRichText = payload?.pageTwoRichText || '';
    }

    handlePageOneRichTextChange(event) {
        this.pageOneRichText = event.detail?.value || '';
    }

    handlePageTwoRichTextChange(event) {
        this.pageTwoRichText = event.detail?.value || '';
    }

    async handleSaveSlides() {
        if (!this.generatedMeetingId) {
            return;
        }

        this.isSavingSlides = true;
        try {
            const payload = await saveEditableSlides({
                meetingId: this.generatedMeetingId,
                pageOneTitle: this.pageOneTitle,
                pageTwoTitle: this.pageTwoTitle,
                pageThreeTitle: null,
                pageFourTitle: null,
                pageFiveTitle: null,
                pageSixTitle: null,
                pageSevenTitle: null,
                pageEightTitle: null,
                pageNineTitle: null,
                pageOneRichText: this.pageOneRichText,
                pageTwoRichText: this.pageTwoRichText,
                pageThreeRichText: null,
                pageFourRichText: null,
                pageFiveSelectedRowIndexes: null,
                pageSixSelectedRowIndexes: null
            });
            this.applyEditablePayload(payload);

            this.showToast(
                this.isChinese ? '儲存完成' : 'Saved',
                this.isChinese
                    ? '第1頁與第2頁內容已更新。'
                    : 'Slide 1 and Slide 2 content updated.',
                'success'
            );
        } catch (error) {
            this.showToast(
                this.isChinese ? '儲存失敗' : 'Save failed',
                this.reduceError(error),
                'error'
            );
        } finally {
            this.isSavingSlides = false;
        }
    }

    async handleSupplierUploadFinished(event) {
        const files = event.detail?.files || [];
        if (!files.length) {
            return;
        }

        this.uploadedSupplierFileId = files[0].documentId;
        this.uploadedSupplierFileName = files[0].name || '';

        await this.regenerateSupplierSlideFromFile();
    }

    async regenerateSupplierSlideFromFile() {
        if (!this.generatedMeetingId || !this.uploadedSupplierFileId) {
            return;
        }

        this.isRegeneratingSupplierSlide = true;
        try {
            const payload = await regenerateSupplierIntroFromFile({
                meetingId: this.generatedMeetingId,
                fileId: this.uploadedSupplierFileId
            });
            this.applyEditablePayload(payload);

            this.showToast(
                this.isChinese ? '第2頁重生完成' : 'Slide 2 regenerated',
                this.isChinese
                    ? '已根據上傳檔案更新供應商公司簡介。'
                    : 'Supplier intro was regenerated from uploaded file.',
                'success'
            );
        } catch (error) {
            this.showToast(
                this.isChinese ? '第2頁重生失敗' : 'Slide 2 regeneration failed',
                this.reduceError(error),
                'error'
            );
        } finally {
            this.isRegeneratingSupplierSlide = false;
        }
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

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || String(error);
    }
}