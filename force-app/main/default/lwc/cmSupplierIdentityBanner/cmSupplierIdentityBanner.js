import { LightningElement, api, wire } from 'lwc';
import { getFieldValue, getRecord } from 'lightning/uiRecordApi';
import ACCOUNT_ROLES_FIELD from '@salesforce/schema/Account.CM_Account_Roles__c';

const FIELDS = [ACCOUNT_ROLES_FIELD];
const ROLE_ORDER = ['Customer', 'Supplier', 'Partner'];

const ROLE_DISPLAY = {
    Customer: '客戶 / Customer',
    Supplier: '供應商 / Supplier',
    Partner: '合作夥伴 / Partner'
};

export default class CmSupplierIdentityBanner extends LightningElement {
    @api recordId;
    roles = [];
    errorMessage = '';

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredAccount({ data, error }) {
        if (data) {
            this.errorMessage = '';
            this.roles = this.parseRoles(getFieldValue(data, ACCOUNT_ROLES_FIELD));
        } else if (error) {
            this.roles = [];
            this.errorMessage = this.reduceError(error);
        }
    }

    get isSupplier() {
        return this.roles.includes('Supplier');
    }

    get supplierStatus() {
        return this.isSupplier ? '供應商 / Supplier' : '非供應商 / Not Supplier';
    }

    get roleSummary() {
        if (!this.roles.length) {
            return '未設定 / Not set';
        }

        return this.roles
            .map((role) => ROLE_DISPLAY[role] || role)
            .join('、');
    }

    parseRoles(rawRoles) {
        if (!rawRoles) {
            return [];
        }

        const parsed = new Set(
            rawRoles
                .split(';')
                .map((item) => (item || '').trim())
                .filter((item) => item)
        );

        return ROLE_ORDER.filter((role) => parsed.has(role));
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unknown error';
    }
}
