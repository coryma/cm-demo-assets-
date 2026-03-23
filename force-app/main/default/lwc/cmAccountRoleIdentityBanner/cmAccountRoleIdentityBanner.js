import { LightningElement, api, wire } from 'lwc';
import LANG from '@salesforce/i18n/lang';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import NAME_FIELD from '@salesforce/schema/Account.Name';
import ACCOUNT_ROLES_FIELD from '@salesforce/schema/Account.CM_Account_Roles__c';

const FIELDS = [NAME_FIELD, ACCOUNT_ROLES_FIELD];
const QUINCY_ALIAS = 'quincy';
const QUALCOMM_NAME = 'Qualcomm';

export default class CmAccountRoleIdentityBanner extends LightningElement {
    @api recordId;
    @api mode = 'header';

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    accountRecord;

    get isChinese() {
        return (LANG || '').toLowerCase().startsWith('zh');
    }

    get accountName() {
        return getFieldValue(this.accountRecord.data, NAME_FIELD) || '';
    }

    get normalizedAccountName() {
        return this.accountName.trim().toLowerCase();
    }

    get businessRoleRaw() {
        return getFieldValue(this.accountRecord.data, ACCOUNT_ROLES_FIELD) || '';
    }

    get businessRoles() {
        return this.businessRoleRaw
            .split(';')
            .map((value) => value.trim())
            .filter((value) => value.length > 0);
    }

    hasRole(roleName) {
        return this.businessRoles.includes(roleName);
    }

    get isCustomer() {
        return this.hasRole('Customer');
    }

    get isSupplier() {
        return this.hasRole('Supplier');
    }

    get isPartner() {
        return this.hasRole('Partner');
    }

    get showBanner() {
        return this.isCustomer || this.isSupplier || this.isPartner;
    }

    get isDetailMode() {
        return this.mode === 'detail';
    }

    get isQuincyAlias() {
        return this.normalizedAccountName === QUINCY_ALIAS;
    }

    get customerLabel() {
        return this.isChinese ? '客戶' : 'Customer';
    }

    get supplierLabel() {
        return this.isChinese ? '供應商' : 'Supplier';
    }

    get partnerLabel() {
        return this.isChinese ? '合作夥伴' : 'Partner';
    }

    get roleBadges() {
        const badges = [];
        if (this.isCustomer) {
            badges.push({
                key: 'customer',
                label: this.customerLabel,
                className: 'tag tag-customer'
            });
        }
        if (this.isSupplier) {
            badges.push({
                key: 'supplier',
                label: this.supplierLabel,
                className: 'tag tag-supplier'
            });
        }
        if (this.isPartner) {
            badges.push({
                key: 'partner',
                label: this.partnerLabel,
                className: 'tag tag-partner'
            });
        }
        return badges;
    }

    get roleAltText() {
        return this.roleBadges.map((badge) => badge.label).join('/');
    }

    get detailTitle() {
        if ((this.isCustomer && this.isSupplier) || (this.isCustomer && this.isPartner) || (this.isSupplier && this.isPartner)) {
            return this.isChinese ? '帳戶角色識別資訊' : 'Account Role Identity';
        }
        if (this.isCustomer) {
            return this.isChinese ? '客戶識別資訊' : 'Customer Identity';
        }
        if (this.isPartner) {
            return this.isChinese ? '合作夥伴識別資訊' : 'Partner Identity';
        }
        return this.isChinese ? '供應商識別資訊' : 'Supplier Identity';
    }

    get mainMessage() {
        if (this.isChinese) {
            if (this.isCustomer && this.isSupplier && this.isPartner) {
                if (this.isQuincyAlias) {
                    return `${this.accountName} 同時標示為客戶、供應商與合作夥伴帳戶（對外實體：${QUALCOMM_NAME}）。`;
                }
                return `${this.accountName} 同時標示為客戶、供應商與合作夥伴帳戶。`;
            }
            if (this.isCustomer && this.isSupplier) {
                if (this.isQuincyAlias) {
                    return `${this.accountName} 同時標示為客戶與供應商帳戶（對外實體：${QUALCOMM_NAME}）。`;
                }
                return `${this.accountName} 同時標示為客戶與供應商帳戶。`;
            }
            if (this.isCustomer && this.isPartner) {
                return `${this.accountName} 同時標示為客戶與合作夥伴帳戶。`;
            }
            if (this.isSupplier && this.isPartner) {
                if (this.isQuincyAlias) {
                    return `${this.accountName} 同時標示為供應商與合作夥伴帳戶（對外實體：${QUALCOMM_NAME}）。`;
                }
                return `${this.accountName} 同時標示為供應商與合作夥伴帳戶。`;
            }
            if (this.isCustomer) {
                return `${this.accountName} 已標示為客戶帳戶。`;
            }
            if (this.isPartner) {
                return `${this.accountName} 已標示為合作夥伴帳戶。`;
            }
            if (this.isQuincyAlias) {
                return `${this.accountName} 已標示為供應商（對外實體：${QUALCOMM_NAME}）。`;
            }
            return `${this.accountName} 已標示為供應商帳戶。`;
        }
        if (this.isCustomer && this.isSupplier && this.isPartner) {
            if (this.isQuincyAlias) {
                return `${this.accountName} is marked as customer, supplier, and partner (external entity: ${QUALCOMM_NAME}).`;
            }
            return `${this.accountName} is marked as customer, supplier, and partner.`;
        }
        if (this.isCustomer && this.isSupplier) {
            if (this.isQuincyAlias) {
                return `${this.accountName} is marked as both customer and supplier (external entity: ${QUALCOMM_NAME}).`;
            }
            return `${this.accountName} is marked as both customer and supplier.`;
        }
        if (this.isCustomer && this.isPartner) {
            return `${this.accountName} is marked as both customer and partner.`;
        }
        if (this.isSupplier && this.isPartner) {
            if (this.isQuincyAlias) {
                return `${this.accountName} is marked as both supplier and partner (external entity: ${QUALCOMM_NAME}).`;
            }
            return `${this.accountName} is marked as both supplier and partner.`;
        }
        if (this.isCustomer) {
            return `${this.accountName} is marked as a customer account.`;
        }
        if (this.isPartner) {
            return `${this.accountName} is marked as a partner account.`;
        }
        if (this.isQuincyAlias) {
            return `${this.accountName} is marked as a supplier account (external entity: ${QUALCOMM_NAME}).`;
        }
        return `${this.accountName} is marked as a supplier account.`;
    }

    get showMapping() {
        return this.isQuincyAlias && this.isSupplier;
    }

    get mappingMessage() {
        return this.isChinese ? '別名對應：Quincy = Qualcomm' : 'Alias mapping: Quincy = Qualcomm';
    }

    get detailHint() {
        if (this.isCustomer && this.isSupplier) {
            return this.isChinese
                ? '已啟用「詳細資訊」、「供應鏈分析」與「供應商資訊」頁籤。'
                : 'The "Details", "Supply Chain Analysis", and "Supplier Information" tabs are enabled.';
        }
        if (this.isSupplier) {
            return this.isChinese
                ? '已啟用「供應鏈分析」與「供應商資訊」頁籤。'
                : 'The "Supply Chain Analysis" and "Supplier Information" tabs are enabled.';
        }
        if (this.isCustomer || this.isPartner) {
            return this.isChinese ? '已啟用「詳細資訊」頁籤。' : 'The "Details" tab is enabled.';
        }
        return '';
    }

    get bannerClass() {
        return this.isDetailMode ? 'supplier-banner detail' : 'supplier-banner header';
    }

    get iconSize() {
        return this.isDetailMode ? 'small' : 'x-small';
    }
}