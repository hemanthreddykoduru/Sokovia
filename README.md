# Sokovia: Native macOS Cloud Drive for Cloudflare R2

**Sokovia** is a native macOS application that turns your personal **Cloudflare R2** bucket into a mounted virtual drive on macOS (`/Volumes/Sokovia`).

---

## Features

- **Your Keys, Your Account**: Direct connection to your personal Cloudflare R2 bucket with **$0 egress fees**.
- **Native macOS Menu Bar App**: Lives in your menu bar with quick status, one-click mount/unmount, and Finder shortcuts.
- **Zero Local Footprint**: Streams files on demand without consuming local storage.
- **High-Speed Range Requests**: Open videos, audio, and large PDFs instantly with byte-range seeking.
- **Optional Zero-Knowledge Encryption**: Local client-side AES-256-GCM encryption with passphrase key derivation via Apple CryptoKit.
- **Zero Third-Party Dependencies**: Pure native Swift, AppKit, CryptoKit, and Network.framework.

---

## Getting Started

### 1. Launching the App
Open the application directly from Finder or terminal:
```bash
open /Users/hemanthmacbook/Desktop/Sokovia/Sokovia.app
```

On first launch, the **Sokovia Settings** window will open automatically.

---

### 2. Setting Up Cloudflare R2 Credentials

To obtain your R2 credentials:
1. Go to the [Cloudflare Dashboard](https://dash.cloudflare.com/) and navigate to **R2**.
2. Create or select a **Bucket** (e.g. `sokovia-drive`).
3. Click **Manage R2 API Tokens** -> **Create API Token**.
4. Select **Object Read & Write** permissions for your bucket.
5. Copy:
   - **Account ID** (visible in your R2 dashboard URL and token page)
   - **Access Key ID**
   - **Secret Access Key**
   - **Bucket Name**
6. In **Sokovia Settings**, paste these credentials and click **Test Connection**.
7. Click **Save & Connect**.

---

### 3. Using the Mounted Drive

Once connected:
- The drive automatically mounts to **`/Volumes/Sokovia`**.
- Click the Menu Bar icon to:
  - Check connection status and active bucket.
  - Open the drive in **Finder**.
  - Mount or Unmount the drive with one click.
  - Access Settings.

Any file you drag into `/Volumes/Sokovia` will upload directly to your Cloudflare R2 bucket!

---

## Rebuilding

To re-compile and update `Sokovia.app`:
```bash
./bundle.sh
```

