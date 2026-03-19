// cmBusinessCardOcrUpload.js
import { LightningElement, api, track } from 'lwc';
import initBatchAndPersist from '@salesforce/apex/CM_BusinessCard_Controller.initBatchAndPersist';
import getSeedVersionIdsByBatch from '@salesforce/apex/CM_BusinessCard_Controller.getSeedVersionIdsByBatch';
import LABEL_UPLOAD_TITLE from '@salesforce/label/c.CM_BC_Upload_Title';
import LABEL_UPLOAD_LABEL from '@salesforce/label/c.CM_BC_Upload_Label';
import LABEL_UPLOAD_STATUS from '@salesforce/label/c.CM_BC_Upload_Status';
import LABEL_ERR_UNKNOWN from '@salesforce/label/c.CM_BC_Err_Unknown';
import LABEL_ERR_BATCH_NOT_READY from '@salesforce/label/c.CM_BC_Err_BatchIdNotReady';
import LABEL_ERR_UPLOADING from '@salesforce/label/c.CM_BC_Err_Uploading';

const LABELS = {
  uploadTitle: LABEL_UPLOAD_TITLE,
  uploadLabel: LABEL_UPLOAD_LABEL,
  uploadStatus: LABEL_UPLOAD_STATUS,
  errUnknown: LABEL_ERR_UNKNOWN,
  errBatchNotReady: LABEL_ERR_BATCH_NOT_READY,
  errUploading: LABEL_ERR_UPLOADING
};

const formatLabel = (label, params = []) =>
  params.reduce((acc, val, idx) => acc.replace(`{${idx}}`, val ?? ''), label);

export default class CmBusinessCardOcrUpload extends LightningElement {
  @api flowOutputBatchId;         // For Flow (legacy flow)
  @api varContentVersionIDs = '[]'; // For Flow (new flow, JSON array)

  @track batchId;
  @track fileCount = 0;
  @track errMsg;
  @track isLoading = false;
  labels = LABELS;

  get uploadedStatusText() {
    return formatLabel(LABELS.uploadStatus, [String(this.fileCount || 0), this.batchId || '']);
  }

  async handleUploadFinished(event) {
    this.errMsg = null;
    const files = event.detail.files || [];
    this.fileCount = files.length;
    if (!files.length) return;

    try {
      this.isLoading = true;
      // Here we receive ContentDocumentId (069...); backend accepts mixed 068/069
      const contentVersionIdsOrDocIds = files.map(f => f.documentId);

      const res = await initBatchAndPersist({ contentVersionIds: contentVersionIdsOrDocIds });
      this.batchId = res?.batchId;
      this.flowOutputBatchId = this.batchId;

      // Immediately fetch seed 068s for this batch for the new flow
      const verIds = await getSeedVersionIdsByBatch({ batchId: this.batchId });
      this.varContentVersionIDs = JSON.stringify(verIds || []);

      // Notify Flow (optional)
      this.dispatchEvent(new CustomEvent('valuechange', {
        detail: { batchId: this.flowOutputBatchId, versionIdsJson: this.varContentVersionIDs }
      }));
    } catch (e) {
      this.errMsg = (e && e.body && e.body.message) ? e.body.message : (e?.message || LABELS.errUnknown);
    } finally {
      this.isLoading = false;
    }
  }

  @api validate() {
    if (this.isLoading) {
      return { isValid: false, errorMessage: LABELS.errUploading };
    }
    if (!this.batchId) {
      return { isValid: false, errorMessage: LABELS.errBatchNotReady };
    }
    return { isValid: true };
  }
}