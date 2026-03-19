import { LightningElement, api } from 'lwc';
import LANG from '@salesforce/i18n/lang';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import getPresentationExportOptions from '@salesforce/apex/CMQbrMeetingPrepController.getPresentationExportOptions';
import generatePresentationFile from '@salesforce/apex/CMQbrMeetingPrepController.generatePresentationFile';

export default class CmQbrPresentationExport extends LightningElement {
    _qbrMeetingId = '';
    topics = [];
    selectedRowKeys = [];

    isLoading = false;
    isGenerating = false;
    statusMessage = '';
    errorMessage = '';

    @api generatedFileUrl;
    @api generatedFileName;
    @api generatedContentDocumentId;
    @api generatedContentVersionId;
    @api selectedSlideNumbers;

    @api
    get qbrMeetingId() {
        return this._qbrMeetingId;
    }

    set qbrMeetingId(value) {
        const normalized = value || '';
        const changed = normalized !== this._qbrMeetingId;
        this._qbrMeetingId = normalized;
        if (changed && this.isConnected && this._qbrMeetingId) {
            this.loadOptions();
        }
    }

    connectedCallback() {
        if (this._qbrMeetingId) {
            this.loadOptions();
        }
    }

    get isChinese() {
        return (LANG || '').toLowerCase().startsWith('zh');
    }

    get title() {
        return this.isChinese ? '最後一步：生成簡報檔' : 'Final Step: Generate Presentation';
    }

    get hintText() {
        return this.isChinese
            ? '請勾選要輸出的議題（預設全選），再按「生成簡報檔」。'
            : 'Select topics to export (all selected by default), then click Generate.';
    }

    get selectAllLabel() {
        return this.isChinese ? '全選' : 'Select All';
    }

    get clearLabel() {
        return this.isChinese ? '清空' : 'Clear';
    }

    get columns() {
        return [
            { label: '#', fieldName: 'slideNumber', type: 'number', initialWidth: 70 },
            { label: this.isChinese ? '議題' : 'Topic', fieldName: 'topicTitle', wrapText: true },
            { label: this.isChinese ? '當前標題' : 'Current Title', fieldName: 'slideTitle', wrapText: true }
        ];
    }

    get rows() {
        return this.topics.map((topic) => ({
            key: topic.key,
            slideNumber: topic.slideNumber,
            topicTitle: topic.topicTitle,
            slideTitle: topic.slideTitle
        }));
    }

    get selectedSlideNumberList() {
        const selected = [];
        this.topics.forEach((topic) => {
            if (this.selectedRowKeys.includes(topic.key)) {
                selected.push(topic.slideNumber);
            }
        });
        selected.sort((a, b) => a - b);
        return selected;
    }

    get selectedCountLabel() {
        return this.isChinese
            ? `已選 ${this.selectedSlideNumberList.length} / 9`
            : `${this.selectedSlideNumberList.length} / 9 selected`;
    }

    get isBusy() {
        return this.isLoading || this.isGenerating;
    }

    get disableGenerate() {
        return this.isBusy || !this._qbrMeetingId || !this.selectedSlideNumberList.length;
    }

    get showFileLink() {
        return !!this.generatedFileUrl;
    }

    get fileLinkLabel() {
        if (this.generatedFileName) {
            return this.generatedFileName;
        }
        return this.isChinese ? '開啟已生成簡報' : 'Open generated presentation';
    }

    get generateButtonLabel() {
        if (this.isGenerating) {
            return this.isChinese ? '生成中...' : 'Generating...';
        }
        return this.isChinese ? '生成簡報檔' : 'Generate Presentation';
    }

    async loadOptions() {
        if (!this._qbrMeetingId) {
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';
        try {
            const payload = await getPresentationExportOptions({ meetingId: this._qbrMeetingId });
            this.topics = (payload?.topics || []).map((topic) => ({
                key: topic.key,
                slideNumber: topic.slideNumber,
                topicTitle: topic.topicTitle,
                slideTitle: topic.slideTitle
            }));
            this.selectedRowKeys = this.topics.map((topic) => topic.key);
            this.generatedFileUrl = '';
            this.generatedFileName = '';
            this.generatedContentDocumentId = '';
            this.generatedContentVersionId = '';
            this.notifySelections();
            this.notifyFileOutputs();
            this.statusMessage = this.isChinese ? '已載入 9 個議題，可開始勾選。' : 'Loaded 9 topics. You can now select slides.';
        } catch (error) {
            this.errorMessage = this.reduceError(error);
            this.statusMessage = '';
        } finally {
            this.isLoading = false;
        }
    }

    handleRowSelection(event) {
        const selectedRows = event.detail?.selectedRows || [];
        this.selectedRowKeys = selectedRows.map((row) => row.key);
        this.notifySelections();
    }

    handleSelectAll() {
        this.selectedRowKeys = this.topics.map((topic) => topic.key);
        this.notifySelections();
    }

    handleClearSelection() {
        this.selectedRowKeys = [];
        this.notifySelections();
    }

    async handleGenerate() {
        if (!this._qbrMeetingId) {
            this.errorMessage = this.isChinese ? '缺少 QBR Meeting，無法生成。' : 'QBR Meeting is missing.';
            return;
        }
        if (!this.selectedSlideNumberList.length) {
            this.errorMessage = this.isChinese ? '請至少選擇 1 個議題。' : 'Select at least 1 topic.';
            return;
        }

        this.isGenerating = true;
        this.errorMessage = '';
        this.statusMessage = '';
        try {
            const payload = await generatePresentationFile({
                meetingId: this._qbrMeetingId,
                selectedSlideNumbers: this.selectedSlideNumberList
            });
            this.generatedFileUrl = payload?.fileUrl || '';
            this.generatedFileName = payload?.fileName || '';
            this.generatedContentDocumentId = payload?.contentDocumentId || '';
            this.generatedContentVersionId = payload?.contentVersionId || '';
            this.notifyFileOutputs();
            this.statusMessage = this.isChinese
                ? '簡報檔已生成，請點連結開啟。'
                : 'Presentation generated. Use the link to open it.';
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isGenerating = false;
        }
    }

    notifySelections() {
        this.selectedSlideNumbers = this.selectedSlideNumberList.join(',');
        this.notifyChange('selectedSlideNumbers', this.selectedSlideNumbers);
    }

    notifyFileOutputs() {
        this.notifyChange('generatedFileUrl', this.generatedFileUrl || '');
        this.notifyChange('generatedFileName', this.generatedFileName || '');
        this.notifyChange('generatedContentDocumentId', this.generatedContentDocumentId || '');
        this.notifyChange('generatedContentVersionId', this.generatedContentVersionId || '');
    }

    @api
    validate() {
        if (this.isBusy) {
            return {
                isValid: false,
                errorMessage: this.isChinese ? '系統仍在處理中，請稍候。' : 'Please wait for processing to finish.'
            };
        }
        if (!this._qbrMeetingId) {
            return {
                isValid: false,
                errorMessage: this.isChinese ? '找不到 QBR Meeting。' : 'QBR Meeting not found.'
            };
        }
        if (!this.selectedSlideNumberList.length) {
            return {
                isValid: false,
                errorMessage: this.isChinese ? '請至少選擇 1 個議題。' : 'Select at least 1 topic.'
            };
        }
        if (!this.generatedFileUrl) {
            return {
                isValid: false,
                errorMessage: this.isChinese ? '請先按「生成簡報檔」。' : 'Please generate the presentation file first.'
            };
        }
        return { isValid: true };
    }

    notifyChange(attributeName, value) {
        this.dispatchEvent(new FlowAttributeChangeEvent(attributeName, value));
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || String(error);
    }
}