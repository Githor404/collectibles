# Layout gate (was capture-outcome-gate), ported from HealthTracker's R21.5 gate (HT-D51).
#
# RENAMED 2026-09-13. It had already outgrown "capture outcome" -- repointed for
# R1's identity draft, and now measuring R2b's comps scatter. One CDP harness,
# honestly named: a sibling would have duplicated ~150 lines of scaffolding, and
# the first fix landing in one copy and not the other is D3's family.
#
# "Exactly one outcome, in view without scrolling" is a LAYOUT claim, so it is
# measured as one. A string gate can prove the modal rendered; only a viewport can
# prove it was READABLE without hunting for it.
#
# R2b ADDED THE SECOND LAYOUT CLAIM, and it was added because a defect escaped.
# The comps row shipped as three inline spans with NO CSS at all and reached a
# phone as one run of text -- "$52.46The Incredible Hulk #271 ... 198217/08",
# the title's year merging into the date. EVERY data-layer assertion was green
# while that shipped, because --dump-dom sees markup and cannot see geometry.
# Emitting a class is not shipping a layout. So: price, date and title must
# occupy DISJOINT rectangles, the title must sit below both, and the page must
# not overflow horizontally.
#
# REPOINTED FOR R1 (HT-D60 Clause 3), not weakened: it now installs the SHIPPED
# identification contract and measures the real identity draft -- the question,
# its fields, and both footer actions. Measuring the synthetic contract's generic
# readout would have kept the gate green while saying nothing about what ships.
#
# Measured against the real index.html, driven through the shipped capture path
# with fetch stubbed, at two phone sizes and one desktop:
#   * exactly ONE outcome state exists, and the capture surface carries none of it;
#   * SUCCESS -- the identity QUESTION and BOTH footer actions are fully inside the
#     viewport with the page unscrolled;
#   * SHORT VIEWPORT -- where the draft is taller than the screen, the body scrolls
#     and the footer does NOT, so Confirm and Discard stay reachable;
#   * FAILURE -- the stated message and both ways out are in view;
#   * PENDING -- the counted spinner and the cancel, in view.
#
# Unlike the data-layer suite this runs in REAL time, so it exercises the
# createImageBitmap decoder that never settles under --virtual-time-budget (HT-D47).
#
# Scope (D1): the browser profile lives under tests/.tmp, never %TEMP%. Ports differ
# from HealthTracker's gate so both suites can run on one machine.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$port = 8237
$origin = "http://127.0.0.1:$port"
$dbg = 9447
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$tmpRoot = Join-Path $PSScriptRoot '.tmp'
if (-not (Test-Path $tmpRoot)) { New-Item -ItemType Directory -Force $tmpRoot | Out-Null }
$udd = Join-Path $tmpRoot ("layout-" + [System.Guid]::NewGuid().ToString('N'))
$ct = [Threading.CancellationToken]::None

$MIN_ACTION_H = 44   # a primary action is a thumb target, not a link

function Find-Browser {
  foreach ($c in @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")) { if (Test-Path $c) { return $c } }
  return $null
}
function Receive-One {
  $ms = New-Object IO.MemoryStream
  $buf = New-Object byte[] 16384
  while ($true) {
    $res = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $ct).GetAwaiter().GetResult()
    $ms.Write($buf, 0, $res.Count)
    if ($res.EndOfMessage) { break }
  }
  return ([Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json)
}
function Invoke-CDP([string]$method, [hashtable]$prms) {
  $script:cid++
  $payload = @{ id = $script:cid; method = $method }
  if ($prms) { $payload.params = $prms }
  $json = $payload | ConvertTo-Json -Depth 20 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  [void]$ws.SendAsync([ArraySegment[byte]]::new($bytes), [Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).GetAwaiter().GetResult()
  $guard = 0
  while ($true) {
    if (++$guard -gt 300) { throw "CDP: no response for $method" }
    $msg = Receive-One
    if (($null -ne $msg.id) -and ($msg.id -eq $script:cid)) { return $msg }
  }
}
function Eval([string]$expr) {
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = $expr; returnByValue = $true; awaitPromise = $true }
  return $r.result.result.value
}

# ---- the page-side helpers, installed once per navigation -------------------
$install = @'
(function(){
  window.__g = {};
  __g.rect = function(sel, root){
    var e = (root||document).querySelector(sel);
    if (!e) return { found:false, inView:false };
    var r = e.getBoundingClientRect();
    return { found:true, top:Math.round(r.top), bottom:Math.round(r.bottom),
             w:Math.round(r.width), h:Math.round(r.height),
             inView: (r.top >= -1 && r.bottom <= window.innerHeight + 1 &&
                      r.left >= -1 && r.right <= window.innerWidth + 1 &&
                      r.width > 0 && r.height > 0) };
  };
  __g.snap = function(){
    var w = document.getElementById('captureOutcome');
    var foot = document.getElementById('outcomeFoot');
    var body = document.getElementById('outcomeBody');
    var cap = document.getElementById('captureBox');
    var shown = !!w && w.style.display !== 'none' && w.style.display !== '';
    return {
      state: CT.captureOutcomeState(),
      shown: shown,
      msgText: (document.getElementById('outcomeMsg').textContent || ''),
      lead:   __g.rect('#captureResult .idq'),
      firstField: __g.rect('#captureResult .idrow input'),
      // D15/D16: the want flag is INSIDE the draft, so it adds height to the
      // surface whose whole threshold is "question and BOTH actions in view,
      // unscrolled". Measured here because the first run of this gate after the
      // want-list shipped passed while the flag rendered EMPTY -- a fresh profile
      // has no wants, so wantFlagHTML returned '' and the gate proved the draft
      // fits WITHOUT the thing that was just added to it.
      wantFlag: __g.rect('#captureResult .wantflag'),
      primary:__g.rect('#outcomeFoot .btn:nth-of-type(1)'),
      second: __g.rect('#outcomeFoot .btn:nth-of-type(2)'),
      nActions: document.querySelectorAll('#outcomeFoot .btn').length,
      spin:   __g.rect('#outcomeMsg .byokspin'),
      bodyScrolls: !!body && body.scrollHeight > body.clientHeight + 1,
      pageScrollY: Math.round(window.scrollY || 0),
      pageOverflowX: document.documentElement.scrollWidth > window.innerWidth + 1,
      captureSurfaceClean: !cap || (cap.innerHTML.indexOf('opend') < 0 && cap.innerHTML.indexOf('byokCancel') < 0 &&
                                    cap.innerHTML.indexOf('captureAccept') < 0 && cap.innerHTML.indexOf('captureRetry') < 0),
      footHTML: foot ? foot.innerHTML : ''
    };
  };
  // The SHIPPED contract, not a stand-in: this gate measures what ships (R1).
  __g.key = function(){ CT.setVisionContract(CT.IDENTITY_CONTRACT); CT.clearConfirmed();
    CT.credClear('vision'); CT.credSave('vision','grok','xai-GATEKEY-0123456789012345',20);
    // Seeded so the measured draft actually CARRIES the flag. Typed in the
    // format-generous form on purpose: ID_SAMPLE is "The Amazing Spider-Man" /
    // "300", so this lower-case, article-less, #-less line makes the SHIPPED
    // page exercise the generosity rule rather than an exact-match shortcut.
    CT.wantsSave('amazing spider-man 300'); };
  __g.file = function(){
    var c=document.createElement('canvas'); c.width=1400; c.height=1050;
    var x=c.getContext('2d'); var g=x.createLinearGradient(0,0,1400,1050);
    g.addColorStop(0,'#873'); g.addColorStop(1,'#39a'); x.fillStyle=g; x.fillRect(0,0,1400,1050);
    return new Promise(function(r){ c.toBlob(function(b){ r(new File([b],'cover.jpg',{type:'image/jpeg'})); },'image/jpeg',0.9); });
  };
  __g.reply = function(){
    return JSON.stringify({choices:[{message:{content:CT.ID_SAMPLE}}]});
  };
  // R2b's comps scatter. THE DEFECT THIS MEASURES reached a phone with every
  // data-layer assertion green: three fields emitted as inline spans with no CSS
  // shipped for them, rendering as one run of text --
  //   "$52.46The Incredible Hulk #271 ... Appearance 198217/08"
  // A string gate cannot see that. Only geometry can.
  //
  // The modal is dismissed FIRST: Measure-Pending leaves it open over a hung
  // fetch, and a rect is still computed for an element underneath it -- so this
  // would measure a correct layout while the user sees a covered one.
  __g.comps = function(){
    CT.byokCancel(); CT.byokBusyClear(); CT.captureDiscard(); CT.clearConfirmed();
    CT.__setComps([
      { itemId:'a1', title:'The Incredible Hulk #271 First Rocket Raccoon Appearance 1982',
        condition:'Pre-Owned', endedAt:'2026-08-17T09:00:00Z', soldPrice:52.46, soldCurrency:'USD', bestOffer:false },
      { itemId:'a2', title:'INCREDIBLE HULK 271 CGC 9.8 WHITE PAGES', condition:'Pre-Owned',
        endedAt:'2026-08-02T09:00:00Z', soldPrice:145, soldCurrency:'USD', bestOffer:false },
      { itemId:'a3', title:'Incredible Hulk 271 VG- complete', condition:'Pre-Owned',
        endedAt:'2026-07-29T09:00:00Z', soldPrice:16.21, soldCurrency:'USD', bestOffer:true },
      { itemId:'a4', title:'Hulk #271 GD 1 CF staple detached', condition:'Pre-Owned',
        endedAt:'2026-08-11T09:00:00Z', soldPrice:9, soldCurrency:'USD', bestOffer:false }
    ], [], 'Incredible Hulk 271');
    var row = document.querySelector('#compsBox .cmplist .cmprow');
    if (!row) return { found:false, why:'no .cmplist .cmprow rendered' };
    var p = row.querySelector('.cmpprice'), m = row.querySelector('.cmpmeta'), t = row.querySelector('.cmptitle');
    if (!p || !m || !t) return { found:false, why:'a field is not its own element: price=' + !!p + ' date=' + !!m + ' title=' + !!t };
    var R = function(e){ var b=e.getBoundingClientRect();
      return { top:Math.round(b.top), bottom:Math.round(b.bottom), left:Math.round(b.left),
               right:Math.round(b.right), w:Math.round(b.width), h:Math.round(b.height) }; };
    var P=R(p), M=R(m), T=R(t);
    // Disjoint = the rectangles do not intersect. Touching edges are allowed;
    // overlap is not, because overlap is exactly what "ran together" looks like.
    var hit = function(a,b){ return !(a.right <= b.left || b.right <= a.left ||
                                      a.bottom <= b.top || b.bottom <= a.top); };
    return {
      found:true, price:P, date:M, title:T,
      priceDateDisjoint:  !hit(P,M),
      priceTitleDisjoint: !hit(P,T),
      dateTitleDisjoint:  !hit(M,T),
      titleBelowPrice: T.top >= P.bottom - 1,
      titleBelowDate:  T.top >= M.bottom - 1,
      pageOverflowX: document.documentElement.scrollWidth > window.innerWidth + 1,
      rowText: (row.textContent || '').slice(0, 90)
    };
  };
  // R3: the comparison. The marker is the ONE number here that is not a sale,
  // so it must be unmistakably separate from the comps around it -- and the ask
  // INPUT must not overlap the scatter it sits above. Geometry again: a string
  // gate cannot tell "labelled and distinct" from "overlapping and illegible".
  __g.ask = function(){
    __g.comps();                       // seeds comps and dismisses the modal
    CT.askSetPrice('30'); CT.askSetGrade('VF-'); CT.askSetTerms('5 for $40');
    var mk = document.querySelector('#compsBox .askrow');
    var inp = document.getElementById('askPrice');
    var cnt = document.querySelector('#askBox .askcount');
    // WHEN A GATE CANNOT MEASURE, IT MUST SAY WHY IN FULL. "input=false" told me
    // what was absent and nothing about the cause, and two hypotheses read off
    // the source were both wrong. These are the facts that separate "the element
    // is missing" from "the phase test said none" from "nothing ever painted it".
    // Captured WITHOUT forcing a render, so the probe cannot mask what it measures.
    if (!mk || !inp || !cnt) {
      var box = document.getElementById('askBox');
      var st = CT.compsState();
      return { found:false, why:'marker=' + !!mk + ' input=' + !!inp + ' counts=' + !!cnt +
        ' | askBox=' + (box ? 'present' : 'MISSING') +
        ' askBoxHTMLlen=' + (box ? box.innerHTML.length : -1) +
        ' phase=' + (st ? st.phase : 'null') +
        ' rows=' + (st ? st.rows.length : -1) +
        ' askState=' + JSON.stringify(CT.askState()) };
    }
    var p = mk.querySelector('.cmpprice'), lab = mk.querySelector('.askmark');
    if (!p || !lab) return { found:false, why:'marker has no price or no label' };
    var R = function(e){ var b=e.getBoundingClientRect();
      return { top:Math.round(b.top), bottom:Math.round(b.bottom), left:Math.round(b.left),
               right:Math.round(b.right), w:Math.round(b.width), h:Math.round(b.height) }; };
    var hit = function(a,b){ return !(a.right <= b.left || b.right <= a.left ||
                                      a.bottom <= b.top || b.bottom <= a.top); };
    var P=R(p), L=R(lab), I=R(inp), C=R(cnt);
    // The marker must not collide with the comps immediately around it.
    var rows = Array.prototype.slice.call(document.querySelectorAll('#compsBox .cmplist .cmprow'));
    var idx = rows.indexOf(mk);
    var nbr = [rows[idx-1], rows[idx+1]].filter(Boolean).map(R);
    return {
      found:true, price:P, label:L, input:I, counts:C,
      priceLabelDisjoint: !hit(P,L),
      markerClearOfNeighbours: nbr.every(function(n){ return !hit(R(mk), n); }),
      inputClearOfScatter: !hit(I, R(document.getElementById('compsBox'))),
      countsVisible: C.w > 0 && C.h > 0,
      labelText: (lab.textContent || ''),
      pageOverflowX: document.documentElement.scrollWidth > window.innerWidth + 1
    };
  };
  __g.ok = function(){ window.fetch=function(){ return Promise.resolve({ok:true,status:200,
    text:function(){ return Promise.resolve(__g.reply()); }}); }; };
  __g.hang = function(){ window.fetch=function(u,i){ return new Promise(function(_,rej){
    var s=i&&i.signal; if(s) s.addEventListener('abort',function(){ var e=new Error('a'); e.name='AbortError'; rej(e); }); }); }; };
  return 'installed';
})()
'@

$capture = @'
(function(){
  CT.captureDiscard(); CT.byokBusyClear(); __g.key();
  return __g.file().then(function(f){ return CT.byokCapture(f); }).then(function(){ return JSON.stringify(__g.snap()); });
})()
'@

function Go([int]$w, [int]$h, [bool]$mobile) {
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = $h; deviceScaleFactor = 1; mobile = $mobile } | Out-Null
  Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $mobile; maxTouchPoints = 5 } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 1500
  Eval $install | Out-Null
}
function Measure-Success {
  Eval '__g.ok()' | Out-Null
  return (Eval $capture | ConvertFrom-Json)
}
function Measure-Fail {
  Eval '__g.hang()' | Out-Null
  Eval 'CT.setCallTimeout(2000)' | Out-Null
  $r = Eval $capture | ConvertFrom-Json
  Eval 'CT.setCallTimeout(120000)' | Out-Null
  return $r
}
function Measure-Pending {
  Eval '__g.hang()' | Out-Null
  Eval 'CT.setCallTimeout(120000)' | Out-Null
  Eval '(function(){ CT.captureDiscard(); CT.byokBusyClear(); __g.key();
        __g.file().then(function(f){ window.__p = CT.byokCapture(f); }); return 1; })()' | Out-Null
  Start-Sleep -Milliseconds 1600
  $r = Eval '(function(){ return JSON.stringify(__g.snap()); })()' | ConvertFrom-Json
  Eval '(function(){ CT.byokCancel(); return 1; })()' | Out-Null
  return $r
}

function Measure-Comps {
  return (Eval '(function(){ return JSON.stringify(__g.comps()); })()' | ConvertFrom-Json)
}
function Measure-Ask {
  return (Eval '(function(){ return JSON.stringify(__g.ask()); })()' | ConvertFrom-Json)
}

$browser = Find-Browser
if (-not $browser) { Write-Host "ERROR: no Chrome/Edge found"; exit 2 }

$server = Start-Job -ArgumentList $repo, $port -ScriptBlock {
  param($repo, $port)
  $l = New-Object System.Net.HttpListener
  $l.Prefixes.Add("http://127.0.0.1:$port/")
  $l.Start()
  $mimes = @{ '.html' = 'text/html'; '.js' = 'application/javascript'; '.json' = 'application/json'; '.png' = 'image/png'; '.svg' = 'image/svg+xml'; '.css' = 'text/css' }
  while ($l.IsListening) {
    try { $ctx = $l.GetContext() } catch { break }
    try {
      $rel = [Uri]::UnescapeDataString($ctx.Request.Url.LocalPath).TrimStart('/')
      if ([string]::IsNullOrEmpty($rel)) { $rel = 'index.html' }
      $full = Join-Path $repo $rel
      if (Test-Path $full -PathType Leaf) {
        $bytes = [System.IO.File]::ReadAllBytes($full)
        $ext = [System.IO.Path]::GetExtension($full).ToLower()
        if ($mimes.ContainsKey($ext)) { $ctx.Response.ContentType = $mimes[$ext] }
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
      } else { $ctx.Response.StatusCode = 404 }
    } catch { }
    try { $ctx.Response.Close() } catch { }
  }
}

function Cleanup {
  try { if ($ws) { $ws.Dispose() } } catch { }
  try { if ($chrome) { Stop-Process -Id $chrome.Id -Force -ErrorAction SilentlyContinue } } catch { }
  try { Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*$udd*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } } catch { }
  try { Stop-Job $server -ErrorAction SilentlyContinue; Remove-Job $server -Force -ErrorAction SilentlyContinue } catch { }
  try { Start-Sleep -Milliseconds 400; if (Test-Path $udd) { Remove-Item $udd -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
}

try {
  Start-Sleep -Milliseconds 800
  try { Invoke-WebRequest "$origin/index.html" -UseBasicParsing -TimeoutSec 5 | Out-Null }
  catch { Write-Host "ERROR: test server did not start"; Cleanup; exit 2 }

  $cargs = @('--headless=new', '--disable-gpu', '--no-sandbox', "--user-data-dir=$udd", '--no-first-run',
             "--remote-debugging-port=$dbg", '--remote-allow-origins=*', 'about:blank')
  $chrome = Start-Process $browser -PassThru -ArgumentList $cargs

  $wsUrl = $null
  for ($i = 0; $i -lt 50; $i++) {
    Start-Sleep -Milliseconds 300
    try {
      $targets = Invoke-RestMethod "http://127.0.0.1:$dbg/json" -TimeoutSec 2
      $pg = $targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
      if ($pg -and $pg.webSocketDebuggerUrl) { $wsUrl = $pg.webSocketDebuggerUrl; break }
    } catch { }
  }
  if (-not $wsUrl) { Write-Host "ERROR: could not reach Chrome debugging endpoint"; Cleanup; exit 2 }

  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  [void]$ws.ConnectAsync([Uri]$wsUrl, $ct).GetAwaiter().GetResult()
  Invoke-CDP 'Page.enable' $null    | Out-Null
  Invoke-CDP 'Runtime.enable' $null | Out-Null

  $viewports = @(@('phone 360x690', 360, 690, $true), @('phone 390x745', 390, 745, $true), @('desktop 1200x900', 1200, 900, $false))

  Write-Host "layout: capture outcome (real index.html, SHIPPED identity contract, CDP, real time):"
  $allOk = $true
  foreach ($v in $viewports) {
    $name = $v[0]; $w = $v[1]; $h = $v[2]; $mob = $v[3]
    Go $w $h $mob

    $S = Measure-Success
    # wantFlag is FOLDED IN, not merely printed: a measurement that does not
    # reach the verdict is decoration, and the flag rendering empty is exactly
    # how this gate passed the slice that added it.
    $sOk = $S.state -eq 'success' -and $S.shown -and $S.lead.inView -and
           $S.primary.inView -and $S.second.inView -and
           $S.primary.h -ge $MIN_ACTION_H -and $S.second.h -ge $MIN_ACTION_H -and
           $S.footHTML -like '*captureAccept()*' -and $S.footHTML -like '*captureDiscard()*' -and
           $S.footHTML -like '*Confirm*' -and $S.nActions -eq 2 -and
           $S.wantFlag.found -and $S.wantFlag.inView -and
           $S.captureSurfaceClean -and (-not $S.pageOverflowX) -and $S.pageScrollY -eq 0
    Write-Host ("  {0,-17} success : question={1} confirm={2}({3}px) discard={4} field={5} oneState={6} wantFlag={7} -> {8}" -f `
      $name, $S.lead.inView, $S.primary.inView, $S.primary.h, $S.second.inView, $S.firstField.found, $S.captureSurfaceClean, $S.wantFlag.inView, $sOk)

    $F = Measure-Fail
    $fOk = $F.state -eq 'error' -and $F.shown -and $F.primary.inView -and $F.second.inView -and
           $F.footHTML -like '*captureRetry()*' -and $F.footHTML -like '*capturePasteInstead()*' -and
           $F.msgText -like '*did not answer*' -and $F.msgText -like '*still counted*' -and
           $F.nActions -eq 2 -and $F.captureSurfaceClean
    Write-Host ("  {0,-17} failure : msg='{1}' retry={2} paste={3} -> {4}" -f `
      $name, ($F.msgText -replace '\s+', ' ').Substring(0, [Math]::Min(52, $F.msgText.Length)), $F.primary.inView, $F.second.inView, $fOk)

    $P = Measure-Pending
    $pOk = $P.state -eq 'pending' -and $P.shown -and $P.spin.inView -and
           $P.primary.inView -and $P.footHTML -like '*byokCancel*' -and
           $P.msgText -match '\d+s' -and $P.nActions -eq 1 -and $P.captureSurfaceClean
    Write-Host ("  {0,-17} pending : spinner={1} counted='{2}' cancel={3} -> {4}" -f `
      $name, $P.spin.inView, ($P.msgText -replace '[^0-9]*(\d+s).*', '$1'), $P.primary.inView, $pOk)

    # R2b: the comps row is THREE FIELDS, and "separated" is a geometric claim.
    # Runs last in each viewport because it dismisses the outcome modal.
    $C = Measure-Comps
    $cOk = $C.found -and $C.priceDateDisjoint -and $C.priceTitleDisjoint -and $C.dateTitleDisjoint -and
           $C.titleBelowPrice -and $C.titleBelowDate -and (-not $C.pageOverflowX)
    if ($C.found) {
      Write-Host ("  {0,-17} comps   : disjoint p/d={1} p/t={2} d/t={3} titleBelow={4} noOverflowX={5} -> {6}" -f `
        $name, $C.priceDateDisjoint, $C.priceTitleDisjoint, $C.dateTitleDisjoint,
        ($C.titleBelowPrice -and $C.titleBelowDate), (-not $C.pageOverflowX), $cOk)
    } else {
      Write-Host ("  {0,-17} comps   : NOT MEASURABLE -- {1} -> False" -f $name, $C.why)
    }

    # R3: the ask marker, its label, the input and the counts -- all geometry.
    $A = Measure-Ask
    $aOk = $A.found -and $A.priceLabelDisjoint -and $A.markerClearOfNeighbours -and
           $A.inputClearOfScatter -and $A.countsVisible -and (-not $A.pageOverflowX) -and
           $A.labelText -like '*YOUR ASK*'
    if ($A.found) {
      Write-Host ("  {0,-17} ask     : price/label={1} clearOfComps={2} inputClear={3} counts={4} noOverflowX={5} -> {6}" -f `
        $name, $A.priceLabelDisjoint, $A.markerClearOfNeighbours, $A.inputClearOfScatter,
        $A.countsVisible, (-not $A.pageOverflowX), $aOk)
    } else {
      Write-Host ("  {0,-17} ask     : NOT MEASURABLE -- {1} -> False" -f $name, $A.why)
    }

    if (-not ($sOk -and $fOk -and $pOk -and $cOk -and $aOk)) { $allOk = $false }
  }

  # The identity draft is a fixed set of fields, so the scroll case is made by a
  # SHORT VIEWPORT rather than a long list: where the draft is taller than the
  # screen, the body must scroll and the footer must not travel with it.
  Go 360 520 $true
  $L = Measure-Success
  $lOk = $L.state -eq 'success' -and $L.shown -and $L.bodyScrolls -and
         $L.lead.inView -and $L.primary.inView -and $L.second.inView -and
         (-not $L.pageOverflowX) -and $L.pageScrollY -eq 0
  Write-Host ("  {0,-17} scrolled: bodyScrolls={1} question={2} confirm={3} discard={4} -> {5}" -f `
    'phone 360x520', $L.bodyScrolls, $L.lead.inView, $L.primary.inView, $L.second.inView, $lOk)
  # The comps row at the TIGHTEST width, where a long seller title is likeliest
  # to overflow. (It also makes the comps-line count four rather than three,
  # which is a coincidence and not the reason: the reason is that 360x520 is the
  # narrowest viewport this gate drives.)
  $CL = Measure-Comps
  $clOk = $CL.found -and $CL.priceDateDisjoint -and $CL.priceTitleDisjoint -and $CL.dateTitleDisjoint -and
          $CL.titleBelowPrice -and $CL.titleBelowDate -and (-not $CL.pageOverflowX)
  if ($CL.found) {
    Write-Host ("  {0,-17} comps   : disjoint p/d={1} p/t={2} d/t={3} titleBelow={4} noOverflowX={5} -> {6}" -f `
      'phone 360x520', $CL.priceDateDisjoint, $CL.priceTitleDisjoint, $CL.dateTitleDisjoint,
      ($CL.titleBelowPrice -and $CL.titleBelowDate), (-not $CL.pageOverflowX), $clOk)
  } else {
    Write-Host ("  {0,-17} comps   : NOT MEASURABLE -- {1} -> False" -f 'phone 360x520', $CL.why)
  }
  if (-not $clOk) { $allOk = $false }

  if (-not $lOk) { $allOk = $false }

  Write-Host ("  thresholds        : exactly one outcome state; the identity question and BOTH actions fully inside the viewport with the page unscrolled; actions >={0}px tall; footer fixed while the body scrolls; capture surface carries no outcome; and a comps row's price, date and title occupy DISJOINT rectangles with the title below both and no horizontal page overflow" -f $MIN_ACTION_H)
  Write-Host "-----------------------------------------"
  if ($allOk) {
    Write-Host "LAYOUT GATE: PASS (one explicit state per capture, in view without scrolling, at every width)"
    Cleanup; exit 0
  }
  Write-Host "LAYOUT GATE: FAIL"
  Cleanup; exit 1
}
catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup; exit 2
}
