import { LightningElement, api } from 'lwc';
import LANG from '@salesforce/i18n/lang';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';

const DEFAULT_CONTEXT = '模擬一批寄給供應商的跟進郵件，用於展示 QBR 後續對齊、交期追蹤與合約草稿往來的活動時間軸。';

export default class CmEmailSimulationSetup extends LightningElement {
    @api simulationContext;
    @api emailCount;
    @api startDate;
    @api endDate;
    @api simulationDirection;

    connectedCallback() {
        const today = new Date();
        if (!this.simulationContext) {
            this.simulationContext = DEFAULT_CONTEXT;
            this.notifyChange('simulationContext', this.simulationContext);
        }
        if (!this.emailCount) {
            this.emailCount = 3;
            this.notifyChange('emailCount', this.emailCount);
        }
        if (!this.endDate) {
            this.endDate = today.toISOString().slice(0, 10);
            this.notifyChange('endDate', this.endDate);
        }
        if (!this.simulationDirection) {
            this.simulationDirection = 'OUTBOUND_ONLY';
            this.notifyChange('simulationDirection', this.simulationDirection);
        }
        if (!this.startDate) {
            const start = new Date(today);
            start.setDate(start.getDate() - 30);
            this.startDate = start.toISOString().slice(0, 10);
            this.notifyChange('startDate', this.startDate);
        }
    }

    get isChinese() {
        return (LANG || '').toLowerCase().startsWith('zh');
    }

    get contextLabel() {
        return this.isChinese ? '模擬郵件背景資料' : 'Simulation Background';
    }

    get contextPlaceholder() {
        return this.isChinese
            ? '例如：模擬與供應商討論 QBR 後續 action items、合約草稿往來、交期追蹤與 VMI 上線確認。'
            : 'Example: simulate supplier follow-up emails for QBR action items, contract drafts, delivery tracking, and VMI go-live.';
    }

    get countLabel() {
        return this.isChinese ? '模擬比數' : 'Email Count';
    }

    get directionLabel() {
        return this.isChinese ? '郵件方向' : 'Simulation Direction';
    }

    get directionOptions() {
        return [
            { label: 'Outbound only', value: 'OUTBOUND_ONLY' },
            { label: 'Inbound only', value: 'INBOUND_ONLY' },
            { label: 'Inbound + Outbound 混合', value: 'MIXED' }
        ];
    }

    get startDateLabel() {
        return this.isChinese ? '期間起日' : 'Start Date';
    }

    get endDateLabel() {
        return this.isChinese ? '期間迄日' : 'End Date';
    }

    get helperText() {
        return this.isChinese
            ? '系統會依所選方向產生對應郵件草稿，再依設定期間分散建立多筆 EmailMessage。混合模式會同時建立 inbound 與 outbound。單次最多 10 筆。'
            : 'The system generates direction-aware drafts, then distributes EmailMessage records across the selected range. Mixed mode creates both inbound and outbound emails. Maximum 10 per run.';
    }

    handleContextChange(event) {
        this.simulationContext = event.detail.value;
        this.notifyChange('simulationContext', this.simulationContext);
    }

    handleCountChange(event) {
        const value = Number(event.detail.value);
        this.emailCount = Number.isNaN(value) ? null : value;
        this.notifyChange('emailCount', this.emailCount);
    }

    handleDirectionChange(event) {
        this.simulationDirection = event.detail.value;
        this.notifyChange('simulationDirection', this.simulationDirection);
    }

    handleStartDateChange(event) {
        this.startDate = event.detail.value;
        this.notifyChange('startDate', this.startDate);
    }

    handleEndDateChange(event) {
        this.endDate = event.detail.value;
        this.notifyChange('endDate', this.endDate);
    }

    @api
    validate() {
        const count = Number(this.emailCount);
        if (!this.simulationContext || !this.startDate || !this.endDate || Number.isNaN(count) || !this.simulationDirection) {
            return {
                isValid: false,
                errorMessage: this.isChinese
                    ? '背景資料、模擬比數、郵件方向、期間起日與期間迄日皆為必填。'
                    : 'Background, email count, direction, start date, and end date are required.'
            };
        }
        if (count < 1 || count > 10) {
            return {
                isValid: false,
                errorMessage: this.isChinese
                    ? '模擬比數需介於 1 到 10 之間。'
                    : 'Email count must be between 1 and 10.'
            };
        }
        if (this.endDate < this.startDate) {
            return {
                isValid: false,
                errorMessage: this.isChinese
                    ? '期間迄日不可早於期間起日。'
                    : 'End date cannot be earlier than start date.'
            };
        }
        return { isValid: true };
    }

    notifyChange(attributeName, value) {
        this.dispatchEvent(new FlowAttributeChangeEvent(attributeName, value));
    }
}