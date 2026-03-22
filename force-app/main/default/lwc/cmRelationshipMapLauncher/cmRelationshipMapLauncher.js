import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import ACCOUNT_ID_FIELD from '@salesforce/schema/AccountPlan.AccountId';

const LABELS = {
    en: {
        title: 'Relationship Map',
        description: 'Visualize key stakeholders for this account.',
        button: 'Open Relationship Map'
    },
    zh: {
        title: '關係圖',
        description: '視覺化此帳戶的主要利害關係人。',
        button: '開啟關係圖'
    }
};

export default class CmRelationshipMapLauncher extends NavigationMixin(LightningElement) {
    @api recordId;
    @api language = 'zh';

    @wire(getRecord, { recordId: '$recordId', fields: [ACCOUNT_ID_FIELD] })
    accountPlan;

    get accountId() {
        return getFieldValue(this.accountPlan.data, ACCOUNT_ID_FIELD);
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

    handleOpen() {
        if (!this.accountId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.accountId,
                objectApiName: 'Account',
                actionName: 'view'
            }
        });
    }
}
