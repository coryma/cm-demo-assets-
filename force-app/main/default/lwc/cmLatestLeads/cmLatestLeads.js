import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import lang from '@salesforce/i18n/lang';
import locale from '@salesforce/i18n/locale';
import fetchLatestLeads from '@salesforce/apex/CM_LatestLeadsController.fetchLatestLeads';

const I18N = {
  zh: {
    leadCaps: '潛在客戶',
    title: 'AI 自動分派潛在客戶名單',
    summary: (sortLabel, pollingSeconds, limitSize) =>
      `3+ 項 · 排序依據 ${sortLabel} · 每 ${pollingSeconds} 秒更新，顯示 ${limitSize} 筆`,
    searchPlaceholder: '搜尋此清單...',
    leadName: 'Lead 名稱',
    company: '公司',
    phone: '電話',
    valueIndicator: 'Value Indicator',
    createdDate: '建立時間',
    status: '狀態',
    noData: '目前沒有資料',
    popoverTitle: '智能評分',
    popoverAria: 'AI Scoring',
    classification: '分類',
    keyTopics: '關鍵主題',
    reason: '理由',
    reply: '回覆建議',
    sortFields: { aiScore: 'AI Score', createdDate: '建立時間', name: 'Lead 名稱' },
    sortDirAsc: '升冪',
    sortDirDesc: '降冪',
    relative: { suffix: ' 前', second: 's', minute: 'm', hour: 'h', day: '天', week: '週', month: '個月' }
  },
  en: {
    leadCaps: 'Leads',
    title: 'AI Auto-Assigned Leads',
    summary: (sortLabel, pollingSeconds, limitSize) =>
      `3+ items · Sorted by ${sortLabel} · Refreshes every ${pollingSeconds}s showing ${limitSize} records`,
    searchPlaceholder: 'Search this list...',
    leadName: 'Lead Name',
    company: 'Company',
    phone: 'Phone',
    valueIndicator: 'Value Indicator',
    createdDate: 'Created',
    status: 'Status',
    noData: 'No data available',
    popoverTitle: 'AI Scoring',
    popoverAria: 'AI Scoring',
    classification: 'Classification',
    keyTopics: 'Key Topics',
    reason: 'Reason',
    reply: 'Suggested Reply',
    sortFields: { aiScore: 'AI Score', createdDate: 'Created', name: 'Lead Name' },
    sortDirAsc: 'Ascending',
    sortDirDesc: 'Descending',
    relative: { suffix: ' ago', second: 's', minute: 'm', hour: 'h', day: 'd', week: 'w', month: 'mo' }
  }
};

export default class CmLatestLeads extends NavigationMixin(LightningElement) {
  // ========== 設計屬性 ==========
  _pollingMs = 10000;
  _limitSize = 20;

  @api
  set pollingMs(v){ const n=parseInt(v,10); this._pollingMs = Number.isFinite(n)&&n>0 ? Math.max(n,1000) : 10000; this._restartTimer(); }
  get pollingMs(){ return this._pollingMs; }

  @api
  set limitSize(v){ const n=parseInt(v,10); this._limitSize = Number.isFinite(n)&&n>0 ? Math.min(n,100) : 20; }
  get limitSize(){ return this._limitSize; }

  // ========== 狀態 ==========
  @track leads = [];
  _timer;
  keyword = '';

  // 排序：預設建立時間 ↓
  sortBy = 'createdDate';
  sortDirection = 'desc';
  nameSortArrow = '';
  aiScoreSortArrow = '';
  createdSortArrow = '▼';

  // Popover（只在這裡動畫）
  @track popover = { visible:false, top:0, left:0, nubbin:'slds-nubbin_left', row:{} , scoreAnimated:'', pct:0 };
  _hideTimer;
  _rafId;

  // ========== 派生 ==========
  get isTraditionalChinese(){
    const primary = (lang || '').toLowerCase().replace('_','-');
    const fallback = (locale || '').toLowerCase().replace('_','-');
    const isHant = code =>
      code &&
      (code.startsWith('zh-hant') ||
       code.startsWith('zh-tw') ||
       code.startsWith('zh-hk') ||
       code.startsWith('zh-mo'));
    if (primary) return isHant(primary);
    return isHant(fallback);
  }
  get i18n(){ return this.isTraditionalChinese ? I18N.zh : I18N.en; }
  get titleText(){ return this.i18n.title; }
  get leadSectionLabel(){ return this.i18n.leadCaps; }
  get summaryText(){ const { summary } = this.i18n; return summary(this.sortLabel, this.pollingSeconds, this._limitSize); }
  get searchPlaceholder(){ return this.i18n.searchPlaceholder; }
  get leadNameLabel(){ return this.i18n.leadName; }
  get companyLabel(){ return this.i18n.company; }
  get phoneLabel(){ return this.i18n.phone; }
  get valueIndicatorLabel(){ return this.i18n.valueIndicator; }
  get createdDateLabel(){ return this.i18n.createdDate; }
  get statusLabel(){ return this.i18n.status; }
  get noDataText(){ return this.i18n.noData; }
  get popoverTitle(){ return this.i18n.popoverTitle; }
  get popoverAriaLabel(){ return this.i18n.popoverAria; }
  get classificationLabel(){ return this.i18n.classification; }
  get keyTopicsLabel(){ return this.i18n.keyTopics; }
  get reasonLabel(){ return this.i18n.reason; }
  get replyLabel(){ return this.i18n.reply; }
  get sortLabel(){
    const map = this.i18n.sortFields || {};
    const dir = this.sortDirection === 'asc' ? this.i18n.sortDirAsc : this.i18n.sortDirDesc;
    const field = map[this.sortBy] || this.sortBy;
    const open = this.isTraditionalChinese ? '（' : ' (';
    const close = this.isTraditionalChinese ? '）' : ')';
    return `${field}${open}${dir}${close}`;
  }
  get pollingSeconds(){
    const s = this._pollingMs / 1000;
    return Number.isInteger(s) ? s : Math.round(s*10)/10;
  }
  get hasLeads(){ return Array.isArray(this.leads) && this.leads.length>0; }
  get popoverStyle(){ return `top:${this.popover.top}px; left:${this.popover.left}px;`; }
  get popoverClass(){ return `slds-popover slds-popover_large ${this.popover.nubbin} cm-popover`; }
  get ringHeaderStyle() {
    const color = this._ringColor(this.popover.row.aiScore);
    const pct = Math.max(0, Math.min(100, Math.round(this.popover.pct || 0)));
    return `--p:${pct};--ring:${color}`;
  }

  // ========== 生命週期 ==========
  connectedCallback(){ this.loadOnce(); this._restartTimer(); this._updateSortArrows(); }
  disconnectedCallback(){ this._clearTimer(); if(this._rafId){ cancelAnimationFrame(this._rafId); } }

  _restartTimer(){ this._clearTimer(); this._timer = window.setInterval(()=>this.loadOnce(), this._pollingMs); }
  _clearTimer(){ if(this._timer){ window.clearInterval(this._timer); this._timer=null; } }


  // ========== 取數/轉換（列表只需靜態欄位） ==========
 
  async loadOnce() {
    const FETCH_WINDOW = 50;
    try {
      const fetchCount = Math.max(FETCH_WINDOW, this._limitSize);
      const data = await fetchLatestLeads({ limitSize: fetchCount }) || [];
      const now = new Date();
  
      // （保持你既有的欄位轉換）
      this.leads = data.map(d => {
        const score = d.aiScore == null ? null : Number(d.aiScore);
        return {
          ...d,
          aiScoreDisplay: score == null ? 'NA' : (Math.round(score * 10) / 10).toString(),
          createdRel: this._toRelativeTime(d.createdDate, now),
          scoreTitle: score == null ? 'AI Score: N/A' : `AI Score: ${Math.round(score)}`,
          starArray: this._starsOf(score).map((filled, i) => ({
            filled, keyFilled: `${d.id}-${i}-f`, keyEmpty: `${d.id}-${i}-e`
          }))
        };
      });
  
      // 如果後端沒有按建立時間 DESC 回來，保險起見先排一次
      this.leads.sort((a,b) => new Date(b.createdDate) - new Date(a.createdDate));
  
      // 只保留最新 50 筆作為搜尋＋排序的資料池
      this.leads = this.leads.slice(0, FETCH_WINDOW);
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error('Load leads failed', e);
    }
  }

  // 0~100 -> 0~5 顆星
  _starsOf(score){
    if (score === null) return [false,false,false,false,false];
    const cnt = Math.max(0, Math.min(5, Math.round(Number(score)/20)));
    return Array.from({length:5},(_,i)=> i<cnt);
  }

  // 相對時間
  // 以秒/分/時/天/週/月/年顯示；超過一年改成絕對日期
_toRelativeTime(iso, now = new Date()) {
  try {
    const d = new Date(iso);
    let diff = Math.floor((now - d) / 1000);        // 秒
    if (!Number.isFinite(diff)) return '';

    // 未來時間（偶發時區或資料誤差）
    if (diff < 0) diff = 0;

    const minute = 60;
    const hour   = 60 * minute;
    const day    = 24 * hour;
    const week   = 7  * day;
    const month  = 30 * day;
    const year   = 365 * day;

    const rel = this.i18n.relative || {};
    const suffix = rel.suffix || '';
    const fmt = (value, unit) => `${value}${unit}${suffix}`;

    if (diff < 60)                 return fmt(diff, rel.second || 's');
    if (diff < hour)               return fmt(Math.floor(diff/minute), rel.minute || 'm');
    if (diff < day)                return fmt(Math.floor(diff/hour), rel.hour || 'h');
    if (diff < week)               return fmt(Math.floor(diff/day), rel.day || 'd');
    if (diff < month)              return fmt(Math.floor(diff/week), rel.week || 'w');
    if (diff < year)               return fmt(Math.floor(diff/month), rel.month || 'mo');

    // 超過一年顯示絕對日期（或改成 `${Math.floor(diff/year)}年前`）
    const y = d.getFullYear();
    const m = d.getMonth() + 1;
    const dd = d.getDate();
    return `${y}/${m}/${dd}`;
  } catch {
    return '';
  }
}

  // ========== 搜尋、排序 ==========
  handleKeywordChange(e){ this.keyword = e.target.value || ''; }

  get popoverHasScore() {
  const s = this.popover?.row?.aiScore;
  return s !== null && s !== undefined;
}

get filteredLeads() {
  const kw = (this.keyword || '').trim().toLowerCase();

  // 搜尋（在 50 筆池內）
  const pool = !kw ? this.leads : this.leads.filter(r =>
    (r.name || '').toLowerCase().includes(kw) ||
    (r.company || '').toLowerCase().includes(kw) ||
    (r.phone || '').toLowerCase().includes(kw) ||
    (r.status || '').toLowerCase().includes(kw)
  );

  // 排序（同你原本邏輯）
  const dir = this.sortDirection === 'asc' ? 1 : -1;
  const normalizeScore = s => (s === null || s === undefined ? null : Number(s));
  const sorted = pool.slice().sort((a, b) => {
    if (this.sortBy === 'aiScore') {
      const sa = normalizeScore(a.aiScore), sb = normalizeScore(b.aiScore);
      if (sa === null && sb === null) return (new Date(a.createdDate) - new Date(b.createdDate)) * dir * -1;
      if (sa === null) return 1;
      if (sb === null) return -1;
      if (sa !== sb) return (sa > sb ? 1 : -1) * dir;
    } else if (this.sortBy === 'createdDate') {
      return (new Date(a.createdDate) - new Date(b.createdDate)) * dir;
    } else if (this.sortBy === 'name') {
      const an = (a.name || '').toLowerCase(), bn = (b.name || '').toLowerCase();
      if (an !== bn) return (an > bn ? 1 : -1) * dir;
    }
    // 次排序：CreatedDate DESC
    return new Date(b.createdDate) - new Date(a.createdDate);
  });

  // 只顯示 limitSize 筆，並重算顯示序號
  return sorted.slice(0, this._limitSize).map((r, i) => ({ ...r, displayIndex: i + 1 }));
}

  handleSort(e){
    const field = e.currentTarget.dataset.field;
    if(!field) return;
    if(this.sortBy === field){
      this.sortDirection = this.sortDirection==='asc' ? 'desc' : 'asc';
    }else{
      this.sortBy = field;
      this.sortDirection = (field==='name') ? 'asc' : 'desc';
    }
    this._updateSortArrows();
  }
  handleSortKeydown(e){ if(e.key==='Enter' || e.key===' '){ e.preventDefault(); this.handleSort(e); } }
  _updateSortArrows(){
    this.nameSortArrow    = (this.sortBy==='name')       ? (this.sortDirection==='asc'?'▲':'▼') : '';
    this.aiScoreSortArrow = (this.sortBy==='aiScore')     ? (this.sortDirection==='asc'?'▲':'▼') : '';
    this.createdSortArrow = (this.sortBy==='createdDate') ? (this.sortDirection==='asc'?'▲':'▼') : '';
  }

  // ========== 導覽 ==========
  handleNavigate(e){
    e.preventDefault();
    e.stopPropagation();
    const recordId = e.currentTarget.dataset.id;
    const href = e.currentTarget.getAttribute('href');
    try{
      this[NavigationMixin.Navigate]({
        type:'standard__recordPage',
        attributes:{ recordId, objectApiName:'Lead', actionName:'view' }
      });
    }catch(err){
      if(href){ window.location.href = href; }
    }
  }
  handleLinkKeydown(e){ if(e.key==='Enter' || e.key===' ') this.handleNavigate(e); }

  // ========== Popover（僅此顯示動畫） ==========
  handleScoreEnter = (evt) => {
    if (this._hideTimer) { clearTimeout(this._hideTimer); this._hideTimer = null; }
    if (this._rafId) { cancelAnimationFrame(this._rafId); this._rafId = null; }
  
    const id = evt.currentTarget.dataset.id;
    const row = (this.filteredLeads || []).find(r => r.id === id);
    if(!row) return;
  
    // 位置
    const r = evt.currentTarget.getBoundingClientRect();
    const gap = 12, popW=448, popH=360;
    let top  = r.top + (r.height/2) - (popH/3);
    let left = r.right + gap;
    const maxLeft = window.innerWidth - (popW + 16);
    const maxTop  = window.innerHeight - (popH + 16);
    top  = Math.max(8, Math.min(top,  maxTop));
    left = Math.max(8, Math.min(left, maxLeft));
  
    const score = row.aiScore == null ? null : Number(row.aiScore);
    const target = score == null ? null : Math.max(0, Math.min(100, Math.round(score))); // 0~100 整數
    const targetPct = target ?? 0;
  
    // 初始 Popover 狀態
    this.popover = {
      visible: true, top, left, nubbin:'slds-nubbin_left',
      row,
      scoreAnimated: score == null ? 'NA' : '0',
      pct: 0
    };
    if (score == null) return; // NA 不跑動畫
  
    // ✅ 碼錶式：整數跳動 + 圓環同步掃動
    const duration = 800; // ms
    const start = performance.now();
    let lastShown = -1;
  
    const step = (ts) => {
      const t = Math.min(1, (ts - start) / duration);
      const eased = 1 - Math.pow(1 - t, 3); // easeOutCubic
      const currVal = Math.min(target, Math.floor(eased * target)); // 整數跳
      const currPct = Math.min(targetPct, Math.floor(eased * targetPct));
  
      // 僅在數字變更時 setState，避免 re-render 太頻繁
      if (currVal !== lastShown || this.popover.pct !== currPct) {
        this.popover = { ...this.popover, scoreAnimated: String(currVal), pct: currPct };
        lastShown = currVal;
      }
  
      if (t < 1) this._rafId = requestAnimationFrame(step);
      else this._rafId = null;
    };
    this._rafId = requestAnimationFrame(step);
  };

  handleScoreLeave = () => {
    this._hideTimer = setTimeout(() => {
      if (this._rafId) { cancelAnimationFrame(this._rafId); this._rafId = null; }
      this.popover = { visible:false, top:0, left:0, nubbin:'slds-nubbin_left', row:{}, scoreAnimated:'', pct:0 };
      this._hideTimer = null;
    }, 120);
  }
  cancelHide = () => { if (this._hideTimer) { clearTimeout(this._hideTimer); this._hideTimer = null; } }

  // 圓環顏色（Popover 用）
  _ringColor(score){
    if (score == null) return '#9ca3af';
    if (score >= 80) return '#059669';   // 綠
    if (score >= 60) return '#2563eb';   // 藍
    if (score >= 40) return '#d97706';   // 橘
    return '#6b7280';                    // 深灰
  }
}