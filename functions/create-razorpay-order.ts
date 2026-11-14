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
    const keyId = Deno.env.get('RAZORPAY_KEY_ID');
    const keySecret = Deno.env.get('RAZORPAY_KEY_SECRET');

    if (!keyId || !keySecret) {
      return new Response(JSON.stringify({ error: 'Razorpay keys not configured' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    const body = await req.json().catch(() => ({}));
    const { email, storage, billingCycle, amountInr } = body;

    if (!amountInr || amountInr <= 0) {
      return new Response(JSON.stringify({ error: 'Valid amount is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // Razorpay amounts are in smallest currency sub-units (paise for INR: 100 paise = 1 INR)
    const amountInPaise = Math.round(amountInr * 100);

    const authHeader = 'Basic ' + btoa(`${keyId}:${keySecret}`);
    const receiptId = `rcpt_${Date.now()}`;

    const rzpRes = await fetch('https://api.razorpay.com/v1/orders', {
      method: 'POST',
      headers: {
        'Authorization': authHeader,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        amount: amountInPaise,
        currency: 'INR',
        receipt: receiptId,
        notes: {
          email: email || '',
          storage: storage || '',
          billingCycle: billingCycle || ''
        }
      })
    });

    const orderData = await rzpRes.json();

    if (!rzpRes.ok) {
      return new Response(JSON.stringify({ error: orderData.error?.description || 'Failed to create Razorpay order' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    return new Response(JSON.stringify({
      orderId: orderData.id,
      amount: orderData.amount,
      currency: orderData.currency,
      keyId: keyId
    }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });

  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message || 'Internal server error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
}
