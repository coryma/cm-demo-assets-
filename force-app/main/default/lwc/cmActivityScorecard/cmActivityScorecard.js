import { LightningElement, api, wire } from 'lwc';
import LANG from '@salesforce/i18n/lang';
import loadScorecard from '@salesforce/apex/CMActivityScorecardController.loadScorecard';
import loadScorecardForUser from '@salesforce/apex/CMActivityScorecardController.loadScorecardForUser';
import lblBaseHeader from '@salesforce/label/c.CM_ActivityScorecard_BaseHeader';
import lblUserHeader from '@salesforce/label/c.CM_ActivityScorecard_UserHeader';
import lblLoadingAlt from '@salesforce/label/c.CM_ActivityScorecard_LoadingAlt';
import lblNewPersonalBest from '@salesforce/label/c.CM_ActivityScorecard_NewPersonalBest';
import lblPersonalBest from '@salesforce/label/c.CM_ActivityScorecard_PersonalBest';
import lblNoDeals from '@salesforce/label/c.CM_ActivityScorecard_NoDeals';
import lblNoActivities from '@salesforce/label/c.CM_ActivityScorecard_NoActivities';
import lblDealsWon from '@salesforce/label/c.CM_ActivityScorecard_DealsWon';
import lblDealsLost from '@salesforce/label/c.CM_ActivityScorecard_DealsLost';
import lblTasksCompleted from '@salesforce/label/c.CM_ActivityScorecard_TasksCompleted';
import lblCallsLogged from '@salesforce/label/c.CM_ActivityScorecard_CallsLogged';
import lblEmailsSent from '@salesforce/label/c.CM_ActivityScorecard_EmailsSent';
import lblEventsLogged from '@salesforce/label/c.CM_ActivityScorecard_EventsLogged';
import lblGenericError from '@salesforce/label/c.CM_ActivityScorecard_GenericError';
import lblBaseHeaderZhTw from '@salesforce/label/c.CM_ActivityScorecard_BaseHeader_ZH_TW';
import lblUserHeaderZhTw from '@salesforce/label/c.CM_ActivityScorecard_UserHeader_ZH_TW';
import lblLoadingAltZhTw from '@salesforce/label/c.CM_ActivityScorecard_LoadingAlt_ZH_TW';
import lblNewPersonalBestZhTw from '@salesforce/label/c.CM_ActivityScorecard_NewPersonalBest_ZH_TW';
import lblPersonalBestZhTw from '@salesforce/label/c.CM_ActivityScorecard_PersonalBest_ZH_TW';
import lblNoDealsZhTw from '@salesforce/label/c.CM_ActivityScorecard_NoDeals_ZH_TW';
import lblNoActivitiesZhTw from '@salesforce/label/c.CM_ActivityScorecard_NoActivities_ZH_TW';
import lblDealsWonZhTw from '@salesforce/label/c.CM_ActivityScorecard_DealsWon_ZH_TW';
import lblDealsLostZhTw from '@salesforce/label/c.CM_ActivityScorecard_DealsLost_ZH_TW';
import lblTasksCompletedZhTw from '@salesforce/label/c.CM_ActivityScorecard_TasksCompleted_ZH_TW';
import lblCallsLoggedZhTw from '@salesforce/label/c.CM_ActivityScorecard_CallsLogged_ZH_TW';
import lblEmailsSentZhTw from '@salesforce/label/c.CM_ActivityScorecard_EmailsSent_ZH_TW';
import lblEventsLoggedZhTw from '@salesforce/label/c.CM_ActivityScorecard_EventsLogged_ZH_TW';
import lblGenericErrorZhTw from '@salesforce/label/c.CM_ActivityScorecard_GenericError_ZH_TW';

function formatLabel(label, ...args) {
  return args.reduce((result, value, index) => result.split(`{${index}}`).join(value), label);
}

const EN_LABELS = {
  baseHeader: lblBaseHeader,
  userHeader: lblUserHeader,
  loadingAlt: lblLoadingAlt,
  newPersonalBest: lblNewPersonalBest,
  personalBest: lblPersonalBest,
  noDeals: lblNoDeals,
  noActivities: lblNoActivities,
  dealsWon: lblDealsWon,
  dealsLost: lblDealsLost,
  tasksCompleted: lblTasksCompleted,
  callsLogged: lblCallsLogged,
  emailsSent: lblEmailsSent,
  eventsLogged: lblEventsLogged,
  genericError: lblGenericError
};

const ZH_TW_LABELS = {
  baseHeader: lblBaseHeaderZhTw,
  userHeader: lblUserHeaderZhTw,
  loadingAlt: lblLoadingAltZhTw,
  newPersonalBest: lblNewPersonalBestZhTw,
  personalBest: lblPersonalBestZhTw,
  noDeals: lblNoDealsZhTw,
  noActivities: lblNoActivitiesZhTw,
  dealsWon: lblDealsWonZhTw,
  dealsLost: lblDealsLostZhTw,
  tasksCompleted: lblTasksCompletedZhTw,
  callsLogged: lblCallsLoggedZhTw,
  emailsSent: lblEmailsSentZhTw,
  eventsLogged: lblEventsLoggedZhTw,
  genericError: lblGenericErrorZhTw
};

const IS_CHINESE_LOCALE = typeof LANG === 'string' && LANG.toLowerCase().startsWith('zh');
const LABELS = IS_CHINESE_LOCALE ? { ...EN_LABELS, ...ZH_TW_LABELS } : EN_LABELS;

const DEFAULT_LOOKBACK_DAYS = 30;
const MAX_LOOKBACK_DAYS = 365;
const DEFAULT_HEADER = formatLabel(LABELS.baseHeader, DEFAULT_LOOKBACK_DAYS);
const DEFAULT_SUMMARY = [
  { label: LABELS.dealsWon, value: 10, variant: 'success' },
  { label: LABELS.dealsLost, value: 7, variant: 'danger' }
];
const DEFAULT_ACTIVITIES = [
  {
    label: LABELS.tasksCompleted,
    value: 90,
    personalBest: 90,
    iconName: 'utility:task',
    theme: 'success',
    isNewPersonalBest: true
  },
  {
    label: LABELS.callsLogged,
    value: 98,
    personalBest: 120,
    iconName: 'utility:call',
    theme: 'teal'
  },
  {
    label: LABELS.emailsSent,
    value: 98,
    personalBest: 150,
    iconName: 'utility:email',
    theme: 'slate'
  },
  {
    label: LABELS.eventsLogged,
    value: 23,
    personalBest: 35,
    iconName: 'utility:event',
    theme: 'magenta'
  }
];

const SUMMARY_VARIANTS = {
  default: 'summary-card',
  success: 'summary-card summary-card--success',
  danger: 'summary-card summary-card--danger'
};

const ACTIVITY_THEMES = {
  success: {
    iconClasses: 'activity__icon theme--success',
    progressClasses: 'activity__progress-fill theme--success'
  },
  teal: {
    iconClasses: 'activity__icon theme--teal',
    progressClasses: 'activity__progress-fill theme--teal'
  },
  slate: {
    iconClasses: 'activity__icon theme--slate',
    progressClasses: 'activity__progress-fill theme--slate'
  },
  magenta: {
    iconClasses: 'activity__icon theme--magenta',
    progressClasses: 'activity__progress-fill theme--magenta'
  }
};

function formatNumber(value) {
  if (value === null || value === undefined || value === '') {
    return '—';
  }

  const number = Number(value);
  if (Number.isNaN(number)) {
    return value;
  }

  return new Intl.NumberFormat().format(number);
}

export default class CmActivityScorecard extends LightningElement {
  _recordId;
  _targetUserId;

  _headerLabel = DEFAULT_HEADER;
  _headerOverride = false;
  _summary = [];
  _activities = [];
  _useSummaryFallback = true;
  _useActivityFallback = true;
  _lookbackDays = DEFAULT_LOOKBACK_DAYS;
  hasFetchedData = false;

  isLoading = false;
  errorMessage;
  loadingLabel = LABELS.loadingAlt;

  @api
  get recordId() {
    return this._recordId;
  }

  set recordId(value) {
    if (this._recordId === value) {
      return;
    }
    this._recordId = value;
    this.resetStateForNewContext();
  }

  @api
  get targetUserId() {
    return this._targetUserId;
  }

  set targetUserId(value) {
    if (this._targetUserId === value) {
      return;
    }
    this._targetUserId = value;
    if (!this._recordId) {
      this.resetStateForNewContext();
    }
  }

  @api
  get headerLabel() {
    return this._headerLabel;
  }

  set headerLabel(value) {
    if (value) {
      this._headerLabel = value;
      this._headerOverride = true;
    } else {
      this._headerLabel = DEFAULT_HEADER;
      this._headerOverride = false;
    }
  }

  @api
  get lookbackDays() {
    return this._lookbackDays;
  }

  set lookbackDays(value) {
    this._lookbackDays = this.normalizeLookback(value);
  }

  @api
  get summary() {
    return this._summary;
  }

  set summary(value) {
    if (Array.isArray(value) && value.length) {
      this._summary = value.map((item) => ({ ...item }));
      this._useSummaryFallback = false;
    } else {
      this._summary = [];
      if (!this.hasFetchedData) {
        this._useSummaryFallback = true;
      }
    }
  }

  @api
  get activities() {
    return this._activities;
  }

  set activities(value) {
    if (Array.isArray(value) && value.length) {
      this._activities = value.map((item) => ({ ...item }));
      this._useActivityFallback = false;
    } else {
      this._activities = [];
      if (!this.hasFetchedData) {
        this._useActivityFallback = true;
      }
    }
  }

  @wire(loadScorecard, { accountId: '$recordId', lookbackDays: '$resolvedLookbackDays' })
  wiredAccountScorecard(result) {
    this.handleWireResult(result, 'account');
  }

  @wire(loadScorecardForUser, { userId: '$resolvedUserId', lookbackDays: '$resolvedLookbackDays' })
  wiredUserScorecard(result) {
    this.handleWireResult(result, 'user');
  }

  get resolvedLookbackDays() {
    return this.normalizeLookback(this._lookbackDays);
  }

  get resolvedUserId() {
    if (this._recordId) {
      return undefined;
    }
    return this._targetUserId || null;
  }

  get shouldFetchFromApex() {
    if (this._recordId) {
      return true;
    }
    return this.resolvedUserId !== undefined;
  }

  resetStateForNewContext() {
    this.hasFetchedData = false;
    this.errorMessage = undefined;
    this._summary = [];
    this._activities = [];
    this._useSummaryFallback = true;
    this._useActivityFallback = true;
    if (!this._headerOverride) {
      this._headerLabel = DEFAULT_HEADER;
    }
    this.isLoading = this.shouldFetchFromApex;
  }

  handleWireResult(result, source) {
    const isAccountSource = source === 'account';
    if (isAccountSource && !this._recordId) {
      return;
    }
    if (!isAccountSource && (this._recordId || this.resolvedUserId === undefined)) {
      return;
    }

    const { data, error } = result;

    if (data) {
      this.isLoading = false;
      this.errorMessage = undefined;
      this.applyScorecardData(data);
      this.hasFetchedData = true;
      return;
    }

    if (error) {
      this.isLoading = false;
      this.hasFetchedData = false;
      this._useSummaryFallback = false;
      this._useActivityFallback = false;
      this._summary = [];
      this._activities = [];
      this.errorMessage = this.formatError(error);
      return;
    }

    if (!this.hasFetchedData) {
      this.isLoading = true;
      this.errorMessage = undefined;
    }
  }

  applyScorecardData(data) {
    if (!this._headerOverride && data.headerLabel) {
      this._headerLabel = data.headerLabel;
    }

    this._summary = Array.isArray(data.summary) ? data.summary.map((item) => ({ ...item })) : [];
    this._activities = Array.isArray(data.activities) ? data.activities.map((item) => ({ ...item })) : [];
    this._useSummaryFallback = false;
    this._useActivityFallback = false;
  }

  normalizeLookback(value) {
    const parsed = Number.parseInt(value, 10);
    if (Number.isFinite(parsed) && parsed > 0) {
      return Math.min(parsed, MAX_LOOKBACK_DAYS);
    }
    return DEFAULT_LOOKBACK_DAYS;
  }

  formatError(error) {
    if (!error) {
      return LABELS.genericError;
    }

    if (Array.isArray(error.body)) {
      const combined = error.body.map((entry) => entry.message).join(', ');
      return combined || LABELS.genericError;
    }

    if (error.body && typeof error.body.message === 'string') {
      return error.body.message || LABELS.genericError;
    }

    return error.message || LABELS.genericError;
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  get effectiveHeaderLabel() {
    return this._headerLabel;
  }

  get hasActivities() {
    return (this._useActivityFallback ? DEFAULT_ACTIVITIES : this._activities).length > 0;
  }

  get hasSummary() {
    return (this._useSummaryFallback ? DEFAULT_SUMMARY : this._summary).length > 0;
  }

  get summaryEmptyMessage() {
    return formatLabel(LABELS.noDeals, this.resolvedLookbackDays);
  }

  get activitiesEmptyMessage() {
    return formatLabel(LABELS.noActivities, this.resolvedLookbackDays);
  }

  get summaryItems() {
    const source = this._useSummaryFallback
      ? DEFAULT_SUMMARY
      : Array.isArray(this._summary) ? this._summary : [];

    return source.map((item, index) => {
      const variant = item.variant || item.theme || 'default';
      const classes = SUMMARY_VARIANTS[variant] || SUMMARY_VARIANTS.default;
      return {
        key: `summary-${index}`,
        label: item.label,
        value: formatNumber(item.value),
        detail: item.detail || '',
        classes
      };
    });
  }

  get activityItems() {
    const source = this._useActivityFallback
      ? DEFAULT_ACTIVITIES
      : Array.isArray(this._activities) ? this._activities : [];

    return source.map((item, index) => {
      const themeKey = item.theme || 'success';
      const theme = ACTIVITY_THEMES[themeKey] || ACTIVITY_THEMES.success;
      const personalBestValue = Number(item.personalBest);
      const personalBest = Number.isNaN(personalBestValue) ? null : personalBestValue;
      const rawValue = Number(item.value);
      const numericValue = Number.isNaN(rawValue) ? null : rawValue;

      const hasBaseline = personalBest !== null && personalBest > 0;
      let ratio = 0;
      if (hasBaseline && numericValue !== null) {
        ratio = numericValue / personalBest;
      } else if (!hasBaseline && numericValue !== null) {
        ratio = numericValue > 0 ? 1 : 0;
      }
      const progressWidth = `${Math.max(0, Math.min(ratio, 1)) * 100}%`;

      const personalBestDisplay = personalBest === null ? '—' : formatNumber(personalBest);

      const isNewPersonalBest = Boolean(
        item.isNewPersonalBest ||
          (hasBaseline && numericValue !== null && numericValue >= personalBest)
      );

      return {
        key: `activity-${index}`,
        label: item.label,
        value: numericValue === null ? item.value : formatNumber(numericValue),
        personalBest: personalBestDisplay,
        isNewPersonalBest,
        iconName: item.iconName || 'utility:activity',
        iconClasses: theme.iconClasses,
        progressClasses: theme.progressClasses,
        progressStyle: `width: ${progressWidth};`,
        badgeText: formatLabel(LABELS.newPersonalBest, personalBestDisplay),
        metaText: formatLabel(LABELS.personalBest, personalBestDisplay)
      };
    });
  }
}