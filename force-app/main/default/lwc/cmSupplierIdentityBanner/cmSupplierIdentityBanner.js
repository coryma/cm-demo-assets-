import { LightningElement, api, wire } from 'lwc';
import { getFieldValue, getRecord } from 'lightning/uiRecordApi';
import lang from '@salesforce/i18n/lang';
import locale from '@salesforce/i18n/locale';

const ROLES_FIELD = 'Account.CM_Account_Roles__c';
const FIELDS = [ROLES_FIELD];
const ROLE_ORDER = ['Customer', 'Supplier', 'Partner'];

const I18N = {
    zh: {
        cardTitle: '供應商身分',
        supplierStatus: '供應商狀態',
        currentRoles: '目前角色',
        isSupplier: '供應商',
        notSupplier: '非供應商',
        notSet: '未設定',
        roleSeparator: '、',
        roleDisplay: {
            Customer: '客戶',
            Supplier: '供應商',
            Partner: '合作夥伴'
        },
        unknownError: '未知錯誤'
    },
    en: {
        cardTitle: 'Supplier Identity',
        supplierStatus: 'Supplier Status',
        currentRoles: 'Current Roles',
        isSupplier: 'Supplier',
        notSupplier: 'Not Supplier',
        notSet: 'Not set',
        roleSeparator: ', ',
        roleDisplay: {
            Customer: 'Customer',
            Supplier: 'Supplier',
            Partner: 'Partner'
        },
        unknownError: 'Unknown error'
    }
};

function isTraditionalChineseLocale() {
    const normalizedLang = (lang || '').toLowerCase().replace('_', '-');
    const normalizedLocale = (locale || '').toLowerCase().replace('_', '-');
    const code = normalizedLang || normalizedLocale;

    return (
        code.startsWith('zh-hant') ||
        code.startsWith('zh-tw') ||
        code.startsWith('zh-hk') ||
        code.startsWith('zh-mo')
    );
}

export default class CmSupplierIdentityBanner extends LightningElement {
    @api recordId;
    roles = [];
    errorMessage = '';

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredAccount({ data, error }) {
        if (data) {
            this.errorMessage = '';
            this.roles = this.parseRoles(getFieldValue(data, ROLES_FIELD));
        } else if (error) {
            this.roles = [];
            this.errorMessage = this.reduceError(error);
        }
    }

    get i18n() {
        return isTraditionalChineseLocale() ? I18N.zh : I18N.en;
    }

    get isSupplier() {
        return this.roles.includes('Supplier');
    }

    get supplierStatus() {
        return this.isSupplier ? this.i18n.isSupplier : this.i18n.notSupplier;
    }

    get roleSummary() {
        if (!this.roles.length) {
            return this.i18n.notSet;
        }

        return this.roles
            .map((role) => this.i18n.roleDisplay[role] || role)
            .join(this.i18n.roleSeparator);
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
        return error?.body?.message || error?.message || this.i18n.unknownError;
    }
}