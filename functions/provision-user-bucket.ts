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
    let email = '';
    let displayName = '';

    if (req.method === 'POST') {
      const body = await req.json().catch(() => ({}));
      email = body.email || '';
      displayName = body.displayName || '';
    } else {
      const url = new URL(req.url);
      email = url.searchParams.get('email') || '';
      displayName = url.searchParams.get('displayName') || '';
    }

    if (!email) {
      return new Response(JSON.stringify({ error: 'Email parameter is required.' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    const insforgeUrl = Deno.env.get('INSFORGE_BASE_URL') || '';
    const apiKey = Deno.env.get('API_KEY') || Deno.env.get('ANON_KEY') || '';
    const cfAccountId = Deno.env.get('CF_ACCOUNT_ID') || '';
    const cfToken = Deno.env.get('CF_R2_TOKEN') || '';

    const client = createClient({
      baseUrl: insforgeUrl,
      anonKey: apiKey
    });

    // 1. Call database RPC to get or allocate bucket name
    const { data: dbData, error: dbError } = await client.database
      .rpc('get_or_create_user_bucket', {
        p_email: email,
        p_display_name: displayName,
        p_r2_endpoint: `https://${cfAccountId}.r2.cloudflarestorage.com`,
        p_r2_account_id: cfAccountId
      });

    if (dbError || !dbData || dbData.length === 0) {
      return new Response(JSON.stringify({ error: dbError?.message || 'Failed to allocate bucket in database.' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    const userBucket = dbData[0];
    const bucketName = userBucket.bucket_name;

    // 2. Ensure R2 bucket exists in Cloudflare
    if (cfToken) {
      try {
        const cfRes = await fetch(`https://api.cloudflare.com/client/v4/accounts/${cfAccountId}/r2/buckets`, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${cfToken}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({ name: bucketName })
        });
        const cfResult = await cfRes.json().catch(() => ({}));
        // If error is 10006 / bucket already exists, that's completely fine
      } catch (err) {
        console.warn('Cloudflare R2 bucket check notice:', err);
      }
    }

    return new Response(JSON.stringify({
      success: true,
      user: {
        id: userBucket.user_id,
        email: userBucket.email
      },
      bucket: {
        name: bucketName,
        endpoint: userBucket.r2_endpoint,
        accountId: userBucket.r2_account_id,
        storageUsedBytes: Number(userBucket.storage_used_bytes || 0)
      }
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

