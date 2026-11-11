export default async function(req: Request): Promise<Response> {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, apikey'
  };

  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    const url = new URL(req.url);
    const action = url.searchParams.get('action'); // 'create', 'check', 'respond', 'pending'

    const insforgeUrl = Deno.env.get('INSFORGE_URL') || Deno.env.get('INSFORGE_BASE_URL') || 'https://26u7vqfh.us-east.insforge.app';
    const insforgeAnonKey = Deno.env.get('INSFORGE_ANON_KEY') || Deno.env.get('ANON_KEY') || '';

    if (action === 'create') {
      // Browser creates a pairing code (e.g. 988 932)
      const body = await req.json().catch(() => ({}));
      const email = body.email;
      const deviceInfo = body.deviceInfo || 'Chrome on Mac';
      if (!email) {
        return new Response(JSON.stringify({ error: 'email is required' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      // Generate 6 digit code formatted as "XXX XXX"
      const num1 = Math.floor(100 + Math.random() * 900);
      const num2 = Math.floor(100 + Math.random() * 900);
      const code = `${num1} ${num2}`;

      const insertRes = await fetch(`${insforgeUrl}/api/database/records/device_pairing_requests`, {
        method: 'POST',
        headers: {
          'apikey': insforgeAnonKey,
          'Authorization': `Bearer ${insforgeAnonKey}`,
          'Content-Type': 'application/json',
          'Prefer': 'return=representation'
        },
        body: JSON.stringify({
          user_email: email,
          code: code,
          device_info: deviceInfo,
          status: 'pending'
        })
      });

      const inserted = await insertRes.json().catch(() => []);
      const record = Array.isArray(inserted) ? inserted[0] : inserted;

      return new Response(JSON.stringify({
        success: true,
        id: record?.id,
        code: code,
        deviceInfo: deviceInfo
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    if (action === 'check') {
      // Browser polls to see if Mac app approved the request
      const id = url.searchParams.get('id');
      const code = url.searchParams.get('code');
      const email = url.searchParams.get('email');

      let queryUrl = `${insforgeUrl}/api/database/records/device_pairing_requests?limit=1&order=created_at.desc`;
      if (id) {
        queryUrl += `&id=eq.${encodeURIComponent(id)}`;
      } else if (email && code) {
        queryUrl += `&user_email=eq.${encodeURIComponent(email)}&code=eq.${encodeURIComponent(code)}`;
      }

      const res = await fetch(queryUrl, {
        headers: {
          'apikey': insforgeAnonKey,
          'Authorization': `Bearer ${insforgeAnonKey}`
        }
      });
      const records = await res.json().catch(() => []);
      const reqRecord = Array.isArray(records) && records.length > 0 ? records[0] : null;

      if (!reqRecord) {
        return new Response(JSON.stringify({ status: 'not_found' }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      return new Response(JSON.stringify({
        id: reqRecord.id,
        status: reqRecord.status, // 'pending', 'approved', 'rejected'
        code: reqRecord.code,
        encryptionKey: reqRecord.encryption_key
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    if (action === 'pending') {
      // Mac App polls for any pending pairing requests
      const email = url.searchParams.get('email');
      let queryUrl = `${insforgeUrl}/api/database/records/device_pairing_requests?status=eq.pending&order=created_at.desc&limit=1`;
      if (email && email.trim().length > 0) {
        queryUrl += `&user_email=eq.${encodeURIComponent(email.trim())}`;
      }

      const res = await fetch(queryUrl, {
        headers: {
          'apikey': insforgeAnonKey,
          'Authorization': `Bearer ${insforgeAnonKey}`
        }
      });
      const records = await res.json().catch(() => []);
      return new Response(JSON.stringify({
        requests: Array.isArray(records) ? records : []
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    if (action === 'respond') {
      // Mac app responds: status = 'approved' or 'rejected'
      const body = await req.json().catch(() => ({}));
      const id = body.id;
      const status = body.status; // 'approved' or 'rejected'
      const encryptionKey = body.encryptionKey || '';

      if (!id || !status) {
        return new Response(JSON.stringify({ error: 'id and status are required' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      const patchRes = await fetch(`${insforgeUrl}/api/database/records/device_pairing_requests?id=eq.${encodeURIComponent(id)}`, {
        method: 'PATCH',
        headers: {
          'apikey': insforgeAnonKey,
          'Authorization': `Bearer ${insforgeAnonKey}`,
          'Content-Type': 'application/json',
          'Prefer': 'return=representation'
        },
        body: JSON.stringify({
          status: status,
          encryption_key: encryptionKey,
          updated_at: new Date().toISOString()
        })
      });

      const updated = await patchRes.json().catch(() => ({}));
      return new Response(JSON.stringify({ success: true, updated }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    return new Response(JSON.stringify({ error: 'Invalid action. Supported: create, check, pending, respond' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
}
