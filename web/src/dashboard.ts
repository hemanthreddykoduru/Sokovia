import { insforge } from './client';

export interface BucketFile {
  name: string;
  size?: number;
  etag?: string;
  lastModified?: string;
}

let currentUserEmail: string = '';
let currentBucketName: string = '';
let currentUserName: string = '';
let loadedFiles: BucketFile[] = [];
let pairingPollTimer: any = null;
let currentPairingId: string | null = null;

export async function initDashboard(): Promise<void> {
  // 1. Wait for OAuth callback to complete if returning from Google OAuth
  if (insforge && insforge.auth && (insforge.auth as any).authCallbackHandled) {
    try { await (insforge.auth as any).authCallbackHandled; } catch (e) {}
  }

  // 2. Resolve active authenticated user
  let authenticatedUser: { email: string; name?: string } | null = null;

  // Check query parameter (from email login redirect)
  const params = new URLSearchParams(window.location.search);
  const qEmail = params.get('email');
  if (qEmail && qEmail.includes('@')) {
    authenticatedUser = { email: qEmail, name: '' };
    localStorage.setItem('sokovia_session', JSON.stringify({ email: qEmail }));
    document.cookie = "sokovia_user=" + encodeURIComponent(qEmail) + "; path=/; max-age=86400; SameSite=Lax";
  }

  // Check live InsForge session (Google OAuth or active session)
  if (!authenticatedUser) {
    try {
      const { data, error } = await insforge.auth.getCurrentUser();
      if (!error && data && data.user && data.user.email) {
        authenticatedUser = {
          email: data.user.email,
          name: (data.user as any).name || (data.user.profile && (data.user.profile as any).name) || ''
        };
        localStorage.setItem('sokovia_session', JSON.stringify({ email: data.user.email, name: authenticatedUser.name }));
        document.cookie = "sokovia_user=" + encodeURIComponent(data.user.email) + "; path=/; max-age=86400; SameSite=Lax";
      }
    } catch (e) {}
  }

  // Check cookie
  if (!authenticatedUser) {
    const matchCookie = document.cookie.match(/(?:^|;\s*)sokovia_user=([^;]+)/);
    if (matchCookie && matchCookie[1]) {
      try {
        const cookieEmail = decodeURIComponent(matchCookie[1]);
        if (cookieEmail && cookieEmail.includes('@')) {
          authenticatedUser = { email: cookieEmail, name: '' };
        }
      } catch (e) {}
    }
  }

  // Check stored session in localStorage
  if (!authenticatedUser) {
    const stored = localStorage.getItem('sokovia_session');
    if (stored) {
      try {
        const parsed = JSON.parse(stored);
        if (parsed && parsed.email) {
          authenticatedUser = { email: parsed.email, name: parsed.name || '' };
        }
      } catch (e) {}
    }
  }

  // If still not authenticated, redirect to login
  if (!authenticatedUser || !authenticatedUser.email) {
    window.location.replace('/#auth-section');
    return;
  }

  currentUserEmail = authenticatedUser.email;
  currentUserName = authenticatedUser.name || '';

  // Clean URL: strip .html extension and query parameters cleanly from address bar
  const currentPath = window.location.pathname;
  const cleanPath = currentPath.endsWith('.html') ? currentPath.replace(/\.html$/, '') : currentPath;
  if (window.location.search || currentPath.endsWith('.html')) {
    window.history.replaceState({}, document.title, cleanPath);
  }

  // Update UI Greetings
  const namePart = currentUserName || currentUserEmail.split('@')[0];
  const capitalized = namePart.charAt(0).toUpperCase() + namePart.slice(1);
  const firstLetter = capitalized.charAt(0);

  const greetingTitle = document.getElementById('greetingTitle');
  const userAvatarLetter = document.getElementById('userAvatarLetter');
  const dockAvatarLetter = document.getElementById('dockAvatarLetter');
  const settingsAvatarLetter = document.getElementById('settingsAvatarLetter');
  const settingsUserName = document.getElementById('settingsUserName');
  const settingsUserEmail = document.getElementById('settingsUserEmail');

  if (greetingTitle) greetingTitle.textContent = `good evening, ${namePart.toLowerCase()}`;
  if (userAvatarLetter) userAvatarLetter.textContent = firstLetter;
  if (dockAvatarLetter) dockAvatarLetter.textContent = firstLetter;
  if (settingsAvatarLetter) settingsAvatarLetter.textContent = firstLetter;
  if (settingsUserName) settingsUserName.textContent = capitalized;
  if (settingsUserEmail) settingsUserEmail.textContent = currentUserEmail;

  // 2. Render from instant cache first if available
  try {
    const cachedBucket = localStorage.getItem('sokovia_bucket_' + currentUserEmail);
    if (cachedBucket) {
      const parsed = JSON.parse(cachedBucket);
      if (parsed && parsed.name) {
        currentBucketName = parsed.name;
        const bucketEl = document.getElementById('settingsBucketName');
        if (bucketEl) bucketEl.textContent = currentBucketName;
      }
    }
    const cachedFiles = localStorage.getItem('sokovia_files_' + currentUserEmail);
    if (cachedFiles) {
      const parsed = JSON.parse(cachedFiles);
      if (parsed && parsed.files) {
        loadedFiles = parsed.files;
        renderFilesUI(parsed.files, parsed.folders || [], parsed.storageUsedBytes || 0);
      }
    }
  } catch (e) {}

  // 3. Initiate device pairing verification & load fresh data concurrently
  initDevicePairing();
  loadBucketData();
}

export async function initDevicePairing(): Promise<void> {
  if (sessionStorage.getItem('sokovia_unlocked') === 'true') {
    return;
  }

  const unlockCard = document.getElementById('deviceUnlockCard');
  const profileCard = document.getElementById('mainProfileCard');
  const filesCard = document.getElementById('recentSection');
  const foldersCard = document.getElementById('foldersSection');

  if (unlockCard) unlockCard.style.display = 'block';
  if (profileCard) profileCard.style.opacity = '0.4';
  if (filesCard) filesCard.style.opacity = '0.3';
  if (foldersCard) foldersCard.style.opacity = '0.3';

  try {
    const res = await fetch('https://26u7vqfh.function2.insforge.app/device-pairing?action=create', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: currentUserEmail, deviceInfo: 'Chrome on Mac' })
    });
    const data = await res.json();
    if (data.success && data.code) {
      currentPairingId = data.id;
      const codeVal = document.getElementById('pairingCodeValue');
      if (codeVal) codeVal.textContent = data.code;
      startPairingPoll(data.id);
    }
  } catch (err) {
    console.error('Pairing creation error:', err);
  }
}

export function startPairingPoll(id: string): void {
  if (pairingPollTimer) clearInterval(pairingPollTimer);
  pairingPollTimer = setInterval(async () => {
    try {
      const res = await fetch(`https://26u7vqfh.function2.insforge.app/device-pairing?action=check&id=${encodeURIComponent(id)}`);
      const data = await res.json();
      if (data && data.status === 'approved') {
        clearInterval(pairingPollTimer);
        sessionStorage.setItem('sokovia_unlocked', 'true');
        dismissUnlockScreen(true);
      } else if (data && data.status === 'rejected') {
        clearInterval(pairingPollTimer);
        alert('Device access was declined on your Mac.');
        dismissUnlockScreen(false);
      }
    } catch (e) {}
  }, 2000);
}

export function dismissUnlockScreen(success = true): void {
  if (pairingPollTimer) clearInterval(pairingPollTimer);
  const unlockCard = document.getElementById('deviceUnlockCard');
  const profileCard = document.getElementById('mainProfileCard');
  const filesCard = document.getElementById('recentSection');
  const foldersCard = document.getElementById('foldersSection');

  if (unlockCard) unlockCard.style.display = 'none';
  if (profileCard) profileCard.style.opacity = '1';
  if (filesCard) filesCard.style.opacity = '1';
  if (foldersCard) foldersCard.style.opacity = '1';
}

export async function loadBucketData(): Promise<void> {
  try {
    const cachedBucket = localStorage.getItem('sokovia_bucket_' + currentUserEmail);
    let knownBucketName = currentBucketName;
    if (!knownBucketName && cachedBucket) {
      try { knownBucketName = JSON.parse(cachedBucket).name; } catch (e) {}
    }

    const fetchFilesPromise = knownBucketName ? fetchFiles() : null;

    const res = await fetch('https://26u7vqfh.function2.insforge.app/provision-user-bucket', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: currentUserEmail, displayName: currentUserName })
    });
    const data = await res.json();

    if (data.success && data.bucket) {
      currentBucketName = data.bucket.name;
      localStorage.setItem('sokovia_bucket_' + currentUserEmail, JSON.stringify(data.bucket));
      const bucketEl = document.getElementById('settingsBucketName');
      if (bucketEl) bucketEl.textContent = currentBucketName;
      if (!fetchFilesPromise) {
        await fetchFiles();
      } else {
        await fetchFilesPromise;
      }
    }
  } catch (err) {
    console.error('Bucket load error:', err);
  }
}

export async function fetchFiles(): Promise<void> {
  if (!currentBucketName) return;

  try {
    const res = await fetch('https://26u7vqfh.function2.insforge.app/list-bucket-files', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ bucketName: currentBucketName, email: currentUserEmail })
    });
    const data = await res.json();

    if (data.success && data.files) {
      loadedFiles = data.files;
      localStorage.setItem('sokovia_files_' + currentUserEmail, JSON.stringify(data));
      renderFilesUI(data.files, data.folders || [], data.storageUsedBytes || 0);
    }
  } catch (err) {
    console.error('Files fetch error:', err);
  }
}

export function renderFilesUI(files: BucketFile[], folders: string[], totalBytes: number): void {
  const maxBytes = 5 * 1024 * 1024 * 1024;
  const pct = Math.min(100, Math.max(1, (totalBytes / maxBytes) * 100));
  const freeBytes = Math.max(0, maxBytes - totalBytes);

  const barFill = document.getElementById('storageBarFill');
  const usedText = document.getElementById('storageUsedText');
  const freeText = document.getElementById('storageFreeText');
  const countsSub = document.getElementById('statsCountsSub');

  if (barFill) barFill.style.width = pct + '%';
  if (usedText) usedText.textContent = formatBytes(totalBytes);
  if (freeText) freeText.textContent = formatBytes(freeBytes) + ' free';
  if (countsSub) countsSub.textContent = `${files.length} files in bucket`;

  const foldersSection = document.getElementById('foldersSection');
  const foldersGrid = document.getElementById('foldersGrid');
  if (folders && folders.length > 0) {
    if (foldersSection) foldersSection.style.display = 'block';
    if (foldersGrid) {
      foldersGrid.innerHTML = folders.map(folderName => `
        <div class="folder-card" onclick="filterFolder('${escapeHtml(folderName)}')">
          <span class="folder-icon">📁</span>
          <div class="folder-title">${escapeHtml(folderName)}</div>
          <div class="folder-sub">folder</div>
        </div>
      `).join('');
    }
  } else {
    if (foldersSection) foldersSection.style.display = 'none';
  }

  const renderList = (elId: string) => {
    const el = document.getElementById(elId);
    if (!el) return;

    if (files.length === 0) {
      el.innerHTML = `
        <div class="empty-state">
          <h3>no files yet</h3>
          <p style="font-size: 13px; color: var(--ink-2); margin-top: 4px;">
            drop files into your sokovia drive in finder, or click + add files.
          </p>
        </div>
      `;
      return;
    }

    el.innerHTML = files.map(f => {
      const icon = getFileIcon(f.name);
      return `
        <div class="file-row">
          <div class="file-main">
            <div class="file-badge-icon">${icon}</div>
            <div class="file-text-col">
              <div class="file-title">${escapeHtml(f.name)}</div>
              <div class="file-subpath">in ${escapeHtml(currentBucketName)}</div>
            </div>
          </div>
          <div class="file-aside">
            <span>${formatBytes(f.size || 0)}</span>
            <button class="file-delete-btn" onclick="handleDeleteFile(event, '${escapeHtml(f.name)}')">✕</button>
          </div>
        </div>
      `;
    }).join('');
  };

  renderList('homeFilesList');
  renderList('allFilesList');
}

export async function handleFileUpload(e: Event): Promise<void> {
  const target = e.target as HTMLInputElement;
  const files = target?.files;
  if (!files || files.length === 0 || !currentBucketName) return;

  const tag = document.getElementById('syncStatusTag');
  if (tag) tag.textContent = 'Uploading...';

  for (let i = 0; i < files.length; i++) {
    const file = files[i];
    try {
      await fetch(`https://26u7vqfh.function2.insforge.app/upload-bucket-file?bucketName=${encodeURIComponent(currentBucketName)}&fileName=${encodeURIComponent(file.name)}`, {
        method: 'PUT',
        headers: {
          'Content-Type': file.type || 'application/octet-stream'
        },
        body: file
      });
    } catch (err) {
      console.error('File upload error:', err);
    }
  }

  if (tag) tag.textContent = '✓ Synced';
  await fetchFiles();
}

export async function handleDeleteFile(e: Event, fileName: string): Promise<void> {
  e.stopPropagation();
  if (!confirm(`Delete "${fileName}" from your bucket?`)) return;

  try {
    await fetch(`https://26u7vqfh.function2.insforge.app/delete-bucket-file`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ bucketName: currentBucketName, fileName })
    });
    await fetchFiles();
  } catch (err: any) {
    alert('Delete error: ' + err.message);
  }
}

export function switchDock(tab: string): void {
  const tabs = ['home', 'files', 'shared', 'plan', 'account'];
  tabs.forEach(t => {
    const view = document.getElementById('view' + t.charAt(0).toUpperCase() + t.slice(1));
    const btn = document.getElementById('dockBtn' + t.charAt(0).toUpperCase() + t.slice(1));
    if (view) view.className = 'tab-content' + (t === tab ? ' active' : '');
    if (btn) btn.className = 'dock-btn' + (t === tab ? ' active' : '');
  });
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

export function filterFolder(folderName: string): void {
  switchDock('files');
}

export function formatBytes(bytes: number): string {
  if (!bytes || bytes === 0) return '0 KB';
  const k = 1024;
  const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

export function getFileIcon(name: string): string {
  const l = name.toLowerCase();
  if (l.endsWith('.mov') || l.endsWith('.mp4') || l.endsWith('.mkv')) return '🎬';
  if (l.endsWith('.zip') || l.endsWith('.tar') || l.endsWith('.gz')) return '📦';
  if (l.endsWith('.psd') || l.endsWith('.ai') || l.endsWith('.fig')) return '🎨';
  if (l.endsWith('.wav') || l.endsWith('.mp3')) return '🎙️';
  if (l.endsWith('.jpg') || l.endsWith('.png') || l.endsWith('.arw')) return '📸';
  if (l.endsWith('.pdf')) return '📑';
  if (l.endsWith('.json') || l.endsWith('.js') || l.endsWith('.ts')) return '📄';
  return '📄';
}

export function escapeHtml(t: string): string {
  return t.replace(/[&<>"']/g, m => (({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' } as Record<string, string>)[m]));
}

export async function handleSignOut(): Promise<void> {
  try {
    localStorage.removeItem('sokovia_session');
    document.cookie = "sokovia_user=; path=/; max-age=0";
    await insforge.auth.signOut();
  } catch (e) {}
  window.location.replace('/');
}

// Plan Tiers configuration matching interactive slider
export interface PlanTier {
  storage: string;
  monthlyPrice: number;
  yearlyTotal: number;
  yearlyEquivalentStr: string;
}

export const PLAN_TIERS: PlanTier[] = [
  { storage: '500 GB', monthlyPrice: 5, yearlyTotal: 50, yearlyEquivalentStr: '$4.17' },
  { storage: '1 TB', monthlyPrice: 10, yearlyTotal: 100, yearlyEquivalentStr: '$8.33' },
  { storage: '2 TB', monthlyPrice: 20, yearlyTotal: 200, yearlyEquivalentStr: '$16.67' },
  { storage: '3 TB', monthlyPrice: 30, yearlyTotal: 300, yearlyEquivalentStr: '$25' },
  { storage: '5 TB', monthlyPrice: 50, yearlyTotal: 500, yearlyEquivalentStr: '$41.67' },
  { storage: '10 TB', monthlyPrice: 100, yearlyTotal: 1000, yearlyEquivalentStr: '$83.33' },
  { storage: '20 TB', monthlyPrice: 200, yearlyTotal: 2000, yearlyEquivalentStr: '$166.67' },
  { storage: '30 TB', monthlyPrice: 300, yearlyTotal: 3000, yearlyEquivalentStr: '$250' },
];

let currentPlanStep = 0;
let currentBillingCycle: 'monthly' | 'yearly' = 'monthly';

export function updatePlanSlider(stepValue: string | number): void {
  const step = parseInt(stepValue.toString(), 10);
  currentPlanStep = Math.max(0, Math.min(step, PLAN_TIERS.length - 1));
  renderPlanUI();
}

export function setPlanStep(step: number): void {
  currentPlanStep = Math.max(0, Math.min(step, PLAN_TIERS.length - 1));
  const slider = document.getElementById('planStorageSlider') as HTMLInputElement | null;
  if (slider) slider.value = currentPlanStep.toString();
  renderPlanUI();
}

export function setPlanBilling(cycle: 'monthly' | 'yearly'): void {
  currentBillingCycle = cycle;
  const btnMonthly = document.getElementById('btnPlanMonthly');
  const btnYearly = document.getElementById('btnPlanYearly');
  if (btnMonthly && btnYearly) {
    if (cycle === 'monthly') {
      btnMonthly.classList.add('active');
      btnYearly.classList.remove('active');
    } else {
      btnYearly.classList.add('active');
      btnMonthly.classList.remove('active');
    }
  }
  renderPlanUI();
}

function renderPlanUI(): void {
  const tier = PLAN_TIERS[currentPlanStep];
  const priceDisplay = document.getElementById('planPriceDisplay');
  const storageDisplay = document.getElementById('planStorageDisplay');
  const billingPeriod = document.getElementById('planBillingPeriod');
  const yearlySubtext = document.getElementById('planYearlySubtext');
  const yearlyPerMonthText = document.getElementById('planYearlyPerMonthText');
  const slider = document.getElementById('planStorageSlider') as HTMLInputElement | null;

  if (slider) {
    const percent = (currentPlanStep / (PLAN_TIERS.length - 1)) * 100;
    slider.style.background = `linear-gradient(to right, #000000 0%, #000000 ${percent}%, #e5e5ea ${percent}%, #e5e5ea 100%)`;
  }

  if (storageDisplay) {
    storageDisplay.textContent = tier.storage;
  }

  if (priceDisplay && billingPeriod) {
    if (currentBillingCycle === 'monthly') {
      priceDisplay.textContent = `$${tier.monthlyPrice.toLocaleString()}`;
      billingPeriod.textContent = '/ month';
      if (yearlySubtext) yearlySubtext.style.display = 'none';
    } else {
      priceDisplay.textContent = `$${tier.yearlyTotal.toLocaleString()}`;
      billingPeriod.textContent = '/ year';
      if (yearlySubtext) {
        yearlySubtext.style.display = 'block';
        if (yearlyPerMonthText) {
          yearlyPerMonthText.textContent = `${tier.yearlyEquivalentStr}/month`;
        }
      }
    }
  }

  // Update tick highlight
  const ticks = document.querySelectorAll('#planTicksContainer span');
  ticks.forEach((tick, idx) => {
    if (idx === currentPlanStep) {
      tick.classList.add('active');
    } else {
      tick.classList.remove('active');
    }
  });
}

export function handleContinueToPayment(): void {
  const tier = PLAN_TIERS[currentPlanStep];
  const cycleText = currentBillingCycle === 'yearly' ? 'billed annually' : 'billed monthly';
  const price = currentBillingCycle === 'yearly' ? `$${tier.yearlyTotal}/yr` : `$${tier.monthlyPrice}/mo`;
  alert(`Upgrade to ${tier.storage} plan (${price}, ${cycleText})\n\nRedirecting to checkout...`);
}

// Bind handlers to global window for inline HTML onclick/onsubmit attributes
if (typeof window !== 'undefined') {
  const w = window as any;
  w.switchDock = switchDock;
  w.filterFolder = filterFolder;
  w.handleFileUpload = handleFileUpload;
  w.handleDeleteFile = handleDeleteFile;
  w.handleSignOut = handleSignOut;
  w.dismissUnlockScreen = dismissUnlockScreen;
  w.updatePlanSlider = updatePlanSlider;
  w.setPlanStep = setPlanStep;
  w.setPlanBilling = setPlanBilling;
  w.handleContinueToPayment = handleContinueToPayment;

  window.addEventListener('DOMContentLoaded', () => {
    initDashboard();
    renderPlanUI();
  });
}
