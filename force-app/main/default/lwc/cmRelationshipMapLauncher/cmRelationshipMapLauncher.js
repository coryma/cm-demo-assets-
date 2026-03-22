import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import ACCOUNT_ID_FIELD from '@salesforce/schema/AccountPlan.AccountId';

const ACCOUNT_ID_PREFIX = '001';

const LABELS = {
    en: {
        title: 'Relationship Map',
        description: 'Open the relationship map view for this account.',
        button: 'Open Relationship Map'
    },
    zh: {
        title: '關係圖',
        description: '開啟此帳戶的關係圖視圖。',
        button: '開啟關係圖'
    }
};

export default class CmRelationshipMapLauncher extends NavigationMixin(LightningElement) {
    @api recordId;
    @api language = 'zh';
    @api relationshipMapActionApiName = 'Account.SalesAIRelationshipGraph';

    @wire(getRecord, { recordId: '$accountPlanRecordId', fields: [ACCOUNT_ID_FIELD] })
    accountPlan;

    get isAccountRecord() {
        return typeof this.recordId === 'string' && this.recordId.startsWith(ACCOUNT_ID_PREFIX);
    }

    get accountPlanRecordId() {
        return this.isAccountRecord ? undefined : this.recordId;
    }

    get accountId() {
        if (this.isAccountRecord) {
            return this.recordId;
        }
        return this.accountPlan?.data ? getFieldValue(this.accountPlan.data, ACCOUNT_ID_FIELD) : undefined;
    }

    get isOpenDisabled() {
        return !this.accountId;
    }

    get labels() {
        return this.language === 'en' ? LABELS.en : LABELS.zh;
    }

    get cardTitle() {
        return this.labels.title;
    }

    get cardDescription() {
        return this.labels.description;
    }

    get buttonLabel() {
        return this.labels.button;
    }

    get primaryActionApiName() {
        return (this.relationshipMapActionApiName || '').trim() || 'Account.SalesAIRelationshipGraph';
    }

    handleOpen() {
        if (!this.accountId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__quickAction',
            attributes: {
                apiName: this.primaryActionApiName
            },
            state: {
                recordId: this.accountId
            }
        });
    }

}