import { insforge } from './client';

let currentMode: 'signup' | 'signin' = 'signup';
let targetEmail: string = '';
let targetName: string = '';

export async function checkExistingSession(): Promise<void> {
  try {
    let email = '';
    let name = '';
    const stored = localStorage.getItem('sokovia_session');
    if (stored) {
      try {
        const parsed = JSON.parse(stored);
        if (parsed && parsed.email) {
          email = parsed.email;
          name = parsed.name || '';
        }
      } catch (e) {}
    }

    if (!email) {
      const { data } = await insforge.auth.getCurrentUser();
      if (data && data.user && data.user.email) {
        email = data.user.email;
        name = (data.user as any).name || (data.user as any).user_metadata?.full_name || '';
      }
    }

    if (email) {
      // User is authenticated: DO NOT forcefully redirect away.
      // Keep the landing page visible and update buttons to allow easy navigation.
      const navAuthBtn = document.getElementById('navAuthBtn');
      if (navAuthBtn) {
        navAuthBtn.textContent = 'dashboard →';
        navAuthBtn.setAttribute('href', '/dashboard');
      }

      const authCard = document.querySelector('.auth-card');
      if (authCard) {
        const displayName = name || email.split('@')[0];
        const letter = (name || email)[0].toUpperCase();
        authCard.innerHTML = `
          <div style="text-align: center; padding: 20px 8px;">
            <div style="width: 54px; height: 54px; border-radius: 50%; background: #000; color: #fff; font-size: 20px; font-weight: 600; display: flex; align-items: center; justify-content: center; margin: 0 auto 16px auto; box-shadow: 0 4px 14px rgba(0,0,0,0.12);">
              ${letter}
            </div>
            <h2 style="font-size: 24px; margin-bottom: 6px; letter-spacing: -0.02em;">welcome back, ${displayName}</h2>
            <p class="card-desc" style="margin-bottom: 24px;">Signed in as <strong>${email}</strong>. Your private cloud drive is active.</p>
            <div style="display: flex; gap: 12px; justify-content: center; flex-wrap: wrap;">
              <a href="/dashboard" class="btn" style="text-decoration: none; padding: 11px 24px; font-size: 14.5px; font-weight: 500; display: inline-flex; align-items: center; gap: 8px; border-radius: 999px; background: #000; color: #fff;">
                <span>open dashboard</span>
                <span style="font-size: 16px;">→</span>
              </a>
              <button onclick="handleSignOut()" class="btn" style="background: transparent; color: var(--ink-2); border: 1px solid var(--border); padding: 11px 20px; font-size: 14.5px; border-radius: 999px; cursor: pointer;">
                sign out
              </button>
            </div>
          </div>
        `;
      }
    }
  } catch (err) {
    console.log('No active session:', err);
  }
}

export function switchTab(mode: 'signup' | 'signin'): void {
  currentMode = mode;
  const tabSignUp = document.getElementById('tabSignUp');
  const tabSignIn = document.getElementById('tabSignIn');
  if (tabSignUp) tabSignUp.className = 'auth-tab' + (mode === 'signup' ? ' active' : '');
  if (tabSignIn) tabSignIn.className = 'auth-tab' + (mode === 'signin' ? ' active' : '');

  const heading = document.getElementById('authHeading');
  const desc = document.getElementById('authDesc');
  const nameGroup = document.getElementById('nameGroup');
  const submitBtn = document.getElementById('sendCodeBtn') as HTMLButtonElement | null;

  if (mode === 'signup') {
    if (heading) heading.textContent = 'create your account';
    if (desc) desc.textContent = 'Enter your email to receive a verification code. Once verified, your isolated Cloudflare R2 bucket is provisioned automatically.';
    if (nameGroup) nameGroup.style.display = 'block';
    if (submitBtn) submitBtn.textContent = 'create account';
  } else {
    if (heading) heading.textContent = 'sign in to sokovia';
    if (desc) desc.textContent = 'Enter your email to receive a sign-in code and access your private bucket.';
    if (nameGroup) nameGroup.style.display = 'none';
    if (submitBtn) submitBtn.textContent = 'sign in with email';
  }
}

export async function handleGoogleAuth(): Promise<void> {
  try {
    await insforge.auth.signInWithOAuth('google', {
      redirectTo: window.location.origin + '/dashboard'
    });
  } catch (err: any) {
    alert('Google Sign-In: ' + (err.message || 'Error redirecting to Google.'));
  }
}

export async function handleSendCode(e: Event): Promise<void> {
  e.preventDefault();
  const emailInput = document.getElementById('authEmail') as HTMLInputElement | null;
  const nameInput = document.getElementById('authName') as HTMLInputElement | null;
  const btn = document.getElementById('sendCodeBtn') as HTMLButtonElement | null;
  const errEl = document.getElementById('sendCodeError');

  const email = emailInput?.value.trim() || '';
  const name = nameInput?.value.trim() || '';

  if (!email || !btn) return;

  targetEmail = email;
  targetName = name;
  if (errEl) errEl.style.display = 'none';
  btn.disabled = true;
  btn.textContent = 'sending code...';

  try {
    const { error } = await insforge.auth.signInWithOtp({ email });
    if (error) throw error;

    const authFormView = document.getElementById('authFormView');
    const verifyTargetEmail = document.getElementById('verifyTargetEmail');
    const verifyView = document.getElementById('verifyView');
    const otpCode = document.getElementById('otpCode') as HTMLInputElement | null;

    if (authFormView) authFormView.style.display = 'none';
    if (verifyTargetEmail) verifyTargetEmail.textContent = email;
    if (verifyView) verifyView.style.display = 'block';
    if (otpCode) otpCode.focus();
  } catch (err: any) {
    if (errEl) {
      errEl.textContent = err.message || 'Failed to send verification code. Please try again.';
      errEl.style.display = 'block';
    }
    btn.disabled = false;
    btn.textContent = currentMode === 'signup' ? 'create account' : 'sign in with email';
  }
}

export async function handleVerifyCode(e: Event): Promise<void> {
  e.preventDefault();
  const otpInput = document.getElementById('otpCode') as HTMLInputElement | null;
  const btn = document.getElementById('verifyBtn') as HTMLButtonElement | null;
  const errEl = document.getElementById('verifyError');

  const otp = otpInput?.value.trim() || '';
  if (!otp || !btn) return;

  btn.disabled = true;
  btn.textContent = 'verifying...';
  if (errEl) errEl.style.display = 'none';

  try {
    const { data, error } = await insforge.auth.verifyOtp({
      email: targetEmail,
      otp: otp,
      name: targetName || undefined
    });

    if (error) throw error;

    const sessionPayload = {
      accessToken: (data && data.accessToken) || '',
      user: (data && data.user) || { email: targetEmail, name: targetName },
      email: targetEmail,
      name: targetName || (data && data.user && (data.user as any).name) || ''
    };
    localStorage.setItem('sokovia_session', JSON.stringify(sessionPayload));
    document.cookie = "sokovia_user=" + encodeURIComponent(targetEmail) + "; path=/; max-age=86400; SameSite=Lax";

    btn.textContent = 'activating bucket...';
    await provisionUserBucket(targetEmail, targetName);

    window.location.href = '/dashboard?email=' + encodeURIComponent(targetEmail);
  } catch (err: any) {
    if (errEl) {
      errEl.textContent = err.message || 'Invalid or expired code. Please check your email and try again.';
      errEl.style.display = 'block';
    }
    btn.disabled = false;
    btn.textContent = 'verify & continue';
  }
}

export async function handleResendCode(): Promise<void> {
  if (!targetEmail) return;
  alert('Resending verification code to ' + targetEmail + '...');
  await insforge.auth.signInWithOtp({ email: targetEmail });
}

export function backToEmail(): void {
  const verifyView = document.getElementById('verifyView');
  const authFormView = document.getElementById('authFormView');
  const btn = document.getElementById('sendCodeBtn') as HTMLButtonElement | null;

  if (verifyView) verifyView.style.display = 'none';
  if (authFormView) authFormView.style.display = 'block';
  if (btn) {
    btn.disabled = false;
    btn.textContent = currentMode === 'signup' ? 'create account' : 'sign in with email';
  }
}

export async function provisionUserBucket(email: string, displayName?: string): Promise<any> {
  try {
    const res = await fetch('https://26u7vqfh.function2.insforge.app/provision-user-bucket', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, displayName })
    });
    return await res.json();
  } catch (err) {
    console.error('Bucket provision error:', err);
    return null;
  }
}

export async function handleSignOut(): Promise<void> {
  try {
    localStorage.removeItem('sokovia_session');
    await insforge.auth.signOut();
  } catch (err) {}
  window.location.reload();
}

// Interactive Landing Page Pricing Slider
export interface LandingPlanTier {
  storage: string;
  monthlyPrice: number;
  yearlyTotal: number;
  yearlyEquivalentStr: string;
}

export const LANDING_PLAN_TIERS: LandingPlanTier[] = [
  { storage: '500 GB', monthlyPrice: 5, yearlyTotal: 50, yearlyEquivalentStr: '$4.17' },
  { storage: '1 TB', monthlyPrice: 10, yearlyTotal: 100, yearlyEquivalentStr: '$8.33' },
  { storage: '2 TB', monthlyPrice: 20, yearlyTotal: 200, yearlyEquivalentStr: '$16.67' },
  { storage: '3 TB', monthlyPrice: 30, yearlyTotal: 300, yearlyEquivalentStr: '$25' },
  { storage: '5 TB', monthlyPrice: 50, yearlyTotal: 500, yearlyEquivalentStr: '$41.67' },
  { storage: '10 TB', monthlyPrice: 100, yearlyTotal: 1000, yearlyEquivalentStr: '$83.33' },
  { storage: '20 TB', monthlyPrice: 200, yearlyTotal: 2000, yearlyEquivalentStr: '$166.67' },
  { storage: '30 TB', monthlyPrice: 300, yearlyTotal: 3000, yearlyEquivalentStr: '$250' },
];

let landingPlanStep = 0;
let landingBillingCycle: 'monthly' | 'yearly' = 'monthly';

export function updateLandingSlider(val: string | number): void {
  landingPlanStep = Math.max(0, Math.min(parseInt(val.toString(), 10), LANDING_PLAN_TIERS.length - 1));
  renderLandingPlanUI();
}

export function setLandingStep(step: number): void {
  landingPlanStep = Math.max(0, Math.min(step, LANDING_PLAN_TIERS.length - 1));
  const slider = document.getElementById('landingStorageSlider') as HTMLInputElement | null;
  if (slider) slider.value = landingPlanStep.toString();
  renderLandingPlanUI();
}

export function setLandingBilling(cycle: 'monthly' | 'yearly'): void {
  landingBillingCycle = cycle;
  const btnMonthly = document.getElementById('btnLandingMonthly');
  const btnYearly = document.getElementById('btnLandingYearly');
  if (btnMonthly && btnYearly) {
    if (cycle === 'monthly') {
      btnMonthly.classList.add('active');
      btnYearly.classList.remove('active');
    } else {
      btnYearly.classList.add('active');
      btnMonthly.classList.remove('active');
    }
  }
  renderLandingPlanUI();
}

function renderLandingPlanUI(): void {
  const tier = LANDING_PLAN_TIERS[landingPlanStep];
  const priceDisplay = document.getElementById('landingPriceDisplay');
  const storageDisplay = document.getElementById('landingStorageDisplay');
  const billingPeriod = document.getElementById('landingBillingPeriod');
  const yearlySubtext = document.getElementById('landingYearlySubtext');
  const yearlyPerMonthText = document.getElementById('landingYearlyPerMonthText');
  const slider = document.getElementById('landingStorageSlider') as HTMLInputElement | null;

  if (slider) {
    const percent = (landingPlanStep / (LANDING_PLAN_TIERS.length - 1)) * 100;
    slider.style.background = `linear-gradient(to right, #000000 0%, #000000 ${percent}%, #e5e5ea ${percent}%, #e5e5ea 100%)`;
  }

  if (storageDisplay) {
    storageDisplay.textContent = tier.storage;
  }

  if (priceDisplay && billingPeriod) {
    if (landingBillingCycle === 'monthly') {
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

  const ticks = document.querySelectorAll('#landingTicksContainer span');
  ticks.forEach((tick, idx) => {
    if (idx === landingPlanStep) {
      tick.classList.add('active');
    } else {
      tick.classList.remove('active');
    }
  });
}

export function toggleFaq(el: HTMLElement): void {
  const item = el.closest('.faq-item');
  if (item) {
    item.classList.toggle('open');
  }
}

// Bind handlers to global window for inline HTML onclick/onsubmit attributes
if (typeof window !== 'undefined') {
  const w = window as any;
  w.switchTab = switchTab;
  w.handleGoogleAuth = handleGoogleAuth;
  w.handleSendCode = handleSendCode;
  w.handleVerifyCode = handleVerifyCode;
  w.handleResendCode = handleResendCode;
  w.backToEmail = backToEmail;
  w.handleSignOut = handleSignOut;
  w.updateLandingSlider = updateLandingSlider;
  w.setLandingStep = setLandingStep;
  w.setLandingBilling = setLandingBilling;
  w.toggleFaq = toggleFaq;

  window.addEventListener('DOMContentLoaded', () => {
    checkExistingSession();
    renderLandingPlanUI();
  });
}
