'use strict';

/**
 * Sokovia Architecture Interactive Canvas Engine
 * Simulates real-time kernel APFS block queries, WebDAV streaming pipelines,
 * and Cloudflare R2 chunk fetches in an elegant engineering halftone matrix.
 */
(function() {
  const canvas = document.getElementById('sokoviaCanvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  if (!ctx) return;

  let width = 0;
  let height = 0;
  let dpr = 1;
  let cols = 0;
  let rows = 0;
  const cellW = 12;
  const cellH = 16;
  let nodes = [];
  let streams = [];
  let mouse = { x: -1000, y: -1000, active: false };

  function resize() {
    dpr = Math.min(2, window.devicePixelRatio || 1);
    const rect = canvas.getBoundingClientRect();
    width = rect.width;
    height = rect.height;
    canvas.width = width * dpr;
    canvas.height = height * dpr;
    ctx.scale(dpr, dpr);

    cols = Math.ceil(width / cellW);
    rows = Math.ceil(height / cellH);

    // Seed interactive memory blocks
    nodes = [];
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        // Density pattern centered horizontally to illustrate virtual disk platter & network bus
        const cx = cols * 0.58;
        const cy = rows * 0.48;
        const dx = (c - cx) * cellW;
        const dy = (r - cy) * cellH;
        const dist = Math.sqrt(dx * dx + dy * dy);

        // Cylindrical disk block distribution
        const isPlatter = (dist > 70 && dist < 240);
        const isBus = (Math.abs(dy) < 32 && dx > -220 && dx < 280);
        const baseProb = isPlatter ? 0.38 : (isBus ? 0.45 : 0.08);

        if (Math.random() < baseProb) {
          nodes.push({
            c, r,
            x: c * cellW,
            y: r * cellH,
            char: ['0', '1', '·', ':', '+', 'x', '▪', '▫', '▓', '░', '═'][Math.floor(Math.random() * 11)],
            baseAlpha: Math.random() * 0.25 + 0.05,
            alpha: 0.1,
            pulse: Math.random() * Math.PI * 2,
            isPlatter,
            isBus
          });
        }
      }
    }
  }

  // Active data packets flowing from Cloudflare R2 into APFS Mount
  function spawnStream() {
    if (streams.length < 8) {
      streams.push({
        x: width * 0.95,
        y: height * 0.48 + (Math.random() - 0.5) * 50,
        vx: -(Math.random() * 3.5 + 2.5),
        vy: (Math.random() - 0.5) * 0.4,
        size: Math.random() * 2 + 2,
        life: 1.0,
        decay: Math.random() * 0.012 + 0.008,
        label: ['AES_BLK', 'CHUNK_4MB', 'APFS_INODE', 'R2_GET', 'BLOB_HASH', 'HKDF_SIG'][Math.floor(Math.random() * 6)]
      });
    }
  }

  let lastTime = performance.now();
  function render(time) {
    const dt = Math.min(32, time - lastTime);
    lastTime = time;

    ctx.clearRect(0, 0, width, height);

    // Draw grid background watermark
    ctx.font = '500 10px "Geist Mono", monospace';
    ctx.textBaseline = 'middle';
    ctx.textAlign = 'center';

    for (let i = 0; i < nodes.length; i++) {
      const n = nodes[i];
      n.pulse += dt * 0.002;
      const wave = Math.sin(n.pulse);

      let alpha = n.baseAlpha + wave * 0.08;

      // Mouse proximity interaction
      const distMouse = Math.hypot(n.x - mouse.x, n.y - mouse.y);
      if (distMouse < 140) {
        alpha += (1 - distMouse / 140) * 0.45;
      }

      if (n.isBus && Math.random() < 0.02) {
        n.char = ['═', '─', '▪', '1', '0'][Math.floor(Math.random() * 5)];
      }

      ctx.fillStyle = (distMouse < 90) ? 'rgba(63, 119, 0, 0.85)' : `rgba(17, 17, 17, ${Math.max(0.04, Math.min(0.75, alpha)).toFixed(3)})`;
      ctx.fillText(n.char, n.x + cellW / 2, n.y + cellH / 2);
    }

    // Update and draw packets
    if (Math.random() < 0.12) spawnStream();

    for (let i = streams.length - 1; i >= 0; i--) {
      const s = streams[i];
      s.x += s.vx;
      s.y += s.vy;
      s.life -= s.decay;

      if (s.life <= 0 || s.x < width * 0.2) {
        streams.splice(i, 1);
        continue;
      }

      // Draw packet pulse
      ctx.fillStyle = `rgba(182, 242, 58, ${s.life * 0.9})`;
      ctx.fillRect(s.x, s.y - 2, 8, 4);

      ctx.font = '600 9px "Geist Mono", monospace';
      ctx.fillStyle = `rgba(17, 17, 17, ${s.life * 0.8})`;
      ctx.fillText(s.label, s.x, s.y - 10);
    }

    // Platter Center HUD Target
    const cx = width * 0.58;
    const cy = height * 0.48;

    ctx.strokeStyle = 'rgba(17, 17, 17, 0.12)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.arc(cx, cy, 140, 0, Math.PI * 2);
    ctx.stroke();

    ctx.beginPath();
    ctx.arc(cx, cy, 70, 0, Math.PI * 2);
    ctx.stroke();

    // Crosshairs
    ctx.strokeStyle = 'rgba(63, 119, 0, 0.35)';
    ctx.beginPath();
    ctx.moveTo(cx - 150, cy); ctx.lineTo(cx - 130, cy);
    ctx.moveTo(cx + 130, cy); ctx.lineTo(cx + 150, cy);
    ctx.moveTo(cx, cy - 150); ctx.lineTo(cx, cy - 130);
    ctx.moveTo(cx, cy + 130); ctx.lineTo(cx, cy + 150);
    ctx.stroke();

    requestAnimationFrame(render);
  }

  window.addEventListener('resize', resize);
  window.addEventListener('mousemove', (e) => {
    const rect = canvas.getBoundingClientRect();
    mouse.x = e.clientX - rect.left;
    mouse.y = e.clientY - rect.top;
    mouse.active = true;
  });
  window.addEventListener('mouseleave', () => {
    mouse.x = -1000;
    mouse.y = -1000;
    mouse.active = false;
  });

  resize();
  requestAnimationFrame(render);
})();
