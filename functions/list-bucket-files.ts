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

    if (req.method === 'POST') {
      const body = await req.json().catch(() => ({}));
      email = body.email || '';
      bucketName = body.bucketName || '';
    } else {
      const url = new URL(req.url);
      email = url.searchParams.get('email') || '';
      bucketName = url.searchParams.get('bucketName') || '';
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
        .select('bucket_name, storage_used_bytes, file_count, sokovia_users!inner(email)')
        .eq('sokovia_users.email', email)
        .limit(1);

      if (userBuckets && userBuckets.length > 0) {
        bucketName = userBuckets[0].bucket_name;
      }
    }

    if (!bucketName) {
      return new Response(JSON.stringify({ error: 'Bucket not found for this user.' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // Helper to check if file is an unwanted macOS system / hidden file
    function isHiddenOrSystemFile(key: string): boolean {
      const parts = key.split('/');
      const base = parts[parts.length - 1];

      // Filter macOS AppleDouble metadata (.DS_Store, ._*, .VolumeIcon, .Trashes, etc.)
      if (base.startsWith('._') || base.startsWith('.DS_Store') || base.startsWith('.Trash') || base === '.VolumeIcon.icns' || base === '.') {
        return true;
      }
      return false;
    }

    let allR2Objects: any[] = [];

    if (cfToken) {
      try {
        const cfRes = await fetch(`https://api.cloudflare.com/client/v4/accounts/${cfAccountId}/r2/buckets/${bucketName}/objects`, {
          headers: {
            'Authorization': `Bearer ${cfToken}`
          }
        });
        const cfData = await cfRes.json().catch(() => ({}));
        if (cfData.success && cfData.result) {
          allR2Objects = cfData.result || [];
        }
      } catch (err) {
        console.warn('Error fetching R2 objects:', err);
      }
    }

    // Filter ONLY real user uploaded files and real folders
    const cleanFiles: any[] = [];
    const discoveredFolders = new Set<string>();
    let totalRealBytes = 0;

    for (const obj of allR2Objects) {
      const key = obj.key;

      if (isHiddenOrSystemFile(key)) {
        continue;
      }

      // If object ends with / it's an explicit folder
      if (key.endsWith('/')) {
        const folderName = key.slice(0, -1).split('/').pop() || '';
        if (folderName && !folderName.startsWith('.')) {
          discoveredFolders.add(folderName);
        }
        continue;
      }

      // Check if file is inside a subfolder
      const slashIndex = key.indexOf('/');
      if (slashIndex > 0) {
        const topFolder = key.substring(0, slashIndex);
        if (!topFolder.startsWith('.')) {
          discoveredFolders.add(topFolder);
        }
      }

      cleanFiles.push({
        name: key,
        size: obj.size || 0,
        uploaded: obj.uploaded,
        etag: obj.etag
      });
      totalRealBytes += (obj.size || 0);
    }

    return new Response(JSON.stringify({
      success: true,
      bucket: bucketName,
      endpoint: `https://${cfAccountId}.r2.cloudflarestorage.com`,
      files: cleanFiles,
      folders: Array.from(discoveredFolders),
      fileCount: cleanFiles.length,
      storageUsedBytes: totalRealBytes
    }), {
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
