import { LightningElement, api } from 'lwc';
import LANG from '@salesforce/i18n/lang';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';

export default class CmQbrReviewBriefing extends LightningElement {
    @api attendeeStrategyHtml;
    @api swotHtml;
    @api keyTalkingPointsHtml;
    @api actionRequestsHtml;
    @api includeActionItems;
    @api includePricingAsks;
    @api includeRiskAlerts;

    connectedCallback() {
        if (this.includeActionItems === undefined || this.includeActionItems === null) {
            this.includeActionItems = true;
            this.notifyChange('includeActionItems', true);
        }
        if (this.includePricingAsks === undefined || this.includePricingAsks === null) {
            this.includePricingAsks = true;
            this.notifyChange('includePricingAsks', true);
        }
        if (this.includeRiskAlerts === undefined || this.includeRiskAlerts === null) {
            this.includeRiskAlerts = true;
            this.notifyChange('includeRiskAlerts', true);
        }
    }

    get isChinese() {
        return (LANG || '').toLowerCase().startsWith('zh');
    }

    get attendeeStrategyLabel() {
        return this.isChinese ? '與會者策略' : 'Attendee Strategy';
    }

    get swotLabel() {
        return this.isChinese ? '策略 SWOT' : 'Strategic SWOT';
    }

    get talkingPointsLabel() {
        return this.isChinese ? '關鍵談判重點' : 'Key Talking Points';
    }

    get actionRequestsLabel() {
        return this.isChinese ? '要求事項' : 'Action Requests';
    }

    get includeSectionLabel() {
        return this.isChinese ? '納入最終草稿' : 'Include In Final Package';
    }

    get includeActionItemsLabel() {
        return this.isChinese ? '納入行動事項' : 'Include action items';
    }

    get includePricingAsksLabel() {
        return this.isChinese ? '納入價格訴求' : 'Include pricing asks';
    }

    get includeRiskAlertsLabel() {
        return this.isChinese ? '納入風險提醒' : 'Include risk alerts';
    }

    handleActionItemsChange(event) {
        this.includeActionItems = event.target.checked;
        this.notifyChange('includeActionItems', this.includeActionItems);
    }

    handlePricingAsksChange(event) {
        this.includePricingAsks = event.target.checked;
        this.notifyChange('includePricingAsks', this.includePricingAsks);
    }

    handleRiskAlertsChange(event) {
        this.includeRiskAlerts = event.target.checked;
        this.notifyChange('includeRiskAlerts', this.includeRiskAlerts);
    }

    @api
    validate() {
        return { isValid: true };
    }

    notifyChange(attributeName, value) {
        this.dispatchEvent(new FlowAttributeChangeEvent(attributeName, value));
    }
}