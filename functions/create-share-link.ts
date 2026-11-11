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

    // Generate a unique token for the share link
    const shareToken = crypto.randomUUID().replace(/-/g, '').substring(0, 16);

    // Store in public.file_shares table
    const { data: shareRecord, error: shareErr } = await client.database
      .from('file_shares')
      .insert([{
        share_token: shareToken,
        bucket_name: bucketName,
        file_name: fileName,
        created_by_email: email,
        view_count: 0
      }])
      .select();

    const publicUrl = `https://26u7vqfh.function2.insforge.app/get-shared-file?token=${shareToken}`;

    return new Response(JSON.stringify({
      success: true,
      shareToken,
      shareUrl: publicUrl,
      fileName,
      bucketName
    }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });

  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message || 'Share link error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
}

