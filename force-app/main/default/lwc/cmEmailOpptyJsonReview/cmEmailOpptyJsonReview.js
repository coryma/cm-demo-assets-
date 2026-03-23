import { LightningElement, api, track } from 'lwc';

export default class CmEmailOpptyJsonReview extends LightningElement {
    @api jsonText = '';
    @api emailSubject = '';
    @api emailBody = '';
    @api summary = '';

    @api editedJson = '';

    @track opptyLines = [];
    originalObject;
    accountName;

    connectedCallback() {
        this.initialize();
    }

    initialize() {
        this.editedJson = this.jsonText || '';
        try {
            this.originalObject = this.jsonText ? JSON.parse(this.jsonText) : {};
        } catch (e) {
            this.originalObject = {};
        }

        this.accountName = this.resolveAccountName(this.originalObject);

        const items = Array.isArray(this.originalObject?.line_items)
            ? this.originalObject.line_items.slice(0, 5)
            : [];

        this.opptyLines = items.map((item, idx) => this.mapLine(item, idx));

        // If no items, still prepare an empty array for display
        if (this.opptyLines.length === 0) {
            this.opptyLines = null;
        } else {
            this.updateEditedJson();
        }
    }

    mapLine(item, idx) {
        const qty = this.toNumber(item?.quantity);
        const unitPrice = this.extractUnitPrice(item);
        const currency = this.extractCurrency(item);
        const productName = this.buildName(item) || `Item ${idx + 1}`;
        const closeDate = this.normalizeDate(item?.close_date) || this.defaultCloseDate();
        const defaultName = this.computeOpptyName(productName, qty, unitPrice, currency, idx);

        return {
            key: `line-${idx}`,
            name: item?.opportunity_name || item?.name || defaultName,
            quantity: Number.isFinite(qty) ? qty : '',
            unitPrice: Number.isFinite(unitPrice) ? unitPrice : '',
            currency,
            closeDate: closeDate,
            productName
        };
    }

    buildName(item) {
        const manufacturer = (item?.manufacturer || '').trim();
        const part = (item?.part_number || '').trim();
        const candidate = [manufacturer, part].filter(Boolean).join(' ');
        return candidate || null;
    }

    computeOpptyName(productName, qty, unitPrice, currency, idx) {
        const account = this.accountName || '';
        const product = productName || `Item ${idx + 1}`;
        const total = (Number.isFinite(qty) && Number.isFinite(unitPrice)) ? (qty * unitPrice) : null;
        const totalLabel = Number.isFinite(total)
            ? `${currency || 'USD'} ${total.toFixed(2)}`
            : 'N/A';

        const parts = [account, product, totalLabel].filter((p) => p && p.trim() !== '');
        return parts.length > 0 ? parts.join(' - ') : `Opportunity ${idx + 1}`;
    }

    extractUnitPrice(item) {
        if (!item) return null;
        if (item.target_price && typeof item.target_price === 'object') {
            const val = item.target_price.value;
            return this.toNumber(val);
        }
        return this.toNumber(item.target_price);
    }

    extractCurrency(item) {
        if (!item) return null;
        if (item.target_price && typeof item.target_price === 'object') {
            return (item.target_price.currency || '').trim() || null;
        }
        return null;
    }

    normalizeDate(raw) {
        if (!raw) return '';
        const str = String(raw).slice(0, 10);
        const valid = /^\d{4}-\d{2}-\d{2}$/.test(str);
        if (valid) return str;
        return '';
    }

    defaultCloseDate() {
        const today = new Date();
        today.setDate(today.getDate() + 30);
        return today.toISOString().slice(0, 10);
    }

    handleFieldChange(event) {
        const key = event.target.dataset.key;
        const field = event.target.name;
        const value = event.target.value;

        this.opptyLines = (this.opptyLines || []).map((line) => {
            if (line.key === key) {
                const updated = { ...line };
                if (field === 'quantity' || field === 'unitPrice') {
                    updated[field] = this.toNumber(value);
                    updated.name = this.computeOpptyName(
                        this.findLineByKey(key).productName,
                        updated.quantity,
                        updated.unitPrice,
                        updated.currency,
                        this.extractIndexFromKey(key)
                    );
                } else {
                    updated[field] = value;
                }
                return updated;
            }
            return line;
        });

        this.updateEditedJson();
    }

    updateEditedJson() {
        const clone = this.originalObject ? JSON.parse(JSON.stringify(this.originalObject)) : {};
        const items = Array.isArray(clone.line_items) ? clone.line_items : [];

        if (this.opptyLines) {
            for (let i = 0; i < this.opptyLines.length; i++) {
                const uiLine = this.opptyLines[i];
                if (!items[i]) {
                    items[i] = {};
                }
                items[i].opportunity_name = uiLine.name;
                items[i].quantity = uiLine.quantity;
                items[i].close_date = uiLine.closeDate || null;

                const currency = uiLine.currency || items[i]?.target_price?.currency || 'USD';
                items[i].target_price = {
                    value: uiLine.unitPrice,
                    currency: currency
                };
            }
        }

        clone.line_items = items;
        this.editedJson = JSON.stringify(clone, null, 2);
    }

    resolveAccountName(obj) {
        if (!obj || typeof obj !== 'object') return null;
        const customer = obj.customer_info || {};
        const company = (customer.company_context || '').trim();
        const name = (customer.name || '').trim();
        return company || name || null;
    }

    findLineByKey(key) {
        if (!this.opptyLines) return {};
        return this.opptyLines.find((l) => l.key === key) || {};
    }

    extractIndexFromKey(key) {
        if (!key) return 0;
        const m = key.match(/line-(\d+)/);
        return m ? parseInt(m[1], 10) : 0;
    }

    toNumber(value) {
        const num = Number(value);
        return Number.isFinite(num) ? num : null;
    }
}