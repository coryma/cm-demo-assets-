import { LightningElement, api } from 'lwc';
import LANG from '@salesforce/i18n/lang';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import findLatestGeneratedMeeting from '@salesforce/apex/CMQbrMeetingPrepController.findLatestGeneratedMeeting';
import getEditableSlides from '@salesforce/apex/CMQbrMeetingPrepController.getEditableSlides';
import saveEditableSlides from '@salesforce/apex/CMQbrMeetingPrepController.saveEditableSlides';
import regenerateSupplierIntroFromFile from '@salesforce/apex/CMQbrMeetingPrepController.regenerateSupplierIntroFromFile';

const MODE_SETUP = 'setup';
const MODE_EDITOR = 'editor';
const MODE_SLIDE_ONE = 'slide1';
const MODE_SLIDE_TWO = 'slide2';
const MODE_SLIDE_THREE = 'slide3';
const MODE_SLIDE_FOUR = 'slide4';
const MODE_SLIDE_FIVE = 'slide5';
const MODE_SLIDE_SIX = 'slide6';
const MODE_SLIDE_SEVEN = 'slide7';
const MODE_SLIDE_EIGHT = 'slide8';
const MODE_SLIDE_NINE = 'slide9';
const EDITOR_SLIDE_NUMBERS = [1, 2, 3, 4, 5, 6, 7, 8, 9];

export default class CmQbrSetupPanel extends LightningElement {
    @api accountId;
    @api screenMode;
    @api quarter;
    @api meetingDate;
    @api meetingObjectives;
    @api outputMode;
    @api primaryFocus;
    @api focusDepartment;
    @api qbrMeetingId;
    @api slideOneHtml;
    @api slideTwoHtml;
    @api slideThreeHtml;
    @api slideFourHtml;
    @api slideFiveHtml;
    @api slideSixHtml;
    @api slideSevenHtml;
    @api slideEightHtml;
    @api slideNineHtml;

    pageOneTitle = '';
    pageTwoTitle = '';
    pageThreeTitle = '';
    pageFourTitle = '';
    pageFiveTitle = '';
    pageSixTitle = '';
    pageSevenTitle = '';
    pageEightTitle = '';
    pageNineTitle = '';
    pageOneRichText = '';
    pageTwoRichText = '';
    pageThreeRichText = '';
    pageFourRichText = '';
    pageFiveRichText = '';
    pageSixRichText = '';
    pageSevenRichText = '';
    pageEightRichText = '';
    pageNineRichText = '';
    pageFiveHasTable = false;
    pageSixHasTable = false;
    pageFiveColumns = [];
    pageSixColumns = [];
    pageFiveRows = [];
    pageSixRows = [];
    pageFiveSelectedRowKeys = [];
    pageSixSelectedRowKeys = [];
    pageFiveSelectedIndexes = [];
    pageSixSelectedIndexes = [];

    generatedMeetingName = '';
    generatedMeetingUrl = '';
    generatedAt = '';

    isLoadingDefault = false;
    isLoadingSlides = false;
    isSavingSlides = false;
    isRegeneratingSupplierSlide = false;

    statusMessage = '';
    errorMessage = '';

    uploadedSupplierFileId = '';
    uploadedSupplierFileName = '';

    slideOneDirty = false;
    slideTwoDirty = false;
    slideThreeDirty = false;
    slideFourDirty = false;
    slideFiveDirty = false;
    slideSixDirty = false;
    slideSevenDirty = false;
    slideEightDirty = false;
    slideNineDirty = false;

    activeSlideNumber = 1;

    _initialized = false;

    connectedCallback() {
        this.setCoreDefaults();
        this.hydrateFromFlowOutputs();
    }

    renderedCallback() {
        if (this._initialized) {
            return;
        }
        this._initialized = true;

        if (this.isSetupMode) {
            this.loadDefaultMeeting();
            return;
        }
        this.ensureSlidesLoaded();
    }

    get modeValue() {
        const mode = (this.screenMode || MODE_SETUP).toLowerCase();
        if (mode === MODE_SLIDE_ONE || mode === 'slide_1' || mode === 'slideone') {
            return MODE_SLIDE_ONE;
        }
        if (mode === MODE_SLIDE_TWO || mode === 'slide_2' || mode === 'slidetwo') {
            return MODE_SLIDE_TWO;
        }
        if (mode === MODE_SLIDE_THREE || mode === 'slide_3' || mode === 'slidethree') {
            return MODE_SLIDE_THREE;
        }
        if (mode === MODE_SLIDE_FOUR || mode === 'slide_4' || mode === 'slidefour') {
            return MODE_SLIDE_FOUR;
        }
        if (mode === MODE_SLIDE_FIVE || mode === 'slide_5' || mode === 'slidefive') {
            return MODE_SLIDE_FIVE;
        }
        if (mode === MODE_SLIDE_SIX || mode === 'slide_6' || mode === 'slidesix') {
            return MODE_SLIDE_SIX;
        }
        if (mode === MODE_SLIDE_SEVEN || mode === 'slide_7' || mode === 'slideseven') {
            return MODE_SLIDE_SEVEN;
        }
        if (mode === MODE_SLIDE_EIGHT || mode === 'slide_8' || mode === 'slideeight') {
            return MODE_SLIDE_EIGHT;
        }
        if (mode === MODE_SLIDE_NINE || mode === 'slide_9' || mode === 'slidenine') {
            return MODE_SLIDE_NINE;
        }
        if (mode === MODE_EDITOR) {
            return MODE_EDITOR;
        }
        return MODE_SETUP;
    }

    get isSetupMode() {
        return this.modeValue === MODE_SETUP;
    }

    get isEditorMode() {
        return this.modeValue === MODE_EDITOR;
    }

    isEditorSlide(slideNumber) {
        return this.isEditorMode && this.activeSlideNumber === slideNumber;
    }

    resolveSlideNumberFromMode() {
        if (this.modeValue === MODE_SLIDE_ONE) {
            return 1;
        }
        if (this.modeValue === MODE_SLIDE_TWO) {
            return 2;
        }
        if (this.modeValue === MODE_SLIDE_THREE) {
            return 3;
        }
        if (this.modeValue === MODE_SLIDE_FOUR) {
            return 4;
        }
        if (this.modeValue === MODE_SLIDE_FIVE) {
            return 5;
        }
        if (this.modeValue === MODE_SLIDE_SIX) {
            return 6;
        }
        if (this.modeValue === MODE_SLIDE_SEVEN) {
            return 7;
        }
        if (this.modeValue === MODE_SLIDE_EIGHT) {
            return 8;
        }
        if (this.modeValue === MODE_SLIDE_NINE) {
            return 9;
        }
        return 1;
    }

    get currentSlideNumber() {
        return this.isEditorMode ? this.activeSlideNumber : this.resolveSlideNumberFromMode();
    }

    get isSlideOneMode() {
        return this.modeValue === MODE_SLIDE_ONE || this.isEditorSlide(1);
    }

    get isSlideTwoMode() {
        return this.modeValue === MODE_SLIDE_TWO || this.isEditorSlide(2);
    }

    get isSlideThreeMode() {
        return this.modeValue === MODE_SLIDE_THREE || this.isEditorSlide(3);
    }

    get isSlideFourMode() {
        return this.modeValue === MODE_SLIDE_FOUR || this.isEditorSlide(4);
    }

    get isSlideFiveMode() {
        return this.modeValue === MODE_SLIDE_FIVE || this.isEditorSlide(5);
    }

    get isSlideSixMode() {
        return this.modeValue === MODE_SLIDE_SIX || this.isEditorSlide(6);
    }

    get isSlideSevenMode() {
        return this.modeValue === MODE_SLIDE_SEVEN || this.isEditorSlide(7);
    }

    get isSlideEightMode() {
        return this.modeValue === MODE_SLIDE_EIGHT || this.isEditorSlide(8);
    }

    get isSlideNineMode() {
        return this.modeValue === MODE_SLIDE_NINE || this.isEditorSlide(9);
    }

    get isChinese() {
        return (LANG || '').toLowerCase().startsWith('zh');
    }

    get quarterLabel() {
        return this.isChinese ? '季度' : 'Quarter';
    }

    get meetingDateLabel() {
        return this.isChinese ? '會議日期' : 'Meeting Date';
    }

    get setupTitle() {
        return this.isChinese ? '第 0 步：載入 QBR 預設內容' : 'Step 0: Load QBR Default Content';
    }

    get setupHint() {
        return this.isChinese
            ? '此頁不會重新生成內容，只會讀取 QBR Setup 已產生的預設草稿。'
            : 'This page does not generate content. It only loads default content from QBR Setup.';
    }

    get loadDefaultLabel() {
        return this.isChinese ? '載入預設內容' : 'Load Default Content';
    }

    get openMeetingLabel() {
        return this.isChinese ? '開啟 QBR Meeting' : 'Open QBR Meeting';
    }

    get editorTopicsTitle() {
        return this.isChinese ? '議題清單' : 'Topic List';
    }

    get editorTopicsHint() {
        return this.isChinese
            ? '請先在表格選擇議題，再在下方編修該議題內容。'
            : 'Select a topic from the table, then edit the content below.';
    }

    get topicTableColumns() {
        return [
            { label: '#', fieldName: 'slideNumber', type: 'number', initialWidth: 70 },
            { label: this.isChinese ? '議題' : 'Topic', fieldName: 'topicLabel', wrapText: true },
            { label: this.isChinese ? '當前標題' : 'Current Title', fieldName: 'slideTitle', wrapText: true },
            { label: this.isChinese ? '狀態' : 'Status', fieldName: 'statusLabel', initialWidth: 120 }
        ];
    }

    get topicRows() {
        return EDITOR_SLIDE_NUMBERS.map((slideNumber) => ({
            key: this.buildTopicRowKey(slideNumber),
            slideNumber,
            topicLabel: this.getTopicLabelBySlideNumber(slideNumber),
            slideTitle: this.getSlideTitleBySlideNumber(slideNumber),
            statusLabel: this.isSlideDirty(slideNumber)
                ? (this.isChinese ? '未儲存' : 'Unsaved')
                : (this.isChinese ? '已儲存' : 'Saved')
        }));
    }

    get selectedTopicRowKeys() {
        return [this.buildTopicRowKey(this.activeSlideNumber)];
    }

    get generatedAtLabel() {
        if (!this.generatedAt) {
            return '';
        }
        return this.isChinese ? `生成時間：${this.generatedAt}` : `Generated at: ${this.generatedAt}`;
    }

    get pageOneLabel() {
        return this.pageOneTitle || (this.isChinese ? '第 1 頁：公司簡介' : 'Slide 1: Company Intro');
    }

    get pageTwoLabel() {
        return this.pageTwoTitle || (this.isChinese ? '第 2 頁：供應商公司簡介' : 'Slide 2: Supplier Intro');
    }

    get pageThreeLabel() {
        return this.pageThreeTitle || (this.isChinese ? '第 3 頁：我方營運概況與變動' : 'Slide 3: Focus Company Operations');
    }

    get pageFourLabel() {
        return this.pageFourTitle || (this.isChinese ? '第 4 頁：對方公司營運概況與產能' : 'Slide 4: Root Account Operations');
    }

    get pageFiveLabel() {
        return this.pageFiveTitle || (this.isChinese ? '第 5 頁：上季 QBR 改善狀況追蹤' : 'Slide 5: QBR Action Tracking');
    }

    get pageSixLabel() {
        return this.pageSixTitle || (this.isChinese ? '第 6 頁：雙方商務指標回顧' : 'Slide 6: Business Scorecard');
    }

    get pageSevenLabel() {
        return this.pageSevenTitle || (this.isChinese ? '第 7 頁：品質問題討論' : 'Slide 7: Quality Discussion');
    }

    get pageEightLabel() {
        return this.pageEightTitle || (this.isChinese ? '第 8 頁：未來需求預測' : 'Slide 8: Demand Forecast');
    }

    get pageNineLabel() {
        return this.pageNineTitle || (this.isChinese ? '第 9 頁：重大議題商討' : 'Slide 9: Executive Summary');
    }

    get saveButtonLabel() {
        return this.isChinese ? '儲存議題' : 'Save Topic';
    }

    get copyButtonLabel() {
        return this.isChinese ? '複製內容' : 'Copy Content';
    }

    get titleInputLabel() {
        return this.isChinese ? '頁面標題' : 'Slide Title';
    }

    get supplierUploadLabel() {
        return this.isChinese ? '上傳檔案（重生第2頁）' : 'Upload File (Regenerate Slide 2)';
    }

    get supplierUploadHint() {
        if (!this.uploadedSupplierFileName) {
            return this.isChinese
                ? '支援 PDF、PPT、DOC、圖片。上傳後會重生第2頁內容。'
                : 'Supports PDF, PPT, DOC, images. Upload regenerates Slide 2.';
        }
        return this.isChinese
            ? `已上傳：${this.uploadedSupplierFileName}`
            : `Uploaded: ${this.uploadedSupplierFileName}`;
    }

    get supplierFileAccept() {
        return '.pdf,.ppt,.pptx,.doc,.docx,.txt,.png,.jpg,.jpeg';
    }

    get hasMeeting() {
        return !!this.qbrMeetingId;
    }

    get showSetupSummary() {
        return this.isSetupMode && this.hasMeeting;
    }

    get quarterOptions() {
        const currentYear = new Date().getFullYear();
        const years = [currentYear, currentYear + 1];
        const options = [];
        years.forEach((year) => {
            for (let quarter = 1; quarter <= 4; quarter += 1) {
                options.push({ label: `${year} Q${quarter}`, value: `${year} Q${quarter}` });
            }
        });
        return options;
    }

    get isBusy() {
        return (
            this.isLoadingDefault ||
            this.isLoadingSlides ||
            this.isSavingSlides ||
            this.isRegeneratingSupplierSlide
        );
    }

    get hasUnsavedChanges() {
        return (
            this.slideOneDirty ||
            this.slideTwoDirty ||
            this.slideThreeDirty ||
            this.slideFourDirty ||
            this.slideFiveDirty ||
            this.slideSixDirty ||
            this.slideSevenDirty ||
            this.slideEightDirty ||
            this.slideNineDirty
        );
    }

    get unsavedWarningMessage() {
        return this.isChinese
            ? '⚠ 有未儲存的議題，返回上一步將遺失變更。'
            : '⚠ Unsaved changes will be lost if you navigate back.';
    }

    get disableLoadDefault() {
        return this.isBusy || !this.accountId;
    }

    get disableSave() {
        return this.isBusy || !this.qbrMeetingId;
    }

    get disableCopyPageOne() {
        return this.isBusy || !this.pageOneRichText?.trim();
    }

    get disableCopyPageTwo() {
        return this.isBusy || !this.pageTwoRichText?.trim();
    }

    get disableCopyPageThree() {
        return this.isBusy || !this.pageThreeRichText?.trim();
    }

    get disableCopyPageFour() {
        return this.isBusy || !this.pageFourRichText?.trim();
    }

    get disableCopyPageFive() {
        return this.isBusy || !this.pageFiveRichText?.trim();
    }

    get disableCopyPageSix() {
        return this.isBusy || !this.pageSixRichText?.trim();
    }

    get disableCopyPageSeven() {
        return this.isBusy || !this.pageSevenRichText?.trim();
    }

    get disableCopyPageEight() {
        return this.isBusy || !this.pageEightRichText?.trim();
    }

    get disableCopyPageNine() {
        return this.isBusy || !this.pageNineRichText?.trim();
    }

    get spendingTableLabel() {
        return this.isChinese ? '可納入簡報的表格列（多選）' : 'Table Rows To Include (Multi-select)';
    }

    get spendingTableHint() {
        return this.isChinese
            ? '請勾選要保留在簡報中的列，儲存後會同步更新該頁內容。'
            : 'Select rows to keep in the slide. Save will apply the selection immediately.';
    }

    get noTableMessage() {
        return this.isChinese ? '此頁沒有可選的表格資料。' : 'No selectable table data on this slide.';
    }

    get pageFiveSelectionCountLabel() {
        return this.isChinese
            ? `已選 ${this.pageFiveSelectedRowKeys.length} 筆`
            : `${this.pageFiveSelectedRowKeys.length} selected`;
    }

    get pageSixSelectionCountLabel() {
        return this.isChinese
            ? `已選 ${this.pageSixSelectedRowKeys.length} 筆`
            : `${this.pageSixSelectedRowKeys.length} selected`;
    }

    getTopicLabelBySlideNumber(slideNumber) {
        if (slideNumber === 1) {
            return this.isChinese ? '我方公司簡介' : 'Focus Company Intro';
        }
        if (slideNumber === 2) {
            return this.isChinese ? '供應商公司簡介' : 'Supplier Intro';
        }
        if (slideNumber === 3) {
            return this.isChinese ? '我方營運概況暨新產品技術/組織變動' : 'Focus Company Operations & Changes';
        }
        if (slideNumber === 4) {
            return this.isChinese ? '供應商營運概況暨新產品技術/產能' : 'Supplier Operations & Capacity';
        }
        if (slideNumber === 5) {
            return this.isChinese ? '上季 QBR 改善狀況追蹤' : 'Last Quarter Improvement Tracking';
        }
        if (slideNumber === 6) {
            return this.isChinese ? '雙方商務指標回顧' : 'Business Scorecard Review';
        }
        if (slideNumber === 7) {
            return this.isChinese ? '品質問題討論' : 'Quality Issue Discussion';
        }
        if (slideNumber === 8) {
            return this.isChinese ? '未來預測需求' : 'Demand Forecast';
        }
        return this.isChinese ? '重大議題商討' : 'Executive Topic Discussion';
    }

    getSlideTitleBySlideNumber(slideNumber) {
        if (slideNumber === 1) {
            return this.pageOneTitle || this.getTopicLabelBySlideNumber(1);
        }
        if (slideNumber === 2) {
            return this.pageTwoTitle || this.getTopicLabelBySlideNumber(2);
        }
        if (slideNumber === 3) {
            return this.pageThreeTitle || this.getTopicLabelBySlideNumber(3);
        }
        if (slideNumber === 4) {
            return this.pageFourTitle || this.getTopicLabelBySlideNumber(4);
        }
        if (slideNumber === 5) {
            return this.pageFiveTitle || this.getTopicLabelBySlideNumber(5);
        }
        if (slideNumber === 6) {
            return this.pageSixTitle || this.getTopicLabelBySlideNumber(6);
        }
        if (slideNumber === 7) {
            return this.pageSevenTitle || this.getTopicLabelBySlideNumber(7);
        }
        if (slideNumber === 8) {
            return this.pageEightTitle || this.getTopicLabelBySlideNumber(8);
        }
        return this.pageNineTitle || this.getTopicLabelBySlideNumber(9);
    }

    isSlideDirty(slideNumber) {
        if (slideNumber === 1) {
            return this.slideOneDirty;
        }
        if (slideNumber === 2) {
            return this.slideTwoDirty;
        }
        if (slideNumber === 3) {
            return this.slideThreeDirty;
        }
        if (slideNumber === 4) {
            return this.slideFourDirty;
        }
        if (slideNumber === 5) {
            return this.slideFiveDirty;
        }
        if (slideNumber === 6) {
            return this.slideSixDirty;
        }
        if (slideNumber === 7) {
            return this.slideSevenDirty;
        }
        if (slideNumber === 8) {
            return this.slideEightDirty;
        }
        return this.slideNineDirty;
    }

    buildTopicRowKey(slideNumber) {
        return `TOPIC_${slideNumber}`;
    }

    setCoreDefaults() {
        if (!this.quarter) {
            const today = new Date();
            const quarterNumber = Math.floor(today.getMonth() / 3) + 1;
            this.quarter = `${today.getFullYear()} Q${quarterNumber}`;
            this.notifyChange('quarter', this.quarter);
        }
        if (!this.meetingDate) {
            this.meetingDate = new Date().toISOString().slice(0, 10);
            this.notifyChange('meetingDate', this.meetingDate);
        }
    }

    hydrateFromFlowOutputs() {
        this.pageOneRichText = this.slideOneHtml || '';
        this.pageTwoRichText = this.slideTwoHtml || '';
        this.pageThreeRichText = this.slideThreeHtml || '';
        this.pageFourRichText = this.slideFourHtml || '';
        this.pageFiveRichText = this.slideFiveHtml || '';
        this.pageSixRichText = this.slideSixHtml || '';
        this.pageSevenRichText = this.slideSevenHtml || '';
        this.pageEightRichText = this.slideEightHtml || '';
        this.pageNineRichText = this.slideNineHtml || '';
    }

    handleQuarterChange(event) {
        this.quarter = event.detail.value;
        this.notifyChange('quarter', this.quarter);
    }

    handleDateChange(event) {
        this.meetingDate = event.detail.value;
        this.notifyChange('meetingDate', this.meetingDate);
    }

    handleTopicRowSelection(event) {
        const selectedRows = event.detail?.selectedRows || [];
        if (!selectedRows.length) {
            return;
        }

        const targetSlideNumber = Number(selectedRows[0]?.slideNumber);
        if (!Number.isInteger(targetSlideNumber) || targetSlideNumber < 1 || targetSlideNumber > 9) {
            return;
        }
        if (targetSlideNumber === this.activeSlideNumber) {
            return;
        }
        if (this.isSlideDirty(this.activeSlideNumber)) {
            this.errorMessage = this.isChinese
                ? `第${this.activeSlideNumber}頁尚未儲存，請先儲存再切換議題。`
                : `Slide ${this.activeSlideNumber} has unsaved changes. Save before switching topics.`;
            return;
        }

        this.activeSlideNumber = targetSlideNumber;
        this.errorMessage = '';
    }

    async handleLoadDefault() {
        await this.loadDefaultMeeting();
    }

    async loadDefaultMeeting() {
        if (!this.accountId) {
            this.errorMessage = this.isChinese
                ? '缺少 Account Id，無法載入預設內容。'
                : 'Missing Account Id. Unable to load default content.';
            return;
        }

        this.isLoadingDefault = true;
        this.errorMessage = '';
        this.statusMessage = this.isChinese
            ? '正在讀取 QBR Setup 預設內容...'
            : 'Loading default content from QBR Setup...';

        try {
            const result = await findLatestGeneratedMeeting({
                rootAccountId: this.accountId,
                quarterOverride: this.quarter
            });

            this.qbrMeetingId = result?.meetingId || '';
            this.notifyChange('qbrMeetingId', this.qbrMeetingId);

            this.generatedMeetingName = result?.meetingName || '';
            this.generatedMeetingUrl = result?.meetingUrl || '';
            this.generatedAt = result?.generatedAt || '';

            if (!this.qbrMeetingId) {
                this.pageOneRichText = '';
                this.pageTwoRichText = '';
                this.pageThreeRichText = '';
                this.pageFourRichText = '';
                this.pageFiveRichText = '';
                this.pageSixRichText = '';
                this.pageSevenRichText = '';
                this.pageEightRichText = '';
                this.pageNineRichText = '';
                this.pageFiveHasTable = false;
                this.pageSixHasTable = false;
                this.pageFiveColumns = [];
                this.pageSixColumns = [];
                this.pageFiveRows = [];
                this.pageSixRows = [];
                this.pageFiveSelectedRowKeys = [];
                this.pageSixSelectedRowKeys = [];
                this.pageFiveSelectedIndexes = [];
                this.pageSixSelectedIndexes = [];
                this.slideOneDirty = false;
                this.slideTwoDirty = false;
                this.slideThreeDirty = false;
                this.slideFourDirty = false;
                this.slideFiveDirty = false;
                this.slideSixDirty = false;
                this.slideSevenDirty = false;
                this.slideEightDirty = false;
                this.slideNineDirty = false;
                this.activeSlideNumber = 1;
                this.syncSlideOutputs();
                this.statusMessage = result?.message || '';
                return;
            }

            this.statusMessage = result?.message || '';
            await this.loadEditableSlides();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
            this.statusMessage = '';
        } finally {
            this.isLoadingDefault = false;
        }
    }

    async ensureSlidesLoaded() {
        if (!this.qbrMeetingId) {
            return;
        }
        await this.loadEditableSlides();
    }

    async loadEditableSlides() {
        if (!this.qbrMeetingId) {
            return;
        }

        this.isLoadingSlides = true;
        try {
            const payload = await getEditableSlides({ meetingId: this.qbrMeetingId });
            this.applyEditablePayload(payload);
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoadingSlides = false;
        }
    }

    applyEditablePayload(payload) {
        this.pageOneTitle = payload?.pageOneTitle || '';
        this.pageTwoTitle = payload?.pageTwoTitle || '';
        this.pageThreeTitle = payload?.pageThreeTitle || '';
        this.pageFourTitle = payload?.pageFourTitle || '';
        this.pageFiveTitle = payload?.pageFiveTitle || '';
        this.pageSixTitle = payload?.pageSixTitle || '';
        this.pageSevenTitle = payload?.pageSevenTitle || '';
        this.pageEightTitle = payload?.pageEightTitle || '';
        this.pageNineTitle = payload?.pageNineTitle || '';
        this.pageOneRichText = payload?.pageOneRichText || '';
        this.pageTwoRichText = payload?.pageTwoRichText || '';
        this.pageThreeRichText = payload?.pageThreeRichText || '';
        this.pageFourRichText = payload?.pageFourRichText || '';
        this.pageFiveRichText = payload?.pageFiveRichText || '';
        this.pageSixRichText = payload?.pageSixRichText || '';
        this.pageSevenRichText = payload?.pageSevenRichText || '';
        this.pageEightRichText = payload?.pageEightRichText || '';
        this.pageNineRichText = payload?.pageNineRichText || '';
        this.pageFiveHasTable = !!payload?.pageFiveHasTable;
        this.pageSixHasTable = !!payload?.pageSixHasTable;
        this.configureTableSelection(
            'five',
            payload?.pageFiveTableHeaders || [],
            payload?.pageFiveAvailableRows || [],
            payload?.pageFiveSelectedRowIndexes || []
        );
        this.configureTableSelection(
            'six',
            payload?.pageSixTableHeaders || [],
            payload?.pageSixAvailableRows || [],
            payload?.pageSixSelectedRowIndexes || []
        );
        this.slideOneDirty = false;
        this.slideTwoDirty = false;
        this.slideThreeDirty = false;
        this.slideFourDirty = false;
        this.slideFiveDirty = false;
        this.slideSixDirty = false;
        this.slideSevenDirty = false;
        this.slideEightDirty = false;
        this.slideNineDirty = false;
        if (!Number.isInteger(this.activeSlideNumber) || this.activeSlideNumber < 1 || this.activeSlideNumber > 9) {
            this.activeSlideNumber = 1;
        }
        this.syncSlideOutputs();
    }

    syncSlideOutputs() {
        this.slideOneHtml = this.pageOneRichText || '';
        this.slideTwoHtml = this.pageTwoRichText || '';
        this.slideThreeHtml = this.pageThreeRichText || '';
        this.slideFourHtml = this.pageFourRichText || '';
        this.slideFiveHtml = this.pageFiveRichText || '';
        this.slideSixHtml = this.pageSixRichText || '';
        this.slideSevenHtml = this.pageSevenRichText || '';
        this.slideEightHtml = this.pageEightRichText || '';
        this.slideNineHtml = this.pageNineRichText || '';
        this.notifyChange('slideOneHtml', this.slideOneHtml);
        this.notifyChange('slideTwoHtml', this.slideTwoHtml);
        this.notifyChange('slideThreeHtml', this.slideThreeHtml);
        this.notifyChange('slideFourHtml', this.slideFourHtml);
        this.notifyChange('slideFiveHtml', this.slideFiveHtml);
        this.notifyChange('slideSixHtml', this.slideSixHtml);
        this.notifyChange('slideSevenHtml', this.slideSevenHtml);
        this.notifyChange('slideEightHtml', this.slideEightHtml);
        this.notifyChange('slideNineHtml', this.slideNineHtml);
    }

    handlePageOneRichTextChange(event) {
        this.pageOneRichText = event.detail?.value || '';
        this.slideOneDirty = true;
        this.syncSlideOutputs();
    }

    handlePageOneTitleChange(event) {
        this.pageOneTitle = event.detail?.value || '';
        this.slideOneDirty = true;
    }

    handlePageTwoRichTextChange(event) {
        this.pageTwoRichText = event.detail?.value || '';
        this.slideTwoDirty = true;
        this.syncSlideOutputs();
    }

    handlePageTwoTitleChange(event) {
        this.pageTwoTitle = event.detail?.value || '';
        this.slideTwoDirty = true;
    }

    handlePageThreeRichTextChange(event) {
        this.pageThreeRichText = event.detail?.value || '';
        this.slideThreeDirty = true;
        this.syncSlideOutputs();
    }

    handlePageThreeTitleChange(event) {
        this.pageThreeTitle = event.detail?.value || '';
        this.slideThreeDirty = true;
    }

    handlePageFourRichTextChange(event) {
        this.pageFourRichText = event.detail?.value || '';
        this.slideFourDirty = true;
        this.syncSlideOutputs();
    }

    handlePageFourTitleChange(event) {
        this.pageFourTitle = event.detail?.value || '';
        this.slideFourDirty = true;
    }

    handlePageFiveTitleChange(event) {
        this.pageFiveTitle = event.detail?.value || '';
        this.slideFiveDirty = true;
    }

    handlePageSixTitleChange(event) {
        this.pageSixTitle = event.detail?.value || '';
        this.slideSixDirty = true;
    }

    handlePageSevenRichTextChange(event) {
        this.pageSevenRichText = event.detail?.value || '';
        this.slideSevenDirty = true;
        this.syncSlideOutputs();
    }

    handlePageSevenTitleChange(event) {
        this.pageSevenTitle = event.detail?.value || '';
        this.slideSevenDirty = true;
    }

    handlePageEightRichTextChange(event) {
        this.pageEightRichText = event.detail?.value || '';
        this.slideEightDirty = true;
        this.syncSlideOutputs();
    }

    handlePageEightTitleChange(event) {
        this.pageEightTitle = event.detail?.value || '';
        this.slideEightDirty = true;
    }

    handlePageNineRichTextChange(event) {
        this.pageNineRichText = event.detail?.value || '';
        this.slideNineDirty = true;
        this.syncSlideOutputs();
    }

    handlePageNineTitleChange(event) {
        this.pageNineTitle = event.detail?.value || '';
        this.slideNineDirty = true;
    }

    handlePageFiveRowSelection(event) {
        const selectedRows = event.detail?.selectedRows || [];
        this.pageFiveSelectedIndexes = selectedRows
            .map((row) => Number(row.rowIndex))
            .filter((value) => Number.isInteger(value) && value >= 0);
        this.pageFiveSelectedRowKeys = this.pageFiveSelectedIndexes.map((index) => this.buildRowKey(index));
        this.slideFiveDirty = true;
    }

    handlePageSixRowSelection(event) {
        const selectedRows = event.detail?.selectedRows || [];
        this.pageSixSelectedIndexes = selectedRows
            .map((row) => Number(row.rowIndex))
            .filter((value) => Number.isInteger(value) && value >= 0);
        this.pageSixSelectedRowKeys = this.pageSixSelectedIndexes.map((index) => this.buildRowKey(index));
        this.slideSixDirty = true;
    }

    async handleCopyPageOne() {
        await this.copyCurrentPageContent(this.pageOneRichText, 1);
    }

    async handleCopyPageTwo() {
        await this.copyCurrentPageContent(this.pageTwoRichText, 2);
    }

    async handleCopyPageThree() {
        await this.copyCurrentPageContent(this.pageThreeRichText, 3);
    }

    async handleCopyPageFour() {
        await this.copyCurrentPageContent(this.pageFourRichText, 4);
    }

    async handleCopyPageFive() {
        await this.copyCurrentPageContent(this.pageFiveRichText, 5);
    }

    async handleCopyPageSix() {
        await this.copyCurrentPageContent(this.pageSixRichText, 6);
    }

    async handleCopyPageSeven() {
        await this.copyCurrentPageContent(this.pageSevenRichText, 7);
    }

    async handleCopyPageEight() {
        await this.copyCurrentPageContent(this.pageEightRichText, 8);
    }

    async handleCopyPageNine() {
        await this.copyCurrentPageContent(this.pageNineRichText, 9);
    }

    async handleSave() {
        if (!this.qbrMeetingId) {
            return;
        }

        const saveSlideOne = this.isSlideOneMode;
        const saveSlideTwo = this.isSlideTwoMode;
        const saveSlideThree = this.isSlideThreeMode;
        const saveSlideFour = this.isSlideFourMode;
        const saveSlideFive = this.isSlideFiveMode;
        const saveSlideSix = this.isSlideSixMode;
        const saveSlideSeven = this.isSlideSevenMode;
        const saveSlideEight = this.isSlideEightMode;
        const saveSlideNine = this.isSlideNineMode;
        const targetSlideNumber = this.currentSlideNumber;

        this.isSavingSlides = true;
        this.errorMessage = '';
        try {
            const payload = await saveEditableSlides({
                meetingId: this.qbrMeetingId,
                pageOneTitle: saveSlideOne ? this.pageOneTitle : null,
                pageTwoTitle: saveSlideTwo ? this.pageTwoTitle : null,
                pageThreeTitle: saveSlideThree ? this.pageThreeTitle : null,
                pageFourTitle: saveSlideFour ? this.pageFourTitle : null,
                pageFiveTitle: saveSlideFive ? this.pageFiveTitle : null,
                pageSixTitle: saveSlideSix ? this.pageSixTitle : null,
                pageSevenTitle: saveSlideSeven ? this.pageSevenTitle : null,
                pageEightTitle: saveSlideEight ? this.pageEightTitle : null,
                pageNineTitle: saveSlideNine ? this.pageNineTitle : null,
                pageOneRichText: saveSlideOne ? this.pageOneRichText : null,
                pageTwoRichText: saveSlideTwo ? this.pageTwoRichText : null,
                pageThreeRichText: saveSlideThree ? this.pageThreeRichText : null,
                pageFourRichText: saveSlideFour ? this.pageFourRichText : null,
                pageFiveSelectedRowIndexes: saveSlideFive ? this.pageFiveSelectedIndexes : null,
                pageSixSelectedRowIndexes: saveSlideSix ? this.pageSixSelectedIndexes : null,
                pageSevenRichText: saveSlideSeven ? this.pageSevenRichText : null,
                pageEightRichText: saveSlideEight ? this.pageEightRichText : null,
                pageNineRichText: saveSlideNine ? this.pageNineRichText : null
            });
            this.applyEditablePayload(payload);
            this.statusMessage = this.isChinese
                ? `第${targetSlideNumber}個議題已儲存。`
                : `Topic ${targetSlideNumber} saved.`;
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSavingSlides = false;
        }
    }

    async handleSupplierUploadFinished(event) {
        const files = event.detail?.files || [];
        if (!files.length || !this.qbrMeetingId) {
            return;
        }

        this.uploadedSupplierFileId = files[0].documentId;
        this.uploadedSupplierFileName = files[0].name || '';

        this.isRegeneratingSupplierSlide = true;
        this.errorMessage = '';
        this.statusMessage = this.isChinese
            ? '正在根據上傳檔案重生第2頁...'
            : 'Regenerating Slide 2 from uploaded file...';

        try {
            const payload = await regenerateSupplierIntroFromFile({
                meetingId: this.qbrMeetingId,
                fileId: this.uploadedSupplierFileId
            });
            this.applyEditablePayload(payload);
            this.statusMessage = this.isChinese
                ? '第2頁已依上傳檔案更新。'
                : 'Slide 2 updated from uploaded file.';
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isRegeneratingSupplierSlide = false;
        }
    }

    configureTableSelection(slideId, headers, rows, selectedIndexes) {
        const normalizedHeaders = Array.isArray(headers) ? headers : [];
        const normalizedRows = Array.isArray(rows) ? rows : [];
        const columns = normalizedHeaders.map((header, columnIndex) => ({
            label: header,
            fieldName: `c${columnIndex}`,
            wrapText: true
        }));
        const rowItems = normalizedRows.map((row, rowIndex) => this.buildTableRow(row, rowIndex));
        const normalizedSelectedIndexes = this.normalizeSelectedIndexes(selectedIndexes, rowItems.length);
        const selectedRowKeys = normalizedSelectedIndexes.map((index) => this.buildRowKey(index));

        if (slideId === 'five') {
            this.pageFiveColumns = columns;
            this.pageFiveRows = rowItems;
            this.pageFiveSelectedIndexes = normalizedSelectedIndexes;
            this.pageFiveSelectedRowKeys = selectedRowKeys;
            return;
        }

        this.pageSixColumns = columns;
        this.pageSixRows = rowItems;
        this.pageSixSelectedIndexes = normalizedSelectedIndexes;
        this.pageSixSelectedRowKeys = selectedRowKeys;
    }

    buildTableRow(row, rowIndex) {
        const normalizedCells = Array.isArray(row) ? row : [];
        const rowPayload = {
            id: this.buildRowKey(rowIndex),
            rowIndex
        };
        normalizedCells.forEach((cell, columnIndex) => {
            rowPayload[`c${columnIndex}`] = cell ?? '';
        });
        return rowPayload;
    }

    buildRowKey(index) {
        return `ROW_${index}`;
    }

    normalizeSelectedIndexes(values, maxRows) {
        if (!Number.isInteger(maxRows) || maxRows <= 0) {
            return [];
        }

        const candidates = Array.isArray(values) ? values : [];
        const normalized = [];
        const seen = new Set();
        candidates.forEach((value) => {
            const parsed = Number(value);
            if (!Number.isInteger(parsed)) {
                return;
            }
            if (parsed < 0 || parsed >= maxRows || seen.has(parsed)) {
                return;
            }
            seen.add(parsed);
            normalized.push(parsed);
        });

        if (!normalized.length) {
            for (let index = 0; index < maxRows; index += 1) {
                normalized.push(index);
            }
        }
        return normalized;
    }

    async copyCurrentPageContent(richTextHtml, pageNumber) {
        this.errorMessage = '';

        const plainText = this.toPlainText(richTextHtml);
        if (!plainText) {
            this.statusMessage = this.isChinese
                ? `第${pageNumber}頁沒有可複製的內容。`
                : `Slide ${pageNumber} has no content to copy.`;
            return;
        }

        try {
            await this.writeClipboard(plainText);
            this.statusMessage = this.isChinese
                ? `第${pageNumber}頁內容已複製到剪貼簿。`
                : `Slide ${pageNumber} content copied to clipboard.`;
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        }
    }

    toPlainText(richTextHtml) {
        if (!richTextHtml) {
            return '';
        }

        const normalizedHtml = String(richTextHtml)
            .replace(/<br\s*\/?>/gi, '\n')
            .replace(/<\/(p|div|li|h[1-6]|tr)>/gi, '\n')
            .replace(/<\/td>/gi, '\t')
            .replace(/<li>/gi, '• ');

        const container = document.createElement('div');
        container.innerHTML = normalizedHtml;

        const rawText = (container.textContent || container.innerText || '').replace(/\u00a0/g, ' ');
        const compactLines = rawText
            .split('\n')
            .map((line) => line.trim())
            .filter((line, index, lines) => line || lines[index - 1]);
        return compactLines.join('\n').trim();
    }

    writeClipboard(text) {
        if (navigator?.clipboard?.writeText) {
            return navigator.clipboard.writeText(text);
        }

        return new Promise((resolve, reject) => {
            const textarea = document.createElement('textarea');
            textarea.value = text;
            textarea.setAttribute('readonly', 'true');
            textarea.style.position = 'fixed';
            textarea.style.opacity = '0';
            document.body.appendChild(textarea);
            textarea.select();

            const copied = document.execCommand('copy');
            document.body.removeChild(textarea);
            if (copied) {
                resolve();
                return;
            }
            reject(new Error(this.isChinese ? '複製失敗，請手動複製。' : 'Copy failed. Please copy manually.'));
        });
    }

    @api
    validate() {
        this.setCoreDefaults();

        if (!this.quarter || !this.meetingDate) {
            return {
                isValid: false,
                errorMessage: this.isChinese
                    ? '季度與會議日期為必填。'
                    : 'Quarter and meeting date are required.'
            };
        }

        if (this.isBusy) {
            return {
                isValid: false,
                errorMessage: this.isChinese ? '系統仍在處理中，請稍候。' : 'Please wait until processing completes.'
            };
        }

        if (!this.qbrMeetingId) {
            return {
                isValid: false,
                errorMessage: this.isChinese
                    ? '找不到預設內容，請先到 QBR Setup 生成該季度資料。'
                    : 'No default content found. Please generate this quarter in QBR Setup first.'
            };
        }

        if (this.isEditorMode) {
            for (const slide of this._getSlideData()) {
                if (!slide.title?.trim()) {
                    return {
                        isValid: false,
                        errorMessage: this.isChinese
                            ? `第${slide.number}頁標題不可為空。`
                            : `Slide ${slide.number} title cannot be empty.`
                    };
                }
                if (slide.hasTable) {
                    if (!slide.selectedRowKeys.length) {
                        return {
                            isValid: false,
                            errorMessage: this.isChinese
                                ? `第${slide.number}頁至少需選擇 1 筆表格資料。`
                                : `Select at least 1 table row for Slide ${slide.number}.`
                        };
                    }
                } else if (!slide.richText?.trim()) {
                    return {
                        isValid: false,
                        errorMessage: this.isChinese
                            ? `第${slide.number}頁內容不可為空。`
                            : `Slide ${slide.number} content cannot be empty.`
                    };
                }
            }
            if (this.hasUnsavedChanges) {
                return {
                    isValid: false,
                    errorMessage: this.isChinese
                        ? '仍有未儲存內容，請先按「儲存議題」。'
                        : 'There are unsaved changes. Please click Save Topic first.'
                };
            }
        }

        if (!this.isSetupMode && !this.isEditorMode) {
            const currentSlide = this._getSlideData().find((s) => s.number === this.currentSlideNumber);
            if (currentSlide) {
                if (currentSlide.hasTable) {
                    if (!currentSlide.selectedRowKeys.length) {
                        return {
                            isValid: false,
                            errorMessage: this.isChinese
                                ? `第${currentSlide.number}頁至少需選擇 1 筆表格資料。`
                                : `Select at least 1 table row for Slide ${currentSlide.number}.`
                        };
                    }
                } else if (!currentSlide.richText?.trim()) {
                    return {
                        isValid: false,
                        errorMessage: this.isChinese
                            ? `第${currentSlide.number}頁內容不可為空。`
                            : `Slide ${currentSlide.number} content cannot be empty.`
                    };
                }
                if (currentSlide.dirty) {
                    return {
                        isValid: false,
                        errorMessage: this.isChinese
                            ? `第${currentSlide.number}頁尚未儲存，請先按「儲存議題」。`
                            : `Slide ${currentSlide.number} has unsaved changes. Please click Save Topic.`
                    };
                }
            }
        }

        this.syncSlideOutputs();
        return { isValid: true };
    }

    _getSlideData() {
        return [
            { number: 1, title: this.pageOneTitle, richText: this.pageOneRichText, dirty: this.slideOneDirty, hasTable: false, selectedRowKeys: [] },
            { number: 2, title: this.pageTwoTitle, richText: this.pageTwoRichText, dirty: this.slideTwoDirty, hasTable: false, selectedRowKeys: [] },
            { number: 3, title: this.pageThreeTitle, richText: this.pageThreeRichText, dirty: this.slideThreeDirty, hasTable: false, selectedRowKeys: [] },
            { number: 4, title: this.pageFourTitle, richText: this.pageFourRichText, dirty: this.slideFourDirty, hasTable: false, selectedRowKeys: [] },
            { number: 5, title: this.pageFiveTitle, richText: null, dirty: this.slideFiveDirty, hasTable: this.pageFiveHasTable, selectedRowKeys: this.pageFiveSelectedRowKeys },
            { number: 6, title: this.pageSixTitle, richText: null, dirty: this.slideSixDirty, hasTable: this.pageSixHasTable, selectedRowKeys: this.pageSixSelectedRowKeys },
            { number: 7, title: this.pageSevenTitle, richText: this.pageSevenRichText, dirty: this.slideSevenDirty, hasTable: false, selectedRowKeys: [] },
            { number: 8, title: this.pageEightTitle, richText: this.pageEightRichText, dirty: this.slideEightDirty, hasTable: false, selectedRowKeys: [] },
            { number: 9, title: this.pageNineTitle, richText: this.pageNineRichText, dirty: this.slideNineDirty, hasTable: false, selectedRowKeys: [] }
        ];
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