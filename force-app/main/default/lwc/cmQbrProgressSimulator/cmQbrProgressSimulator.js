import { LightningElement, api } from 'lwc';
import LANG from '@salesforce/i18n/lang';
import { FlowNavigationNextEvent } from 'lightning/flowSupport';

const DEFAULT_ADVANCE_MS = 1200;

export default class CmQbrProgressSimulator extends LightningElement {
    @api titleText;
    @api autoAdvanceMs;
    @api availableActions = [];

    progressValue = 12;
    hasStarted = false;
    intervalId;
    timeoutId;

    get isChinese() {
        return (LANG || '').toLowerCase().startsWith('zh');
    }

    get displayTitle() {
        if (this.titleText) {
            return this.titleText;
        }
        return this.isChinese ? 'AI 正在處理，請稍候...' : 'AI is working. Please wait...';
    }

    get subtitleText() {
        return this.isChinese
            ? '系統會在完成後自動進入下一步。'
            : 'The flow will continue automatically when this step is ready.';
    }

    get progressStyle() {
        return `width:${this.progressValue}%;`;
    }

    renderedCallback() {
        if (this.hasStarted) {
            return;
        }
        this.hasStarted = true;
        this.startProgress();
    }

    disconnectedCallback() {
        this.clearTimers();
    }

    @api
    validate() {
        return { isValid: true };
    }

    startProgress() {
        const duration = Number(this.autoAdvanceMs) > 0 ? Number(this.autoAdvanceMs) : DEFAULT_ADVANCE_MS;
        const intervalMs = 120;
        const steps = Math.max(1, Math.floor(duration / intervalMs));
        const increment = Math.max(1, Math.floor(78 / steps));

        this.intervalId = setInterval(() => {
            if (this.progressValue < 90) {
                this.progressValue = Math.min(90, this.progressValue + increment);
            }
        }, intervalMs);

        this.timeoutId = setTimeout(() => {
            this.progressValue = 100;
            this.clearTimers();
            if ((this.availableActions || []).includes('NEXT')) {
                this.dispatchEvent(new FlowNavigationNextEvent());
            }
        }, duration);
    }

    clearTimers() {
        if (this.intervalId) {
            clearInterval(this.intervalId);
            this.intervalId = null;
        }
        if (this.timeoutId) {
            clearTimeout(this.timeoutId);
            this.timeoutId = null;
        }
    }
}