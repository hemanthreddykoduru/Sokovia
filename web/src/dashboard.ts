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
let currentUserRecoveryKey: string = '';
let currentPlanQuotaBytes: number = 5 * 1024 * 1024 * 1024; // Default 5 GB free
let currentActivePlanStorage: string = '5 GB free';
let currentActiveBillingCycle: string = 'free';
let loadedFiles: BucketFile[] = [];
let pairingPollTimer: any = null;
let currentPairingId: string | null = null;

export async function initDashboard(): Promise<void> {
  const urlParams = new URLSearchParams(window.location.search);
  const oauthCode = urlParams.get('insforge_code');

  // If returning from Google OAuth with code, perform exchange immediately
  if (oauthCode) {
    try {
      const storedVerifier = sessionStorage.getItem('insforge_pkce_verifier') || localStorage.getItem('insforge_pkce_verifier');
      if (storedVerifier) {
        sessionStorage.setItem('insforge_pkce_verifier', storedVerifier);
      }
      if (insforge && insforge.auth) {
        const { data, error } = await insforge.auth.exchangeOAuthCode(oauthCode, storedVerifier || undefined);
        if (error) {
          console.error('OAuth exchange error:', error);
        } else if (data && data.user) {
          const userObj = data.user;
          const uEmail = userObj.email;
          const uName = (userObj as any).name || (userObj.profile && (userObj.profile as any).name) || '';
          localStorage.setItem('sokovia_session', JSON.stringify({ email: uEmail, name: uName, user: userObj }));
          document.cookie = "sokovia_user=" + encodeURIComponent(uEmail) + "; path=/; max-age=86400; SameSite=Lax";
          
          // Clear verifier once safely exchanged
          sessionStorage.removeItem('insforge_pkce_verifier');
          localStorage.removeItem('insforge_pkce_verifier');

          // Auto-provision bucket if first time
          try {
            await fetch('https://26u7vqfh.function2.insforge.app/provision-user-bucket', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ email: uEmail, displayName: uName })
            });
          } catch (bErr) {}

          // Notify native Mac app via deep link
          try {
            const frame = document.createElement('iframe');
            frame.style.display = 'none';
            frame.src = 'sokovia://auth?email=' + encodeURIComponent(uEmail) + '&name=' + encodeURIComponent(uName);
            document.body.appendChild(frame);
            setTimeout(() => { document.body.removeChild(frame); }, 500);
          } catch (e) {}
        }
      }
    } catch (e) {
      console.warn('OAuth exchange handler notice:', e);
    }
  }

  // 1. Wait for OAuth callback to complete if returning from Google OAuth
  if (insforge && insforge.auth && (insforge.auth as any).authCallbackHandled) {
    try { await (insforge.auth as any).authCallbackHandled; } catch (e) {}
  }

  // 2. Resolve active authenticated user
  let authenticatedUser: { email: string; name?: string } | null = null;

  // Check query parameter (from email login redirect)
  const params = new URLSearchParams(window.location.search);
  const qEmail = params.get('email');
  const isNewSignup = params.get('new_signup') === '1' || sessionStorage.getItem('sokovia_just_registered') === 'true';
  if (isNewSignup) {
    sessionStorage.removeItem('sokovia_just_registered');
  }
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
    window.location.replace('/login');
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
    // Check cached active subscription first to avoid 5 GB flicker
    const cachedSub = localStorage.getItem('sokovia_sub_' + currentUserEmail);
    if (cachedSub) {
      const parsedSub = JSON.parse(cachedSub);
      if (parsedSub && parsedSub.plan_storage) {
        currentActivePlanStorage = parsedSub.plan_storage;
        currentActiveBillingCycle = parsedSub.billing_cycle || 'monthly';
        const s = parsedSub.plan_storage.toUpperCase();
        if (s.includes('TB')) {
          currentPlanQuotaBytes = parseFloat(s.replace('TB', '').trim()) * 1024 * 1024 * 1024 * 1024;
        } else if (s.includes('GB')) {
          currentPlanQuotaBytes = parseFloat(s.replace('GB', '').trim()) * 1024 * 1024 * 1024;
        }
        applyActivePlanUI(parsedSub.plan_storage, currentActiveBillingCycle, parsedSub.amount_inr);
      }
    }

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

  // 3. Initiate device pairing verification, load subscription & fresh data concurrently
  initDevicePairing();
  loadUserSubscription();
  loadBucketData();
  initRecoveryKeyFlow(isNewSignup);
}

function generateStandardRecoveryKey(): string {
  const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  const groups: string[] = [];
  const array = new Uint8Array(48);
  if (typeof window !== 'undefined' && window.crypto) {
    window.crypto.getRandomValues(array);
  } else {
    for (let i = 0; i < 48; i++) array[i] = Math.floor(Math.random() * 256);
  }
  for (let g = 0; g < 12; g++) {
    let grp = '';
    for (let i = 0; i < 4; i++) {
      grp += chars[array[g * 4 + i] % chars.length];
    }
    groups.push(grp);
  }
  return groups.join('-');
}

export async function initRecoveryKeyFlow(forceShow = false): Promise<void> {
  try {
    let key = localStorage.getItem('sokovia_recovery_' + currentUserEmail) || '';

    // Check backend RPC
    if (!key && insforge && insforge.database) {
      const { data } = await insforge.database.rpc('get_user_recovery_key', { p_email: currentUserEmail });
      if (data && typeof data === 'string' && data.length > 10) {
        key = data;
      }
    }

    // If still no key, generate one now
    if (!key) {
      key = generateStandardRecoveryKey();
      if (insforge && insforge.database) {
        try {
          await insforge.database.rpc('set_user_recovery_key', {
            p_email: currentUserEmail,
            p_recovery_key: key
          });
        } catch (e) {}
      }
    }

    currentUserRecoveryKey = key;
    localStorage.setItem('sokovia_recovery_' + currentUserEmail, key);

    // Format today's date like "4 November 2026"
    const today = new Date();
    const formattedDate = today.toLocaleDateString('en-GB', {
      day: 'numeric',
      month: 'long',
      year: 'numeric'
    });

    const codeDisplay = document.getElementById('recoveryKeyCodeDisplay');
    const dateDisplay = document.getElementById('recoveryKeyDateDisplay');
    if (codeDisplay) codeDisplay.textContent = currentUserRecoveryKey;
    if (dateDisplay) dateDisplay.textContent = formattedDate;

    // Check if user has already acknowledged their key
    const hasAcknowledged = localStorage.getItem('sokovia_recovery_acked_' + currentUserEmail) === 'true';

    // Show automatically and trigger PDF download on first account creation
    if (forceShow || !hasAcknowledged) {
      showRecoveryKeyModal();
      // Automatically download PDF for user on first creation (just like Helumi)
      const hasAutoDownloaded = localStorage.getItem('sokovia_recovery_downloaded_' + currentUserEmail) === 'true';
      if (!hasAutoDownloaded) {
        localStorage.setItem('sokovia_recovery_downloaded_' + currentUserEmail, 'true');
        setTimeout(() => {
          downloadRecoveryKeyPdf();
        }, 500);
      }
    }
  } catch (err) {
    console.warn('Recovery key flow notice:', err);
  }
}

export function showRecoveryKeyModal(): void {
  const modal = document.getElementById('recoveryKeyModal');
  const codeDisplay = document.getElementById('recoveryKeyCodeDisplay');
  const dateDisplay = document.getElementById('recoveryKeyDateDisplay');

  if (codeDisplay && currentUserRecoveryKey) {
    codeDisplay.textContent = currentUserRecoveryKey;
  }
  if (dateDisplay && !dateDisplay.textContent) {
    dateDisplay.textContent = new Date().toLocaleDateString('en-GB', {
      day: 'numeric',
      month: 'long',
      year: 'numeric'
    });
  }
  if (modal) {
    modal.classList.add('active');
  }
}

export function dismissRecoveryKeyModal(): void {
  const modal = document.getElementById('recoveryKeyModal');
  if (modal) {
    modal.classList.remove('active');
  }
  if (currentUserEmail) {
    localStorage.setItem('sokovia_recovery_acked_' + currentUserEmail, 'true');
  }
}

export function promptRecoveryKeyUnlock(): void {
  const modal = document.getElementById('enterRecoveryKeyModal');
  const input = document.getElementById('recoveryKeyInput') as HTMLTextAreaElement | null;
  const errorEl = document.getElementById('recoveryKeyError');
  if (errorEl) errorEl.style.display = 'none';
  if (input) {
    input.value = '';
    setTimeout(() => input.focus(), 100);
  }
  if (modal) {
    modal.classList.add('active');
  }
}

export function closeEnterRecoveryKeyModal(): void {
  const modal = document.getElementById('enterRecoveryKeyModal');
  if (modal) {
    modal.classList.remove('active');
  }
}

export async function handleRecoveryKeySubmit(e: Event): Promise<void> {
  e.preventDefault();
  const input = document.getElementById('recoveryKeyInput') as HTMLTextAreaElement | null;
  const errorEl = document.getElementById('recoveryKeyError');
  const submitBtn = document.getElementById('btnSubmitRecoveryKey') as HTMLButtonElement | null;

  const enteredKey = input?.value.trim().toUpperCase().replace(/[\s\r\n]+/g, '') || '';
  if (!enteredKey) {
    if (errorEl) {
      errorEl.textContent = 'Please enter your recovery key.';
      errorEl.style.display = 'block';
    }
    return;
  }

  if (submitBtn) {
    submitBtn.disabled = true;
    submitBtn.textContent = 'verifying key...';
  }

  try {
    let validKey = currentUserRecoveryKey;
    if (!validKey) {
      validKey = localStorage.getItem('sokovia_recovery_' + currentUserEmail) || '';
    }
    if (!validKey && insforge && insforge.database) {
      const { data } = await insforge.database.rpc('get_user_recovery_key', { p_email: currentUserEmail });
      if (data && typeof data === 'string') {
        validKey = data;
        currentUserRecoveryKey = data;
      }
    }

    // Normalize keys for clean comparison (remove spaces/dashes if user pasted raw)
    const normalizedEntered = enteredKey.replace(/[^A-Z0-9]/g, '');
    const normalizedTarget = (validKey || '').replace(/[^A-Z0-9]/g, '');

    // Allow unlock if matches target key, or has valid standard recovery key format
    const isValid = (normalizedTarget && normalizedEntered === normalizedTarget) || 
                    (!normalizedTarget && normalizedEntered.length >= 32);

    if (isValid) {
      sessionStorage.setItem('sokovia_unlocked', 'true');
      closeEnterRecoveryKeyModal();
      dismissUnlockScreen(true);
    } else {
      if (errorEl) {
        errorEl.textContent = 'Invalid recovery key. Please check the code and try again.';
        errorEl.style.display = 'block';
      }
    }
  } catch (err: any) {
    if (errorEl) {
      errorEl.textContent = err.message || 'Error validating recovery key.';
      errorEl.style.display = 'block';
    }
  } finally {
    if (submitBtn) {
      submitBtn.disabled = false;
      submitBtn.textContent = 'unlock files';
    }
  }
}

export function downloadRecoveryKeyPdf(): void {
  const code = (currentUserRecoveryKey || document.getElementById('recoveryKeyCodeDisplay')?.textContent || '').trim();
  const dateStr = (document.getElementById('recoveryKeyDateDisplay')?.textContent || '').trim() ||
    new Date().toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' });

  if (!code) return;

  const pdfBytes = generateHelumiRecoveryPdf(code, dateStr);
  const blob = new Blob([pdfBytes], { type: 'application/pdf' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'Sokovia-Recovery-Key.pdf';
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function generateHelumiRecoveryPdf(key: string, dateStr: string): Uint8Array {
  // Helumi layout matches 540 x 246 pt
  const parts = key.split('-');
  let line1 = key;
  let line2 = '';
  if (parts.length >= 9) {
    line1 = parts.slice(0, 9).join('-') + '-';
    line2 = parts.slice(9).join('-');
  }

  const title = 'Sokovia Recovery Key';
  const footer = 'Keep this safe. It opens your Sokovia files.';

  let stream = 'BT\n';
  stream += '/F1 22 Tf\n48 177 Td\n(' + title.replace(/([()\\])/g, '\\$1') + ') Tj\n';
  stream += '0 -38 Td\n/F2 15 Tf\n(' + line1.replace(/([()\\])/g, '\\$1') + ') Tj\n';
  if (line2) {
    stream += '0 -19 Td\n(' + line2.replace(/([()\\])/g, '\\$1') + ') Tj\n';
    stream += '0 -35 Td\n';
  } else {
    stream += '0 -54 Td\n';
  }
  stream += '/F1 13 Tf\n0.5 0.5 0.5 rg\n(' + dateStr.replace(/([()\\])/g, '\\$1') + ') Tj\n';
  stream += '0 -34 Td\n0 0 0 rg\n(' + footer.replace(/([()\\])/g, '\\$1') + ') Tj\n';
  stream += 'ET\n';

  const encoder = new TextEncoder();
  const streamBytes = encoder.encode(stream);
  const streamLen = streamBytes.length;

  const chunks: Uint8Array[] = [];
  const offsets: number[] = [];
  let currentOffset = 0;

  function pushChunk(bytes: Uint8Array) {
    chunks.push(bytes);
    currentOffset += bytes.length;
  }

  function addObj(contentStr: string, bodyBytes?: Uint8Array) {
    offsets.push(currentOffset);
    pushChunk(encoder.encode(contentStr));
    if (bodyBytes) {
      pushChunk(bodyBytes);
      pushChunk(encoder.encode('\nendstream\nendobj\n'));
    }
  }

  pushChunk(encoder.encode('%PDF-1.4\n%\xe2\xe3\xcf\xd3\n'));

  addObj('1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n');
  addObj('2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n');
  addObj('3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 540 246] /Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> /Contents 6 0 R >>\nendobj\n');
  addObj('4 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n');
  addObj('5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>\nendobj\n');
  addObj(`6 0 obj\n<< /Length ${streamLen} >>\nstream\n`, streamBytes);

  const xrefOffset = currentOffset;
  let xref = `xref\n0 ${offsets.length + 1}\n0000000000 65535 f \n`;
  for (const off of offsets) {
    xref += off.toString().padStart(10, '0') + ' 00000 n \n';
  }
  xref += `trailer\n<< /Size ${offsets.length + 1} /Root 1 0 R >>\nstartxref\n${xrefOffset}\n%%EOF\n`;
  pushChunk(encoder.encode(xref));

  const totalLen = chunks.reduce((acc, c) => acc + c.length, 0);
  const result = new Uint8Array(totalLen);
  let pos = 0;
  for (const c of chunks) {
    result.set(c, pos);
    pos += c.length;
  }
  return result;
}

export function copyRecoveryKey(): void {
  const code = currentUserRecoveryKey || document.getElementById('recoveryKeyCodeDisplay')?.textContent || '';
  if (code && navigator.clipboard) {
    navigator.clipboard.writeText(code.trim());
    const copyBtn = document.getElementById('btnCopyRecovery');
    if (copyBtn) {
      const orig = copyBtn.textContent;
      copyBtn.textContent = 'copied!';
      setTimeout(() => { copyBtn.textContent = orig; }, 1800);
    }
  }
}

export async function loadUserSubscription(): Promise<void> {
  if (!currentUserEmail) return;

  try {
    const { data, error } = await insforge.database
      .from('user_subscriptions')
      .select('*')
      .eq('email', currentUserEmail)
      .order('created_at', { ascending: false })
      .limit(1);

    if (!error && data && data.length > 0) {
      const sub = data[0];
      localStorage.setItem('sokovia_sub_' + currentUserEmail, JSON.stringify(sub));
      currentActivePlanStorage = sub.plan_storage;
      currentActiveBillingCycle = sub.billing_cycle;

      // Parse plan storage to bytes
      const s = sub.plan_storage.toUpperCase();
      if (s.includes('TB')) {
        const tb = parseFloat(s.replace('TB', '').trim());
        currentPlanQuotaBytes = tb * 1024 * 1024 * 1024 * 1024;
      } else if (s.includes('GB')) {
        const gb = parseFloat(s.replace('GB', '').trim());
        currentPlanQuotaBytes = gb * 1024 * 1024 * 1024;
      }

      applyActivePlanUI(sub.plan_storage, sub.billing_cycle, sub.amount_inr);
    }
  } catch (e) {
    console.error('Error loading subscription:', e);
  }
}

export function applyActivePlanUI(storage: string, cycle: string, amountInr?: number): void {
  // 1. Quota label on Home bar
  const quotaLabel = document.getElementById('currentPlanQuotaLabel');
  if (quotaLabel) quotaLabel.textContent = storage;

  // 2. Active plan card display on Plan Tab
  const activeCard = document.getElementById('activeSubscriptionCard');
  const sliderCard = document.getElementById('planSliderCard');
  const activeTitle = document.getElementById('activeSubStorageTitle');
  const activeDesc = document.getElementById('activeSubMetaDesc');

  if (activeCard && sliderCard) {
    activeCard.style.display = 'block';
    sliderCard.style.display = 'none'; // Hide slider by default since plan is active
    if (activeTitle) activeTitle.textContent = storage;
    if (activeDesc) {
      activeDesc.textContent = `Billed ${cycle} via Razorpay ${amountInr ? `(₹${amountInr.toLocaleString()})` : ''} · renews automatically`;
    }
  }

  // 3. Account Settings tab
  const planTitle = document.getElementById('accountPlanTitle');
  const planSub = document.getElementById('accountPlanSub');
  if (planTitle) planTitle.textContent = `${storage} Plan (Active)`;
  if (planSub) planSub.textContent = `Billed ${cycle} via Razorpay ${amountInr ? `(₹${amountInr.toLocaleString()})` : ''}`;

  // 4. Update slider step if matched
  const matchedIdx = PLAN_TIERS.findIndex(t => t.storage.toLowerCase() === storage.toLowerCase());
  if (matchedIdx !== -1) {
    setPlanStep(matchedIdx);
  }

  // Re-render storage meter with new quota
  renderFilesUI(loadedFiles, [], totalStorageUsedBytes);
}

export function toggleUpgradeSlider(): void {
  const activeCard = document.getElementById('activeSubscriptionCard');
  const sliderCard = document.getElementById('planSliderCard');
  const heading = document.getElementById('planSliderHeading');
  const btn = document.getElementById('btnToggleUpgrade');

  if (sliderCard && activeCard) {
    if (sliderCard.style.display === 'none') {
      sliderCard.style.display = 'block';
      if (heading) heading.textContent = 'select your upgrade tier';
      if (btn) btn.textContent = 'hide upgrade options';
      sliderCard.scrollIntoView({ behavior: 'smooth' });
    } else {
      sliderCard.style.display = 'none';
      if (btn) btn.textContent = 'upgrade to more space';
    }
  }
}

let totalStorageUsedBytes: number = 0;

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

export function showPaymentSuccessModal(storage: string, amountInr: number): void {
  const modal = document.getElementById('paymentSuccessModal');
  const desc = document.getElementById('paymentSuccessDesc');
  if (desc) {
    desc.textContent = `Your ${storage} plan (₹${amountInr.toLocaleString()}) is now active. Your storage bar and macOS Finder drive have been upgraded.`;
  }
  if (modal) {
    modal.style.display = 'flex';
  }
}

export function closePaymentSuccessModal(): void {
  const modal = document.getElementById('paymentSuccessModal');
  if (modal) modal.style.display = 'none';
  window.location.reload();
}

export function renderFilesUI(files: BucketFile[], folders: string[], totalBytes: number): void {
  totalStorageUsedBytes = totalBytes;
  const maxBytes = currentPlanQuotaBytes || (5 * 1024 * 1024 * 1024);
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

  // Dynamic button text: only allow upgrades; lock current plan and lower plans
  const submitBtn = document.getElementById('planSubmitBtn') as HTMLButtonElement | null;
  if (submitBtn) {
    // Find index of user's active plan
    const activeIdx = PLAN_TIERS.findIndex(t => 
      currentActivePlanStorage.toLowerCase().includes(t.storage.toLowerCase())
    );

    const isCurrentPlan = activeIdx !== -1 && activeIdx === currentPlanStep &&
                          currentActiveBillingCycle === currentBillingCycle;

    if (isCurrentPlan) {
      submitBtn.textContent = 'current active plan';
      submitBtn.style.opacity = '0.5';
      submitBtn.style.pointerEvents = 'none';
      submitBtn.style.background = '#6e6e73';
    } else if (activeIdx !== -1 && currentPlanStep < activeIdx) {
      submitBtn.textContent = 'plan already exceeds this tier';
      submitBtn.style.opacity = '0.5';
      submitBtn.style.pointerEvents = 'none';
      submitBtn.style.background = '#6e6e73';
    } else {
      submitBtn.textContent = 'upgrade plan';
      submitBtn.style.opacity = '1';
      submitBtn.style.pointerEvents = 'auto';
      submitBtn.style.background = '#000000';
    }
  }
}

export async function handleContinueToPayment(): Promise<void> {
  const tier = PLAN_TIERS[currentPlanStep];
  const submitBtn = document.getElementById('planSubmitBtn') as HTMLButtonElement | null;
  const originalText = submitBtn ? submitBtn.textContent : 'continue to payment';

  try {
    if (submitBtn) {
      submitBtn.disabled = true;
      submitBtn.textContent = 'opening secure checkout...';
    }

    const email = currentUserEmail || (function() {
      try {
        const s = localStorage.getItem('sokovia_session');
        if (s) {
          const parsed = JSON.parse(s);
          if (parsed && parsed.email) return parsed.email;
        }
      } catch (e) {}
      return localStorage.getItem('sokovia_email') || 'user@sokovia.dev';
    })();
    const amountUsd = currentBillingCycle === 'yearly' ? tier.yearlyTotal : tier.monthlyPrice;
    
    // Convert USD to INR (at standard ~85 INR per USD) for Razorpay test gateway
    const amountInr = Math.round(amountUsd * 85);

    // Call our InsForge edge function to create Razorpay Order
    const orderRes = await fetch('https://26u7vqfh.function2.insforge.app/create-razorpay-order', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email,
        storage: tier.storage,
        billingCycle: currentBillingCycle,
        amountInr
      })
    });

    const orderData = await orderRes.json();
    if (!orderRes.ok || !orderData.orderId) {
      throw new Error(orderData.error || 'Failed to initiate Razorpay checkout');
    }

    // Open Razorpay Standard Checkout Modal
    const rzp = (window as any).Razorpay;
    if (!rzp) {
      throw new Error('Razorpay SDK failed to load. Please disable ad-blockers or refresh.');
    }

    const options = {
      key: orderData.keyId,
      amount: orderData.amount,
      currency: orderData.currency || 'INR',
      name: 'Sokovia',
      description: `${tier.storage} Plan (${currentBillingCycle}) - ₹${amountInr.toLocaleString()}`,
      image: '/favicon.png',
      order_id: orderData.orderId,
      prefill: {
        email: email,
        name: currentUserName || ''
      },
      theme: {
        color: '#000000'
      },
      handler: async function (response: any) {
        try {
          if (submitBtn) submitBtn.textContent = 'verifying payment...';

          const verifyRes = await fetch('https://26u7vqfh.function2.insforge.app/verify-razorpay-payment', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              razorpay_order_id: response.razorpay_order_id,
              razorpay_payment_id: response.razorpay_payment_id,
              razorpay_signature: response.razorpay_signature,
              email,
              storage: tier.storage,
              billingCycle: currentBillingCycle,
              amountInr
            })
          });

          const verifyData = await verifyRes.json();
          if (verifyRes.ok && verifyData.success) {
            applyActivePlanUI(tier.storage, currentBillingCycle, amountInr);
            showPaymentSuccessModal(tier.storage, amountInr);
          } else {
            alert('Payment received, but verification returned an error: ' + (verifyData.error || 'Unknown error'));
          }
        } catch (vErr: any) {
          alert('Error completing payment verification: ' + vErr.message);
        } finally {
          if (submitBtn) {
            submitBtn.disabled = false;
            submitBtn.textContent = originalText;
          }
        }
      },
      modal: {
        ondismiss: function () {
          if (submitBtn) {
            submitBtn.disabled = false;
            submitBtn.textContent = originalText;
          }
        }
      }
    };

    const paymentInstance = new rzp(options);
    paymentInstance.open();

  } catch (err: any) {
    alert('Checkout error: ' + err.message);
    if (submitBtn) {
      submitBtn.disabled = false;
      submitBtn.textContent = originalText;
    }
  }
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
  w.closePaymentSuccessModal = closePaymentSuccessModal;
  w.toggleUpgradeSlider = toggleUpgradeSlider;
  w.showRecoveryKeyModal = showRecoveryKeyModal;
  w.dismissRecoveryKeyModal = dismissRecoveryKeyModal;
  w.copyRecoveryKey = copyRecoveryKey;
  w.downloadRecoveryKeyPdf = downloadRecoveryKeyPdf;
  w.promptRecoveryKeyUnlock = promptRecoveryKeyUnlock;
  w.closeEnterRecoveryKeyModal = closeEnterRecoveryKeyModal;
  w.handleRecoveryKeySubmit = handleRecoveryKeySubmit;

  window.addEventListener('DOMContentLoaded', () => {
    initDashboard();
    renderPlanUI();
  });
}
