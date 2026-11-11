import { createClient } from '@insforge/sdk';

export const insforge = createClient({
  baseUrl: 'https://26u7vqfh.us-east.insforge.app',
  anonKey: 'anon_e454796e3cc024e7eb2a436ad67da1ac94ba3e4963f7d56349c900c7d25ddf68'
});

// Expose globally for any legacy bindings or devtools
if (typeof window !== 'undefined') {
  (window as any).insforge = insforge;
}
