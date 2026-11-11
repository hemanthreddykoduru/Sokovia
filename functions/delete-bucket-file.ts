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
    let bucketName = '';
    let fileName = '';

    if (req.method === 'POST') {
      const body = await req.json().catch(() => ({}));
      email = body.email || '';
      bucketName = body.bucketName || '';
      fileName = body.fileName || '';
    } else {
      const url = new URL(req.url);
      email = url.searchParams.get('email') || '';
      bucketName = url.searchParams.get('bucketName') || '';
      fileName = url.searchParams.get('fileName') || '';
    }

    if (!fileName) {
      return new Response(JSON.stringify({ error: 'fileName is required.' }), {
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

    if (email && !bucketName) {
      const { data: userBuckets } = await client.database
        .from('user_buckets')
        .select('bucket_name, sokovia_users!inner(email)')
        .eq('sokovia_users.email', email)
        .limit(1);

      if (userBuckets && userBuckets.length > 0) {
        bucketName = userBuckets[0].bucket_name;
      }
    }

    if (!bucketName) {
      return new Response(JSON.stringify({ error: 'Bucket not found.' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // Call Cloudflare R2 API to delete object
    if (cfToken) {
      const deleteRes = await fetch(
        `https://api.cloudflare.com/client/v4/accounts/${cfAccountId}/r2/buckets/${bucketName}/objects/${encodeURIComponent(fileName)}`,
        {
          method: 'DELETE',
          headers: {
            'Authorization': `Bearer ${cfToken}`
          }
        }
      );
    }

    // Update InsForge file_catalog & user_buckets
    await client.database.rpc('sync_file_catalog', {
      p_user_id: null,
      p_bucket_name: bucketName,
      p_path: fileName,
      p_size: 0,
      p_is_delete: true
    }).catch(() => {});

    return new Response(JSON.stringify({ success: true, deleted: fileName }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });

  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message || 'Server error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
}

