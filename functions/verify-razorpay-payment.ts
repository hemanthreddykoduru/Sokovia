import { createClient } from 'npm:@insforge/sdk';

export default async function(req: Request): Promise<Response> {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization'
  };

  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    const keySecret = Deno.env.get('RAZORPAY_KEY_SECRET');
    const insforgeUrl = Deno.env.get('INSFORGE_BASE_URL') || '';
    const apiKey = Deno.env.get('API_KEY') || Deno.env.get('ANON_KEY') || '';

    const body = await req.json().catch(() => ({}));
    const {
      razorpay_order_id,
      razorpay_payment_id,
      razorpay_signature,
      email,
      storage,
      billingCycle,
      amountInr
    } = body;

    if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
      return new Response(JSON.stringify({ error: 'Missing payment signature details' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // Verify HMAC SHA256 Signature
    const encoder = new TextEncoder();
    const dataToSign = `${razorpay_order_id}|${razorpay_payment_id}`;
    const key = await crypto.subtle.importKey(
      'raw',
      encoder.encode(keySecret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign']
    );

    const signatureBuffer = await crypto.subtle.sign(
      'HMAC',
      key,
      encoder.encode(dataToSign)
    );

    const generatedSignature = Array.from(new Uint8Array(signatureBuffer))
      .map(b => b.toString(16).padStart(2, '0'))
      .join('');

    if (generatedSignature !== razorpay_signature) {
      return new Response(JSON.stringify({ error: 'Invalid payment signature' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // Signature verified! Record subscription in database
    const client = createClient({
      baseUrl: insforgeUrl,
      anonKey: apiKey
    });

    await client.database.from('user_subscriptions').insert([{
      email: email || 'anonymous',
      plan_storage: storage || '500 GB',
      billing_cycle: billingCycle || 'monthly',
      amount_inr: amountInr || 0,
      razorpay_order_id: razorpay_order_id,
      razorpay_payment_id: razorpay_payment_id,
      status: 'active'
    }]);

    return new Response(JSON.stringify({
      success: true,
      message: 'Payment verified and plan activated!'
    }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });

  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message || 'Payment verification failed' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
}
