import { LightningElement, api, track, wire } from 'lwc';
import getDocIdFromVersion from '@salesforce/apex/CM_BusinessCard_Image_Helper.getDocIdFromVersion';
import LABEL_IMAGE_TITLE from '@salesforce/label/c.CM_BC_Image_Title';
import LABEL_IMAGE_LOADING from '@salesforce/label/c.CM_BC_Image_Loading';
import LABEL_IMAGE_DOWNLOAD from '@salesforce/label/c.CM_BC_Image_Download';
import LABEL_IMAGE_MISSING_PARAMS from '@salesforce/label/c.CM_BC_Image_MissingParams';
import LABEL_IMAGE_LOAD_FAILED from '@salesforce/label/c.CM_BC_Image_LoadFailed';

const LABELS = {
  imageTitle: LABEL_IMAGE_TITLE,
  imageLoading: LABEL_IMAGE_LOADING,
  imageDownload: LABEL_IMAGE_DOWNLOAD,
  imageMissingParams: LABEL_IMAGE_MISSING_PARAMS,
  imageLoadFailed: LABEL_IMAGE_LOAD_FAILED
};

export default class CmBusinessCardDisplayImageInFlow extends LightningElement {
  // ===== Inputs =====
  @api title = LABELS.imageTitle;
  @api altText = LABELS.imageTitle;
  @api contentVersionId;      // 068… (can be provided alone)
  @api contentDocumentId;     // 069… (can also be provided directly)
  _contentVersionIdsJson;
  @api
  get contentVersionIdsJson() { return this._contentVersionIdsJson; }
  set contentVersionIdsJson(v) {
    this._contentVersionIdsJson = v;
    this.prepareCandidates();
  }
  @api width = '100%';        // '100%' / '600px'
  @api height = 'auto';       // 'auto' / '300px'
  @api objectFit = 'contain'; // contain | cover | fill | none | scale-down
  @api borderRadius = '6px';
  @api showDownloadLink = false;

  // Compatibility: if a full URL is already built, it can be passed in
  @api imageUrl;              // Full image URL (highest priority)
  @api imageStyle;            // Custom CSS string, e.g. "max-width:100%;border-radius:8px;"

  // ===== Outputs =====
  @api resolvedUrl;           // Actual URL that successfully renders
  @api loadStatus = '';       // '', 'loaded', 'failed'

  // ===== State =====
  @track isLoading = false;
  @track errorMsg;
  @track imageItems = [];
  _candidates = [];
  _idx = 0;
  labels = LABELS;

  // Resolve 069 if only 068 is provided
  @wire(getDocIdFromVersion, { anyId: '$contentVersionId' })
  wiredDoc({ data, error }) {
    if (data && !this.contentDocumentId) {
      this.contentDocumentId = data;
    }
    // After runtime/Flow sets values, prepare candidates if not already built
    if (!this._candidates.length) {
      this.prepareCandidates();
    }
  }

  // ===== Computed props (avoid clashing with @api imageStyle) =====
  get containerStyle() {
    return `width:${this.width};height:${this.height};`;
  }
  get computedImageStyle() {
    // Allow external CSS override (fall back to defaults if not provided)
    if (this.imageStyle && this.imageStyle.trim()) return this.imageStyle;
    return `width:100%;height:100%;object-fit:${this.objectFit};border-radius:${this.borderRadius};display:block;`;
  }
  get imgUrl() {
    return this._candidates.length ? this._candidates[this._idx] : null;
  }
  get showDownload() {
    return !!this.showDownloadLink && !!this.downloadUrl;
  }
  get hasMultiImages() {
    return Array.isArray(this.imageItems) && this.imageItems.length > 0;
  }

  // ===== Base prefix: Experience Cloud support =====
  get basePrefix() {
    try {
      return window.location.pathname.includes('/sfsites/') ? '/sfsites/c' : '';
    } catch {
      return '';
    }
  }
  abs(path) {
    // Absolute URLs are more reliable on mobile
    try { return `${window.location.origin}${path}`; }
    catch { return path; }
  }

  // ===== Shepherd URLs =====
  buildVersionInline(versionId) {
    return this.abs(`${this.basePrefix}/sfc/servlet.shepherd/version/download/${versionId}?asInline=1`);
  }
  buildRendition(versionId, rendition) {
    return this.abs(`${this.basePrefix}/sfc/servlet.shepherd/version/renditionDownload?rendition=${rendition}&versionId=${versionId}`);
  }
  buildVersionDownload(versionId) {
    return this.abs(`${this.basePrefix}/sfc/servlet.shepherd/version/download/${versionId}`);
  }
  buildDocumentDownload(docId) {
    return this.abs(`${this.basePrefix}/sfc/servlet.shepherd/document/download/${docId}`);
  }

  get downloadUrl() {
    if (this.contentVersionId) return this.buildVersionDownload(this.contentVersionId);
    if (this.contentDocumentId) return this.buildDocumentDownload(this.contentDocumentId);
    return null;
  }

  // ===== Init / update =====
  connectedCallback() {
    this.prepareCandidates();
  }
  renderedCallback() {
    // Flow sets values before render; if candidates aren't built yet, build them here
    if (!this._candidates.length && (this.contentVersionId || this.contentDocumentId || this.imageUrl)) {
      this.prepareCandidates();
    }
  }

  @api refresh() {
    this.prepareCandidates();
  }

  parseIds(jsonValue) {
    if (!jsonValue) return [];
    try {
      const parsed = JSON.parse(jsonValue);
      if (!Array.isArray(parsed)) return [];
      return parsed.map(String).map(v => v.trim()).filter(v => v);
    } catch {
      return [];
    }
  }

  buildCandidatesForId(anyId) {
    const id = String(anyId || '');
    const pref = id.substring(0, 3);
    if (pref === '069') {
      // ContentDocumentId fallback (no version id available)
      return [this.buildDocumentDownload(id)];
    }
    return [
      this.buildVersionInline(id),
      this.buildRendition(id, 'THUMB1200BY900'),
      this.buildRendition(id, 'THUMB720BY480'),
      this.buildVersionDownload(id)
    ];
  }

  prepareCandidates() {
    this.errorMsg = undefined;
    this.loadStatus = '';
    this.isLoading = true;
    this._idx = 0;
    this._candidates = [];
    this.imageItems = [];

    // 1) Full URL provided externally → highest priority
    if (this.imageUrl && this.imageUrl.trim()) {
      this._candidates.push(this.imageUrl.trim());
    }

    // 2) JSON array of version ids (multi-image)
    const ids = this.parseIds(this._contentVersionIdsJson);
    if (!this._candidates.length && ids.length) {
      this.imageItems = ids.map((id) => {
        const candidates = this.buildCandidatesForId(id);
        return {
          id,
          candidates,
          idx: 0,
          url: candidates[0],
          downloadUrl: id.startsWith('069') ? this.buildDocumentDownload(id) : this.buildVersionDownload(id),
          error: ''
        };
      });
      this.isLoading = false;
      return;
    }

    // 2) Prefer 068 display (most stable on mobile: inline)
    if (this.contentVersionId) {
      this._candidates.push(this.buildVersionInline(this.contentVersionId));       // ✅ first choice
      this._candidates.push(this.buildRendition(this.contentVersionId, 'THUMB1200BY900')); // common thumbnail
      this._candidates.push(this.buildRendition(this.contentVersionId, 'THUMB720BY480'));  // fallback thumbnail
      this._candidates.push(this.buildVersionDownload(this.contentVersionId));     // final fallback
    }

    // 3) If 069 exists, add a download fallback
    if (this.contentDocumentId) {
      this._candidates.push(this.buildDocumentDownload(this.contentDocumentId));
    }

    if (!this._candidates.length) {
      this.isLoading = false;
      this.errorMsg = LABELS.imageMissingParams;
    }
  }

  // ===== Event handlers =====
  onImgLoad() {
    this.isLoading = false;
    this.errorMsg = undefined;
    this.loadStatus = 'loaded';
    this.resolvedUrl = this.imgUrl;
  }
  onImgError() {
    const next = this._idx + 1;
    if (next < this._candidates.length) {
      this._idx = next;   // Switch to next candidate URL (template auto-refreshes <img src>)
      return;
    }
    this.isLoading = false;
    this.loadStatus = 'failed';
    this.errorMsg = LABELS.imageLoadFailed;
  }
  onMultiImgError(event) {
    const index = Number(event?.currentTarget?.dataset?.index);
    if (Number.isNaN(index)) return;
    const items = Array.isArray(this.imageItems) ? [...this.imageItems] : [];
    const item = items[index];
    if (!item) return;
    const next = (item.idx || 0) + 1;
    if (next < item.candidates.length) {
      item.idx = next;
      item.url = item.candidates[next];
      items[index] = item;
      this.imageItems = items;
      return;
    }
    item.error = LABELS.imageLoadFailed;
    items[index] = item;
    this.imageItems = items;
  }
  openDownload() {
    const url = this.downloadUrl;
    if (url) window.open(url, '_blank'); // eslint-disable-line no-restricted-globals
  }
  openDownloadMulti(event) {
    const index = Number(event?.currentTarget?.dataset?.index);
    if (Number.isNaN(index)) return;
    const item = this.imageItems?.[index];
    if (item?.downloadUrl) window.open(item.downloadUrl, '_blank'); // eslint-disable-line no-restricted-globals
  }
}