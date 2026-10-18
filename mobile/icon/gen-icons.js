'use strict';
/**
 * 《我的末日》平板 App 图标生成器 —— 方案 ⑥「末日警戒」
 *
 * 构图：夜蓝底 + 琥珀色斜向警戒条纹（出血铺满）+ 暗底牌上的方块僵尸头（红眼）。
 * 小尺寸判据：48px 时仍能读出「警戒条纹 + 绿方块头 + 两只红眼」三件事。
 *
 * 单一事实来源：本文件的 BODY 构图（108x108 viewBox）一次生成
 *   - mobile/icon/ic_launcher_foreground.svg / ic_launcher_full.svg  设计源
 *   - res/values/ic_launcher_background.xml              自适应图标背景色
 *   - res/mipmap-dpi/ic_launcher_foreground.png          自适应前景（透明底，108dp）
 *   - res/mipmap-dpi/ic_launcher.png / ic_launcher_round.png  legacy 图标（48dp）
 *
 * 零 npm 依赖：光栅化用本机 Chrome/Edge headless（先超采样到大尺寸，
 * Chrome 在 window-size < 200 时视口会塌陷出全透明图），
 * 再用内置的精确盒式降采样 + PNG 编码器落到目标像素，最后解码回读实证校验。
 *
 * 用法：node mobile/icon/gen-icons.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const zlib = require('zlib');
const { execFileSync } = require('child_process');

const MOBILE = path.resolve(__dirname, '..');
const RES = path.join(MOBILE, 'android', 'app', 'src', 'main', 'res');
const TMP = path.join(os.tmpdir(), 'doomsday-icon');
const PROFILE = path.join(TMP, 'chrome-profile');
const MIN_RENDER_PX = 320; // 超采样下限

const P = {
  bg: '#13203a',       // 夜蓝底（自适应背景色，写入 @color）
  plate: '#0d1526',    // 头像暗底牌（把警戒条纹与僵尸头隔开）
  warn: '#ffb300',     // 琥珀警戒条纹
  red: '#e53935',      // 僵尸红眼（与游戏同色）
  skin: '#9ccc65',     // 方块僵尸皮肤（与游戏 ZK 同色）
  skinDark: '#7cb342', // 皮肤暗部 / 下颌
  mouth: '#33421f',    // 嘴
};

// adaptive 图标只有画布中心 72dp 会被显示，legacy 需按 108/72 放大以对齐观感
const BLEED = 108 / 72;

function fail(msg) {
  console.error('✗ ' + msg);
  process.exit(1);
}

/* ---------------- 构图（108x108 viewBox） ----------------
 * 形状以数据描述，既用于渲染，也用于「安全区」几何守卫。
 * 警戒条纹标了 bleed:true —— 它是有意出血的装饰底纹，被圆形遮罩裁掉边缘
 * 正是自适应图标期望的效果；其余图形（底牌 + 僵尸头）必须整块落在
 * 遮罩安全半径 33 之内，否则会被切。 */

const CENTER = { x: 54, y: 54 };
const SAFE = 33; // 系统圆形遮罩安全半径

// 斜向警戒条纹：整组绕画布中心旋转 -45°，条纹在旋转坐标系里是竖条。
// 旋转后画布（0..108）对应的旋转坐标系范围是中心 ±54√2 ≈ -22.4..130.4，
// 所以竖条起点取 -53、并按周期铺过 131，长度覆盖 ±60 之外，保证铺满无空洞。
const STRIPE = { tilt: -45, period: 18, width: 8, first: -53, last: 131, y: -60, h: 228 };

const SHAPES = [
  { name: '警戒条纹', stripes: true, bleed: true },
  { name: '底牌', rect: [34, 38, 40, 32], fill: P.plate },
  { name: '僵尸头', rect: [38, 42, 32, 24], fill: P.skin },
  { name: '下颌暗部', rect: [38, 61, 32, 5], fill: P.skinDark },
  { name: '嘴', rect: [45, 57, 18, 4], fill: P.mouth },
  { name: '左眼', rect: [43, 48, 8, 7], fill: P.red },
  { name: '右眼', rect: [57, 48, 8, 7], fill: P.red },
];

/** 形状的所有极值角点（用于安全区计算） */
function corners(s) {
  const [x, y, w, h] = s.rect;
  return [[x, y], [x + w, y], [x + w, y + h], [x, y + h]];
}

function renderShape(s) {
  if (s.stripes) {
    const bars = [];
    for (let x = STRIPE.first; x <= STRIPE.last; x += STRIPE.period)
      bars.push(`<rect x="${x}" y="${STRIPE.y}" width="${STRIPE.width}" height="${STRIPE.h}" fill="${P.warn}"/>`);
    return `<g transform="rotate(${STRIPE.tilt} ${CENTER.x} ${CENTER.y})">${bars.join('')}</g>`;
  }
  const [x, y, w, h] = s.rect;
  return `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${s.fill}"/>`;
}

/** 前景构图（透明底，只画内容；底色由 @color/ic_launcher_background 提供） */
const BODY = SHAPES.map(renderShape).join('');

/** legacy / round 用整幅图：夜蓝满铺 + 前景按 bleed 放大居中 */
const LEGACY =
  `<rect width="108" height="108" fill="${P.bg}"/>` +
  `<g transform="translate(54 54) scale(${BLEED}) translate(-54 -54)">${BODY}</g>`;
const ROUND =
  `<defs><clipPath id="rc"><circle cx="54" cy="54" r="54"/></clipPath></defs>` +
  `<g clip-path="url(#rc)">${LEGACY}</g>`;

const DENSITIES = [
  { name: 'mdpi', launcher: 48, foreground: 108 },
  { name: 'hdpi', launcher: 72, foreground: 162 },
  { name: 'xhdpi', launcher: 96, foreground: 216 },
  { name: 'xxhdpi', launcher: 144, foreground: 324 },
  { name: 'xxxhdpi', launcher: 192, foreground: 432 },
];

/* ---------------- 光栅化 ---------------- */

function svgDoc(inner, px) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${px}" height="${px}" viewBox="0 0 108 108">${inner}</svg>`;
}

function page(inner, px) {
  return (
    `<!doctype html><html><head><meta charset="utf-8"><style>` +
    `html,body{margin:0;padding:0;height:100%;overflow:hidden;background:transparent}` +
    `svg{display:block}</style></head><body>` + svgDoc(inner, px) + `</body></html>`
  );
}

function findBrowser() {
  const list = [
    process.env.DOOMSDAY_BROWSER,
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
    'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
  ].filter(Boolean);
  const hit = list.find((p) => fs.existsSync(p));
  if (!hit) fail('找不到 Chrome/Edge，可设置环境变量 DOOMSDAY_BROWSER 指定可执行文件');
  console.log('光栅化浏览器: ' + hit);
  return hit;
}

function shoot(browser, htmlFile, pngFile, px) {
  execFileSync(
    browser,
    [
      '--headless',
      '--disable-gpu',
      '--no-sandbox',
      '--hide-scrollbars',
      `--user-data-dir=${PROFILE}`,
      '--force-device-scale-factor=1',
      '--default-background-color=00000000',
      `--window-size=${px},${px}`,
      `--screenshot=${pngFile}`,
      'file:///' + htmlFile.replace(/\\/g, '/'),
    ],
    { stdio: 'pipe' }
  );
  if (!fs.existsSync(pngFile)) fail('截图未生成: ' + pngFile);
}

/* ---------------- PNG 解码 / 降采样 / 编码（纯 Node） ---------------- */

function decodePng(buf, label) {
  if (buf.readUInt32BE(0) !== 0x89504e47) fail('不是 PNG: ' + label);
  let pos = 8;
  let ihdr = null;
  const idat = [];
  while (pos + 8 <= buf.length) {
    const len = buf.readUInt32BE(pos);
    const type = buf.toString('ascii', pos + 4, pos + 8);
    const data = buf.subarray(pos + 8, pos + 8 + len);
    if (type === 'IHDR') {
      ihdr = { w: data.readUInt32BE(0), h: data.readUInt32BE(4), depth: data[8], color: data[9], interlace: data[12] };
    } else if (type === 'IDAT') idat.push(data);
    pos += 12 + len;
  }
  if (!ihdr) fail('PNG 缺 IHDR: ' + label);
  if (ihdr.depth !== 8 || ihdr.interlace !== 0 || (ihdr.color !== 6 && ihdr.color !== 2)) {
    fail(`${label}: 格式非预期 depth=${ihdr.depth} color=${ihdr.color} interlace=${ihdr.interlace}`);
  }
  const ch = ihdr.color === 6 ? 4 : 3;
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = ihdr.w * ch;
  const out = Buffer.alloc(ihdr.h * stride);
  let p = 0;
  for (let y = 0; y < ihdr.h; y++) {
    const f = raw[p++];
    for (let x = 0; x < stride; x++) {
      const a = x >= ch ? out[y * stride + x - ch] : 0;
      const b = y > 0 ? out[(y - 1) * stride + x] : 0;
      const c = x >= ch && y > 0 ? out[(y - 1) * stride + x - ch] : 0;
      let v = raw[p++];
      if (f === 1) v += a;
      else if (f === 2) v += b;
      else if (f === 3) v += (a + b) >> 1;
      else if (f === 4) {
        const pp = a + b - c;
        const pa = Math.abs(pp - a), pb = Math.abs(pp - b), pc = Math.abs(pp - c);
        v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
      }
      out[y * stride + x] = v & 255;
    }
  }
  // 归一化为 RGBA：页面完全不透明时 Chrome 输出 color type 2（无 alpha 通道），
  // 下游的降采样与取色断言统一按 4 通道处理，避免两种内存布局分支。
  if (ch === 4) return { w: ihdr.w, h: ihdr.h, data: out };
  const rgba = Buffer.alloc(ihdr.w * ihdr.h * 4);
  for (let i = 0, j = 0; i < ihdr.w * ihdr.h; i++) {
    rgba[j++] = out[i * 3];
    rgba[j++] = out[i * 3 + 1];
    rgba[j++] = out[i * 3 + 2];
    rgba[j++] = 255;
  }
  return { w: ihdr.w, h: ihdr.h, data: rgba };
}

/** 整数倍盒式降采样（按预乘 alpha 平均，避免透明边缘出现暗边） */
function downscale(img, target, factor) {
  if (img.w !== target * factor || img.h !== target * factor) fail('降采样尺寸不成整数倍');
  const out = Buffer.alloc(target * target * 4);
  const area = factor * factor;
  for (let y = 0; y < target; y++) {
    for (let x = 0; x < target; x++) {
      let sr = 0, sg = 0, sb = 0, sa = 0;
      for (let j = 0; j < factor; j++) {
        for (let i = 0; i < factor; i++) {
          const idx = ((y * factor + j) * img.w + x * factor + i) * 4;
          const al = img.data[idx + 3];
          sa += al;
          sr += img.data[idx] * al;
          sg += img.data[idx + 1] * al;
          sb += img.data[idx + 2] * al;
        }
      }
      const o = (y * target + x) * 4;
      out[o + 3] = Math.round(sa / area);
      if (sa > 0) {
        // sr 是 Σ(R·α)，除以 Σα 即得非预乘的平均色
        out[o] = Math.min(255, Math.round(sr / sa));
        out[o + 1] = Math.min(255, Math.round(sg / sa));
        out[o + 2] = Math.min(255, Math.round(sb / sa));
      }
    }
  }
  return out;
}

const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const head = Buffer.alloc(8);
  head.writeUInt32BE(data.length, 0);
  head.write(type, 4, 'ascii');
  const tail = Buffer.alloc(4);
  tail.writeUInt32BE(crc32(Buffer.concat([head.subarray(4), data])), 0);
  return Buffer.concat([head, data, tail]);
}

function encodePng(w, h, rgba) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8;   // bit depth
  ihdr[9] = 6;   // RGBA
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;
  const raw = Buffer.alloc(h * (1 + w * 4));
  let p = 0;
  for (let y = 0; y < h; y++) {
    raw[p++] = 0; // filter: none
    rgba.copy(raw, p, y * w * 4, (y + 1) * w * 4);
    p += w * 4;
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

/* ---------------- 实证校验 ---------------- */

function hexRgb(hex) {
  const n = parseInt(hex.slice(1), 16);
  return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
}

/** 取 viewBox 分数坐标处的像素（图像已归一化为 RGBA） */
function sample(img, fx, fy) {
  const x = Math.min(img.w - 1, Math.max(0, Math.round(fx * img.w - 0.5)));
  const y = Math.min(img.h - 1, Math.max(0, Math.round(fy * img.h - 0.5)));
  const i = (y * img.w + x) * 4;
  return { r: img.data[i], g: img.data[i + 1], b: img.data[i + 2], a: img.data[i + 3], x, y };
}

const VB = (v) => v / 108;

function expectSize(img, px, label) {
  if (img.w !== px || img.h !== px) fail(`${label}: 尺寸 ${img.w}x${img.h} != 期望 ${px}x${px}`);
}

function expectAlpha(img, fx, fy, wantZero, label) {
  const s = sample(img, fx, fy);
  const ok = wantZero ? s.a < 8 : s.a > 247;
  if (!ok) fail(`${label}: (${s.x},${s.y}) alpha=${s.a} 期望 ${wantZero ? '0' : '255'}`);
}

function expectColor(img, fx, fy, hex, label, tol = 80) {
  const s = sample(img, fx, fy);
  const e = hexRgb(hex);
  const d = Math.max(Math.abs(s.r - e.r), Math.abs(s.g - e.g), Math.abs(s.b - e.b));
  if (d > tol) fail(`${label}: (${s.x},${s.y}) 实测 rgb(${s.r},${s.g},${s.b}) 距 ${hex} 差 ${d} > ${tol}`);
}

/** 前景 viewBox 点映射到 legacy（BLEED 倍放大）后的分数坐标 */
function legacyFrac(fvx, fvy) {
  return [VB(54 + (fvx - 54) * BLEED), VB(54 + (fvy - 54) * BLEED)];
}

/**
 * 暗底判定：底牌 #0d1526 / 夜蓝 #13203a / 嘴 #33421f 三者互相最大差 < 80，
 * 逐点取色分不开，因此只判「不透明且确实够暗」——足以排除条纹与皮肤串位。
 */
function expectDark(img, fx, fy, label) {
  const s = sample(img, fx, fy);
  if (s.a < 247) fail(`${label}: (${s.x},${s.y}) alpha=${s.a} 期望不透明`);
  if (s.r > 90 || s.g > 100 || s.b > 110)
    fail(`${label}: (${s.x},${s.y}) rgb(${s.r},${s.g},${s.b}) 亮度过高，不像暗底`);
}

/**
 * 斜纹是相位相关的图形，逐点取色太脆（差半个周期就误判），
 * 改用「安全区面积占比」实证条纹确实画出来了、颜色正确、也没有铺满失控。
 * radiusVB 为 null 时统计整幅画布。
 */
function colorFraction(img, hex, radiusVB, tol = 60) {
  const e = hexRgb(hex);
  const cx = img.w / 2, cy = img.h / 2;
  const r = radiusVB === null ? Infinity : (radiusVB / 108) * img.w;
  let hit = 0, total = 0;
  for (let y = 0; y < img.h; y++) {
    for (let x = 0; x < img.w; x++) {
      if (Math.hypot(x + 0.5 - cx, y + 0.5 - cy) > r) continue;
      total++;
      const i = (y * img.w + x) * 4;
      const d = Math.max(Math.abs(img.data[i] - e.r), Math.abs(img.data[i + 1] - e.g), Math.abs(img.data[i + 2] - e.b));
      if (d <= tol && img.data[i + 3] > 128) hit++;
    }
  }
  return hit / total;
}

/** 透明像素占比（前景必须是透明底，条纹间隙才露得出 @color 背景） */
function transparentFraction(img) {
  let hit = 0;
  const n = img.w * img.h;
  for (let i = 3; i < n * 4; i += 4) if (img.data[i] < 8) hit++;
  return hit / n;
}

function expectRange(frac, lo, hi, label) {
  if (frac < lo || frac > hi) fail(`${label}: 占比 ${(frac * 100).toFixed(1)}% 超出预期区间 ${(lo * 100).toFixed(0)}%~${(hi * 100).toFixed(0)}%`);
  console.log(`  ${label} ${(frac * 100).toFixed(1)}% (区间 ${(lo * 100).toFixed(0)}%~${(hi * 100).toFixed(0)}%)`);
}

/* ---------------- 主流程 ---------------- */

function main() {
  fs.rmSync(TMP, { recursive: true, force: true });
  fs.mkdirSync(PROFILE, { recursive: true });
  const browser = findBrowser();

  fs.writeFileSync(path.join(__dirname, 'ic_launcher_foreground.svg'), svgDoc(BODY, 108) + '\n');
  fs.writeFileSync(path.join(__dirname, 'ic_launcher_full.svg'), svgDoc(LEGACY, 108) + '\n');
  fs.writeFileSync(
    path.join(RES, 'values', 'ic_launcher_background.xml'),
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n' +
      `    <color name="ic_launcher_background">${P.bg}</color>\n</resources>\n`
  );

  const jobs = [];
  for (const d of DENSITIES) {
    jobs.push({ file: 'ic_launcher_foreground.png', dir: `mipmap-${d.name}`, inner: BODY, px: d.foreground, kind: 'fg' });
    jobs.push({ file: 'ic_launcher.png', dir: `mipmap-${d.name}`, inner: LEGACY, px: d.launcher, kind: 'legacy' });
    jobs.push({ file: 'ic_launcher_round.png', dir: `mipmap-${d.name}`, inner: ROUND, px: d.launcher, kind: 'round' });
  }

  let seq = 0;
  for (const j of jobs) {
    const factor = Math.max(2, Math.ceil(MIN_RENDER_PX / j.px));
    const renderPx = j.px * factor;
    const html = path.join(TMP, `shot-${++seq}.html`);
    const big = path.join(TMP, `shot-${seq}.png`);
    fs.writeFileSync(html, page(j.inner, renderPx));
    shoot(browser, html, big, renderPx);

    const src = decodePng(fs.readFileSync(big), big);
    expectSize(src, renderPx, `${j.dir} 超采样 ${j.file}`);
    const dst = path.join(RES, j.dir, j.file);
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    fs.writeFileSync(dst, encodePng(j.px, j.px, downscale(src, j.px, factor)));

    const img = decodePng(fs.readFileSync(dst), dst);
    expectSize(img, j.px, `${j.dir}/${j.file}`);
    if (j.kind === 'fg') {
      expectAlpha(img, 0.5, 0.5, false, `${j.dir}/fg 僵尸头中心不透明`);
      expectColor(img, 0.5, 0.5, P.skin, `${j.dir}/fg 僵尸皮肤`);
      expectColor(img, VB(47), VB(51.5), P.red, `${j.dir}/fg 左眼`);
      expectColor(img, VB(61), VB(51.5), P.red, `${j.dir}/fg 右眼`);
      expectDark(img, VB(36), VB(40), `${j.dir}/fg 暗底牌`);
      expectDark(img, VB(54), VB(59), `${j.dir}/fg 僵尸嘴`);
      // 遮罩安全圆内：条纹约占裸露面积的 8/18，底牌吃掉一半，估算落在 28% 附近
      expectRange(colorFraction(img, P.warn, SAFE), 0.18, 0.38, `${j.dir}/fg 安全圆内警戒条纹占比`);
      expectRange(transparentFraction(img), 0.35, 0.62, `${j.dir}/fg 透明底占比`);
    } else {
      expectAlpha(img, 0.5, 0.5, false, `${j.dir}/${j.file} 中心不透明`);
      expectColor(img, 0.5, 0.5, P.skin, `${j.dir}/${j.file} 僵尸皮肤`);
      expectColor(img, ...legacyFrac(47, 51.5), P.red, `${j.dir}/${j.file} 左眼`);
      expectDark(img, ...legacyFrac(36, 40), `${j.dir}/${j.file} 暗底牌`);
      expectRange(colorFraction(img, P.warn, null), 0.2, 0.46, `${j.dir}/${j.file} 整幅警戒条纹占比`);
      if (j.kind === 'legacy') expectAlpha(img, 0.02, 0.02, false, `${j.dir}/legacy 方角不透明`);
      if (j.kind === 'round') expectAlpha(img, 0.02, 0.02, true, `${j.dir}/round 圆裁外缘透明`);
    }
    console.log(`✓ ${j.dir}/${j.file}  ${img.w}x${img.h}  ${fs.statSync(dst).size}B  (渲染 ${renderPx}px/${factor}x)`);
  }

  // 安全区自检：主体图形（底牌 + 僵尸头）角点必须整块落在圆形遮罩安全半径内；
  // 警戒条纹是有意出血的装饰底纹，被遮罩裁掉边缘正是自适应图标的预期效果。
  for (const s of SHAPES) {
    if (s.bleed) {
      console.log(`安全区 ${s.name.padEnd(5)} 出血装饰（允许被遮罩裁切）`);
      continue;
    }
    const worst = Math.max(...corners(s).map((p) => Math.hypot(p[0] - CENTER.x, p[1] - CENTER.y)));
    if (worst > SAFE) fail(`安全区: ${s.name} 最远角 ${worst.toFixed(2)} 超出上限 ${SAFE.toFixed(2)}`);
    console.log(`安全区 ${s.name.padEnd(5)} 最远角 ${worst.toFixed(2)} / 上限 ${SAFE.toFixed(2)}`);
  }

  console.log(`\n共生成 ${jobs.length} 张 PNG（含 5 个密度），全部通过尺寸/alpha/取色校验。`);
}

main();
