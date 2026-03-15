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

export default class CmAccountRoleIdentityBanner extends LightningElement {
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

    get isCustomer() {
        return this.roles.includes('Customer');
    }

    get isSupplier() {
        return this.roles.includes('Supplier');
    }

    get isPartner() {
        return this.roles.includes('Partner');
    }

    get badgeItems() {
        return this.roles.map((role) => ({
            key: role,
            label: ROLE_DISPLAY[role] || role
        }));
    }

    get hasBadges() {
        return this.badgeItems.length > 0;
    }

    get summaryLabel() {
        if (this.isCustomer && this.isSupplier) {
            return '兩者皆是 / Both';
        }
        if (this.isCustomer) {
            return '客戶 / Customer';
        }
        if (this.isSupplier) {
            return '供應商 / Supplier';
        }
        if (this.isPartner) {
            return '合作夥伴 / Partner';
        }
        return '未設定 / Not set';
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
