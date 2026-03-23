import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import ACCOUNT_NEWS_FIELD from '@salesforce/schema/Account.Account_News__c';
import RELATED_NEWS_FIELD from '@salesforce/schema/Account.Related_News__c';
import ACCOUNT_NEWS_TITLE from '@salesforce/label/c.CM_Latest_Account_News_Title';
import RELATED_NEWS_TITLE from '@salesforce/label/c.CM_Latest_Related_News_Title';

const FIELDS = [ACCOUNT_NEWS_FIELD, RELATED_NEWS_FIELD];

export default class CmAccountNewsSidebar extends LightningElement {
    @api recordId;

    accountItems = [];
    relatedItems = [];
    isLoading = true;
    labels = {
        accountTitle: ACCOUNT_NEWS_TITLE,
        relatedTitle: RELATED_NEWS_TITLE
    };

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredAccount({ data, error }) {
        this.isLoading = false;

        if (error || !data) {
            this.accountItems = [];
            this.relatedItems = [];
            return;
        }

        const accountPayload = data.fields?.Account_News__c?.value || '';
        const relatedPayload = data.fields?.Related_News__c?.value || '';
        this.accountItems = this.parseNewsPayload(accountPayload).slice(0, 5);
        this.relatedItems = this.parseNewsPayload(relatedPayload).slice(0, 5);
    }

    get hasAccountData() {
        return this.accountItems.length > 0;
    }

    get hasRelatedData() {
        return this.relatedItems.length > 0;
    }

    parseNewsPayload(payload) {
        if (!payload) {
            return [];
        }

        const lines = payload.split('\n');
        const entries = [];
        let current = null;

        lines.forEach((rawLine) => {
            const line = (rawLine || '').trim();
            if (line.startsWith('Title:')) {
                if (current?.title) {
                    entries.push(this.normalizeEntry(current));
                }
                current = {
                    title: line.substring('Title:'.length).trim(),
                    url: '',
                    publishedDate: ''
                };
            } else if (line.startsWith('URL:')) {
                if (!current) {
                    current = { title: '', url: '', publishedDate: '' };
                }
                current.url = line.substring('URL:'.length).trim();
            } else if (line.startsWith('Date:')) {
                if (!current) {
                    current = { title: '', url: '', publishedDate: '' };
                }
                current.publishedDate = line.substring('Date:'.length).trim();
            }
        });

        if (current?.title) {
            entries.push(this.normalizeEntry(current));
        }

        entries.sort((a, b) => b.timeValue - a.timeValue);
        return entries;
    }

    normalizeEntry(entry) {
        const parsed = Date.parse(entry.publishedDate);
        return {
            id: `${entry.title}-${entry.url}`,
            title: entry.title,
            url: entry.url,
            publishedDate: entry.publishedDate || 'N/A',
            timeValue: Number.isNaN(parsed) ? 0 : parsed
        };
    }
}