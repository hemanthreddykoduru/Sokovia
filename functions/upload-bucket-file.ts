import { createClient } from 'npm:@insforge/sdk';

export default async function(req: Request): Promise<Response> {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, x-filename'
  };

  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    const url = new URL(req.url);
    const bucketName = url.searchParams.get('bucketName') || '';
    const fileName = url.searchParams.get('fileName') || req.headers.get('x-filename') || 'uploaded-file.bin';

    if (!bucketName) {
      return new Response(JSON.stringify({ error: 'bucketName is required.' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    const cfAccountId = Deno.env.get('CF_ACCOUNT_ID') || '';
    const cfToken = Deno.env.get('CF_R2_TOKEN') || '';

    const bodyBuffer = await req.arrayBuffer();

    // Upload directly to Cloudflare R2
    const uploadRes = await fetch(
      `https://api.cloudflare.com/client/v4/accounts/${cfAccountId}/r2/buckets/${bucketName}/objects/${encodeURIComponent(fileName)}`,
      {
        method: 'PUT',
        headers: {
          'Authorization': `Bearer ${cfToken}`,
          'Content-Type': req.headers.get('content-type') || 'application/octet-stream'
        },
        body: bodyBuffer
      }
    );

    const result = await uploadRes.json().catch(() => ({}));

    return new Response(JSON.stringify({ success: true, fileName, size: bodyBuffer.byteLength, result }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });

  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message || 'Upload error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
}

