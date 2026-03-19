import { LightningElement, api, track } from 'lwc';
import getBatchProgress from '@salesforce/apex/CM_BusinessCard_Controller.getBatchProgress';
import getCardsByBatch   from '@salesforce/apex/CM_BusinessCard_Controller.getCardsByBatch';
import getProgressByVersionId from '@salesforce/apex/CM_BusinessCard_Controller.getProgressByVersionId';
import getCardsByVersionId    from '@salesforce/apex/CM_BusinessCard_Controller.getCardsByVersionId';
import findAccountDuplicates  from '@salesforce/apex/CM_BusinessCard_Controller.findAccountDuplicates';
import LABEL_REVIEW_TITLE from '@salesforce/label/c.CM_BC_Review_Title';
import LABEL_REVIEW_SPINNER from '@salesforce/label/c.CM_BC_Review_Spinner';
import LABEL_REVIEW_NO_CARDS_TITLE from '@salesforce/label/c.CM_BC_Review_NoCards_Title';
import LABEL_REVIEW_NO_CARDS_BODY from '@salesforce/label/c.CM_BC_Review_NoCards_Body';
import LABEL_REVIEW_DESC_LABEL from '@salesforce/label/c.CM_BC_Review_Desc_Label';
import LABEL_REVIEW_DUPE_TITLE from '@salesforce/label/c.CM_BC_Review_Dupe_Title';
import LABEL_REVIEW_DUPE_BODY from '@salesforce/label/c.CM_BC_Review_Dupe_Body';
import LABEL_REVIEW_ACCOUNT_LABEL from '@salesforce/label/c.CM_BC_Review_Account_Label';
import LABEL_REVIEW_ACCOUNT_PLACEHOLDER from '@salesforce/label/c.CM_BC_Review_Account_Placeholder';
import LABEL_REVIEW_FOOTER_NOTE from '@salesforce/label/c.CM_BC_Review_FooterNote';
import LABEL_PROGRESS_PREPARING from '@salesforce/label/c.CM_BC_Progress_Preparing';
import LABEL_PROGRESS_RUNNING from '@salesforce/label/c.CM_BC_Progress_Running';
import LABEL_PROGRESS_FAILED_SEGMENT from '@salesforce/label/c.CM_BC_Progress_Failed_Segment';
import LABEL_ERR_PROGRESS_FETCH from '@salesforce/label/c.CM_BC_Err_ProgressFetch';
import LABEL_ERR_DUPLICATE_MATCH from '@salesforce/label/c.CM_BC_Err_DuplicateMatch';
import LABEL_CREATE_OPTION_LEAD from '@salesforce/label/c.CM_BC_CreateOption_Lead';
import LABEL_CREATE_OPTION_CONTACT from '@salesforce/label/c.CM_BC_CreateOption_Contact';
import LABEL_ERR_NOT_FINISHED from '@salesforce/label/c.CM_BC_Err_NotFinished';
import LABEL_ERR_SELECT_ACCOUNT from '@salesforce/label/c.CM_BC_Err_SelectAccountForCard';
import LABEL_CARD_FALLBACK_NAME from '@salesforce/label/c.CM_BC_Card_FallbackName';

const LABELS = {
  reviewTitle: LABEL_REVIEW_TITLE,
  reviewSpinner: LABEL_REVIEW_SPINNER,
  noCardsTitle: LABEL_REVIEW_NO_CARDS_TITLE,
  noCardsBody: LABEL_REVIEW_NO_CARDS_BODY,
  descLabel: LABEL_REVIEW_DESC_LABEL,
  dupeTitle: LABEL_REVIEW_DUPE_TITLE,
  dupeBody: LABEL_REVIEW_DUPE_BODY,
  accountLabel: LABEL_REVIEW_ACCOUNT_LABEL,
  accountPlaceholder: LABEL_REVIEW_ACCOUNT_PLACEHOLDER,
  footerNote: LABEL_REVIEW_FOOTER_NOTE,
  progressPreparing: LABEL_PROGRESS_PREPARING,
  progressRunning: LABEL_PROGRESS_RUNNING,
  progressFailedSegment: LABEL_PROGRESS_FAILED_SEGMENT,
  errProgressFetch: LABEL_ERR_PROGRESS_FETCH,
  errDuplicateMatch: LABEL_ERR_DUPLICATE_MATCH,
  createLead: LABEL_CREATE_OPTION_LEAD,
  createContact: LABEL_CREATE_OPTION_CONTACT,
  errNotFinished: LABEL_ERR_NOT_FINISHED,
  errSelectAccount: LABEL_ERR_SELECT_ACCOUNT,
  cardFallbackName: LABEL_CARD_FALLBACK_NAME
};

const formatLabel = (label, params = []) =>
  params.reduce((acc, val, idx) => acc.replace(`{${idx}}`, val ?? ''), label);

const POLL_MS      = 2000;   // Backend polling interval
const ANIM_TOTAL_MS= 12000;  // Progress bar loops every 12 seconds
const ANIM_TICK_MS = 100;    // Progress bar update interval
const TIMEOUT_MS   = 20000;  // Timeout fallback: stop waiting when time is up
const MODE_LEAD    = 'Lead';
const MODE_CONTACT = 'Contact';

export default class CmBusinessCardReviewAsync extends LightningElement {
  // ===== Two modes: contentVersionId (068/069) or batchId, choose one =====
  _contentVersionId;
  _batchId;

  @api
  get contentVersionId() { return this._contentVersionId; }
  set contentVersionId(v) {
    this._contentVersionId = v;
    this.tryStart(); // Late-arriving params can still start in time
  }

  @api
  get batchId() { return this._batchId; }
  set batchId(v) {
    this._batchId = v;
    this.tryStart(); // Late-arriving params can still start in time
  }

  @api leadSource;

  @api flowOutputCardsJsonEdited;

  @track progress = { total: 0, recognized: 0, failed: 0, status: 'EMPTY' };
  @track cards = [];
  @track errMsg;
  @track matchErrMsg;
  @track uiProgress = 0;
  labels = LABELS;

  _pollTimer;
  _animTimer;
  _animStart = 0;
  _started   = false;
  _finished  = false;
  _t0        = 0;

  // State flags
  get useVersionMode() { return !!this._contentVersionId; }
  get hasCards()       { return (this.cards?.length || 0) > 0; }
  get isReady()        { return this.hasCards; }
  get isNoCards()      { return !this.hasCards && this._finished; } // Finished but no cards
  get isWaiting()      { return !this.isReady && !this.isNoCards; }

  // Use a textual progress description; percentage comes from animation
  get progressLabel() {
    const t = this.progress?.total || 0;
    const r = this.progress?.recognized || 0;
    const f = this.progress?.failed || 0;
    if (!t) return LABELS.progressPreparing;
    const failedSeg = f ? formatLabel(LABELS.progressFailedSegment, [String(f)]) : '';
    return formatLabel(LABELS.progressRunning, [String(r), String(t), failedSeg]);
  }

  connectedCallback() {
    this.tryStart();
  }
  disconnectedCallback() {
    this.stopAnimation();
    if (this._pollTimer) clearTimeout(this._pollTimer);
  }

  // ===== Start condition: if any Id exists and not started, start =====
  tryStart() {
    if (this._started) return;
    if (!this._contentVersionId && !this._batchId) return;

    this._started = true;
    this._finished = false;
    this._t0 = Date.now();
    this.matchErrMsg = null;

    this.startAnimation();
    this.schedulePoll(0);
  }

  // ===== 12-second looping animation =====
  startAnimation() {
    this.stopAnimation();
    this._animStart = Date.now();
    this._animTimer = setInterval(() => {
      const elapsed = Date.now() - this._animStart;
      const pct = Math.floor(((elapsed % ANIM_TOTAL_MS) / ANIM_TOTAL_MS) * 100);
      this.uiProgress = (this._finished || this.isReady) ? 100 : pct;
    }, ANIM_TICK_MS);
  }
  stopAnimation() {
    if (this._animTimer) clearInterval(this._animTimer);
    this._animTimer = null;
    this.uiProgress = 100;
  }

  // ===== Backend polling (stop when done or timed out) =====
  schedulePoll(delay) {
    if (this._pollTimer) clearTimeout(this._pollTimer);
    this._pollTimer = setTimeout(() => this.pollOnce(), delay);
  }

  async pollOnce() {
    try {
      let p, rows;
      if (this.useVersionMode) {
        [p, rows] = await Promise.all([
          getProgressByVersionId({ contentVersionIdOrDocId: this._contentVersionId }),
          getCardsByVersionId({ contentVersionIdOrDocId: this._contentVersionId })
        ]);
      } else {
        [p, rows] = await Promise.all([
          getBatchProgress({ batchId: this._batchId }),
          getCardsByBatch({ batchId: this._batchId })
        ]);
      }

      this.progress = p || { total: 0, recognized: 0, failed: 0, status: 'EMPTY' };

      // 1) If cards exist, finish immediately
      if (Array.isArray(rows) && rows.length > 0) {
        this.cards = this.attachKeys(rows);
        await this.decorateCardsWithMatches();
        this.syncOutput();
        this.finishPolling();
        return;
      }

      // 2) No cards but progress says ALL_RECOGNIZED ⇒ treat as finished with no cards
      const allDone = (this.progress?.status === 'ALL_RECOGNIZED') && (this.progress?.total || 0) > 0;
      if (allDone) {
        this.cards = [];
        this.syncOutput();
        this.finishPolling(true);
        return;
      }

      // 3) Timeout fallback: fetch once more; if still empty, finish (avoid stalling)
      const timedOut = (Date.now() - this._t0) >= TIMEOUT_MS;
      if (timedOut) {
        const rows2 = await this.fetchCardsOnce(); // Double-check once more
        if (Array.isArray(rows2) && rows2.length > 0) {
          this.cards = this.attachKeys(rows2);
          await this.decorateCardsWithMatches();
          this.syncOutput();
        } else {
          this.cards = []; // Treat as no-cards completion
          this.matchErrMsg = null;
          this.syncOutput();
        }
        this.finishPolling(true);
        return;
      }

      // 4) Continue polling
      this.schedulePoll(POLL_MS);

    } catch (e) {
      this.errMsg = e?.body?.message || e?.message || LABELS.errProgressFetch;
      // Don't hard-stop on error; try again next poll
      this.schedulePoll(POLL_MS);
    }
  }

  async fetchCardsOnce() {
    try {
      if (this.useVersionMode) {
        return await getCardsByVersionId({ contentVersionIdOrDocId: this._contentVersionId });
      }
      return await getCardsByBatch({ batchId: this._batchId });
    } catch {
      return [];
    }
  }

  async decorateCardsWithMatches() {
    if (!Array.isArray(this.cards) || this.cards.length === 0) {
      this.matchErrMsg = null;
      return;
    }

    const companyNames = this.cards.map(card => (card && card.Company) ? card.Company : null);
    try {
      const response = await findAccountDuplicates({ companyNames });
      const matches = Array.isArray(response) ? response : [];
      const updated = this.cards.map((card, index) => this.decorateCardWithMatches(card, matches[index]));
      this.cards = updated;
      this.matchErrMsg = null;
    } catch (error) {
      // If query fails, record message without blocking flow, and reset to default state
      this.matchErrMsg = error?.body?.message || error?.message || LABELS.errDuplicateMatch;
      this.cards = this.cards.map(card => this.decorateCardWithMatches(card, null));
    }
  }

  decorateCardWithMatches(card, match) {
    const options = this.buildAccountOptions(match);
    const hasMatches = options.length > 0;
    const createAs = this.normalizeCreateMode(card?.CreateAs, hasMatches);

    let selectedAccountId = card?.ExistingAccountId || null;
    if (createAs === MODE_CONTACT && hasMatches) {
      const exists = options.some(opt => opt.value === selectedAccountId);
      if (!exists) {
        selectedAccountId = options.length === 1 ? options[0].value : null;
      }
    } else {
      selectedAccountId = null;
    }

    return {
      ...card,
      CreateAs: createAs,
      ExistingAccountId: selectedAccountId,
      accountOptions: options,
      createOptions: this.buildCreateOptions(hasMatches),
      hasAccountMatches: hasMatches,
      showAccountPicker: createAs === MODE_CONTACT && hasMatches
    };
  }

  buildAccountOptions(match) {
    if (!match || !Array.isArray(match.accounts)) {
      return [];
    }

    return match.accounts
      .filter(acc => acc && acc.accountId)
      .map(acc => ({
        label: this.formatAccountLabel(acc),
        value: acc.accountId
      }));
  }

  buildCreateOptions(hasMatches) {
    const options = [
      { label: LABELS.createLead, value: MODE_LEAD }
    ];
    if (hasMatches) {
      options.push({ label: LABELS.createContact, value: MODE_CONTACT });
    }
    return options;
  }

  normalizeCreateMode(value, hasMatches) {
    const token = (value || '').toLowerCase();
    if (hasMatches && token === MODE_CONTACT.toLowerCase()) {
      return MODE_CONTACT;
    }
    return MODE_LEAD;
  }

  formatAccountLabel(option) {
    const parts = [option.name];
    const region = [option.billingCity, option.billingCountry].filter(Boolean).join(', ');
    if (region) {
      parts.push(`· ${region}`);
    }
    if (option.phone) {
      parts.push(`· ${option.phone}`);
    }
    return parts.filter(Boolean).join(' ');
  }

  finishPolling(noCards = false) {
    this._finished = true;
    this.stopAnimation();
    if (this._pollTimer) {
      clearTimeout(this._pollTimer);
      this._pollTimer = null;
    }
    // If you need to notify Flow, you can dispatch an event:
    // this.dispatchEvent(new CustomEvent('done', { detail: { noCards } }));
  }

  // ===== UI & Flow output =====
  attachKeys(rows) {
    return (rows || []).map((r, i) => {
      const a = (r.Email || '').toLowerCase();
      const b = (r.Company || '').toLowerCase();
      const c = (r.FirstName || '').toLowerCase() + (r.LastName || '').toLowerCase();
      const key = `${i}-${a}-${b}-${c}`;
      const createAs = this.normalizeCreateMode(r?.CreateAs, false);
      return {
        ...r,
        CreateAs: createAs,
        ExistingAccountId: r?.ExistingAccountId || null,
        accountOptions: [],
        createOptions: this.buildCreateOptions(false),
        hasAccountMatches: false,
        showAccountPicker: false,
        _key: key
      };
    });
  }
  onDescChange(e) {
    const idx = Number(e.target.dataset.index);
    if (Number.isNaN(idx) || !this.cards[idx]) {
      return;
    }
    this.cards[idx].Description = e.detail.value;
    this.cards = [...this.cards];
    this.syncOutput();
  }
  onCreateModeChange(e) {
    const idx = Number(e.target.dataset.index);
    if (Number.isNaN(idx) || !this.cards[idx]) {
      return;
    }
    const selectedMode = this.normalizeCreateMode(e.detail.value, this.cards[idx].hasAccountMatches);
    const card = this.cards[idx];
    card.CreateAs = selectedMode;
    if (selectedMode === MODE_CONTACT && card.hasAccountMatches) {
      if (!card.ExistingAccountId && card.accountOptions.length === 1) {
        card.ExistingAccountId = card.accountOptions[0].value;
      }
      card.showAccountPicker = true;
    } else {
      card.ExistingAccountId = null;
      card.showAccountPicker = false;
    }
    this.cards = [...this.cards];
    this.syncOutput();
  }
  onAccountPickChange(e) {
    const idx = Number(e.target.dataset.index);
    if (Number.isNaN(idx) || !this.cards[idx]) {
      return;
    }
    const value = e.detail.value;
    this.cards[idx].ExistingAccountId = value || null;
    this.cards = [...this.cards];
    this.syncOutput();
  }
  syncOutput() {
    try {
      const sanitized = (this.cards || []).map(card => {
        const payload = { ...card };
        const leadSource = (this.leadSource || '').trim();
        if (leadSource) {
          payload.LeadSource = leadSource;
        }
        delete payload._key;
        delete payload.accountOptions;
        delete payload.createOptions;
        delete payload.hasAccountMatches;
        delete payload.showAccountPicker;
        return payload;
      });
      this.flowOutputCardsJsonEdited = JSON.stringify(sanitized);
    } catch {
      this.flowOutputCardsJsonEdited = '[]';
    }
  }

  @api validate() {
    // Allow next step whether cards exist or not; if you want to block when no cards, make isNoCards fail validation
    if (this.isWaiting) {
      return { isValid: false, errorMessage: LABELS.errNotFinished };
    }
    this.syncOutput();
    for (const card of this.cards || []) {
      if (card.CreateAs === MODE_CONTACT && (!card.ExistingAccountId || !card.ExistingAccountId.length)) {
        const name = card.Company || `${card.LastName || ''}${card.FirstName || ''}` || LABELS.cardFallbackName;
        return { isValid: false, errorMessage: formatLabel(LABELS.errSelectAccount, [name]) };
      }
    }
    return { isValid: true };
  }
}