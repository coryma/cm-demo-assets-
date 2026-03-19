import { LightningElement, api } from 'lwc';
import LANG from '@salesforce/i18n/lang';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';

const DECISION_USE_CURRENT = 'USE_CURRENT';
const DECISION_REGENERATE = 'REGENERATE';
const DECISION_SKIP = 'SKIP';

export default class CmQbrSwotDecision extends LightningElement {
    @api hasAccountPlan;
    @api hasExistingSwot;
    @api isCompleteSwot;
    @api canGenerate;
    @api accountPlanName;
    @api lastModifiedLabel;
    @api statusMessage;
    @api strengthsPreviewHtml;
    @api weaknessesPreviewHtml;
    @api opportunitiesPreviewHtml;
    @api threatsPreviewHtml;
    @api swotDecision;
    @api editedStrengthsHtml;
    @api editedWeaknessesHtml;
    @api editedOpportunitiesHtml;
    @api editedThreatsHtml;

    connectedCallback() {
        this.initializeEditors();
        if (this.hasExistingSwot && this.swotDecision === DECISION_REGENERATE) {
            this.swotDecision = DECISION_USE_CURRENT;
            this.notifyChange('swotDecision', this.swotDecision);
        }
        if (!this.swotDecision) {
            this.swotDecision = this.defaultDecision;
            this.notifyChange('swotDecision', this.swotDecision);
        }
    }

    get isChinese() {
        return (LANG || '').toLowerCase().startsWith('zh');
    }

    get defaultDecision() {
        if (!this.hasAccountPlan) {
            return DECISION_SKIP;
        }
        if (this.hasExistingSwot) {
            return DECISION_USE_CURRENT;
        }
        if (this.canGenerate) {
            return DECISION_REGENERATE;
        }
        return DECISION_SKIP;
    }

    get decisionOptions() {
        if (!this.hasAccountPlan) {
            return [
                {
                    label: this.isChinese ? '略過 SWOT' : 'Skip SWOT',
                    value: DECISION_SKIP
                }
            ];
        }

        if (this.hasExistingSwot) {
            return [
                {
                    label: this.isChinese ? '使用目前 SWOT' : 'Use current SWOT',
                    value: DECISION_USE_CURRENT
                },
                {
                    label: this.isChinese ? '重新產生並覆蓋 SWOT' : 'Regenerate and overwrite SWOT',
                    value: DECISION_REGENERATE
                },
                {
                    label: this.isChinese ? '本次不使用 SWOT' : 'Skip SWOT for this QBR',
                    value: DECISION_SKIP
                }
            ];
        }

        return [
            {
                label: this.isChinese ? '立即產生 SWOT' : 'Generate SWOT now',
                value: DECISION_REGENERATE
            },
            {
                label: this.isChinese ? '略過，直接繼續' : 'Skip and continue',
                value: DECISION_SKIP
            }
        ];
    }

    get headerText() {
        return this.isChinese ? 'SWOT 檢查' : 'SWOT Check';
    }

    get modeLabel() {
        return this.isChinese ? 'SWOT 處理方式' : 'SWOT Handling';
    }

    get planLabel() {
        return this.isChinese ? '客戶經營計劃' : 'Account Plan';
    }

    get lastUpdatedLabel() {
        return this.isChinese ? '最後更新' : 'Last Updated';
    }

    get previewTitle() {
        return this.isChinese ? '目前 SWOT 預覽' : 'Current SWOT Preview';
    }

    get strengthsLabel() {
        return this.isChinese ? '優勢' : 'Strengths';
    }

    get strengthsEditorLabel() {
        return this.isChinese ? '優勢內容' : 'Strengths Content';
    }

    get strengthsHelpText() {
        return this.isChinese
            ? '填寫目前合作關係中可作為談判籌碼、技術優勢或供應優勢的內容。'
            : 'Capture the negotiation leverage, technical advantages, or supply advantages in the current relationship.';
    }

    get weaknessesLabel() {
        return this.isChinese ? '劣勢' : 'Weaknesses';
    }

    get weaknessesEditorLabel() {
        return this.isChinese ? '劣勢內容' : 'Weaknesses Content';
    }

    get weaknessesHelpText() {
        return this.isChinese
            ? '填寫目前的限制、依賴風險、成本壓力或議價弱點。'
            : 'Capture current constraints, dependency risks, cost pressure, or negotiation disadvantages.';
    }

    get opportunitiesLabel() {
        return this.isChinese ? '機會' : 'Opportunities';
    }

    get opportunitiesEditorLabel() {
        return this.isChinese ? '機會內容' : 'Opportunities Content';
    }

    get opportunitiesHelpText() {
        return this.isChinese
            ? '填寫本次 QBR 可爭取的利益，例如價格、VMI、allocation 或合作擴張機會。'
            : 'Capture the upside this QBR can unlock, such as pricing, VMI, allocation, or expansion opportunities.';
    }

    get threatsLabel() {
        return this.isChinese ? '威脅' : 'Threats';
    }

    get threatsEditorLabel() {
        return this.isChinese ? '威脅內容' : 'Threats Content';
    }

    get threatsHelpText() {
        return this.isChinese
            ? '填寫需要防範的供應、地緣政治、交期或競爭風險。'
            : 'Capture the supply, geopolitical, lead-time, or competitive risks that need active mitigation.';
    }

    get overwriteWarningText() {
        if (this.swotDecision !== DECISION_REGENERATE || !this.hasAccountPlan) {
            return '';
        }
        return this.isChinese
            ? '注意：重新產生將覆蓋目前客戶經營計劃中的 SWOT 欄位內容。'
            : 'Warning: Regenerating SWOT will overwrite the current Account Plan SWOT fields.';
    }

    handleDecisionChange(event) {
        this.swotDecision = event.detail.value;
        this.notifyChange('swotDecision', this.swotDecision);
    }

    handleStrengthsChange(event) {
        this.editedStrengthsHtml = event.detail.value;
        this.notifyChange('editedStrengthsHtml', this.editedStrengthsHtml);
    }

    handleWeaknessesChange(event) {
        this.editedWeaknessesHtml = event.detail.value;
        this.notifyChange('editedWeaknessesHtml', this.editedWeaknessesHtml);
    }

    handleOpportunitiesChange(event) {
        this.editedOpportunitiesHtml = event.detail.value;
        this.notifyChange('editedOpportunitiesHtml', this.editedOpportunitiesHtml);
    }

    handleThreatsChange(event) {
        this.editedThreatsHtml = event.detail.value;
        this.notifyChange('editedThreatsHtml', this.editedThreatsHtml);
    }

    @api
    validate() {
        if (!this.swotDecision) {
            return {
                isValid: false,
                errorMessage: this.isChinese ? '請先選擇 SWOT 處理方式。' : 'Choose a SWOT handling option.'
            };
        }
        return { isValid: true };
    }

    notifyChange(attributeName, value) {
        this.dispatchEvent(new FlowAttributeChangeEvent(attributeName, value));
    }

    initializeEditors() {
        if (this.editedStrengthsHtml === undefined || this.editedStrengthsHtml === null) {
            this.editedStrengthsHtml = this.strengthsPreviewHtml || '';
            this.notifyChange('editedStrengthsHtml', this.editedStrengthsHtml);
        }
        if (this.editedWeaknessesHtml === undefined || this.editedWeaknessesHtml === null) {
            this.editedWeaknessesHtml = this.weaknessesPreviewHtml || '';
            this.notifyChange('editedWeaknessesHtml', this.editedWeaknessesHtml);
        }
        if (this.editedOpportunitiesHtml === undefined || this.editedOpportunitiesHtml === null) {
            this.editedOpportunitiesHtml = this.opportunitiesPreviewHtml || '';
            this.notifyChange('editedOpportunitiesHtml', this.editedOpportunitiesHtml);
        }
        if (this.editedThreatsHtml === undefined || this.editedThreatsHtml === null) {
            this.editedThreatsHtml = this.threatsPreviewHtml || '';
            this.notifyChange('editedThreatsHtml', this.editedThreatsHtml);
        }
    }
}