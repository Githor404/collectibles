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
# C1's REPLAY SAVE (2026-09-16) is measured here too, and it is not a layout
# claim: it is a SHIPPED-ELEMENT claim, which this is the only harness able to
# make. Real touch events on the Settings card, a real paste, and the key read
# straight out of localStorage. Every RP1 assertion called replaySave() by hand,
# so a save that said nothing on the real surface passed all of them.
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
      // R6: THE VERTICAL SLACK. The named conflict is that a larger type scale
      // makes the draft taller while this gate requires the identity question
      // and BOTH actions in view with the page unscrolled. That conflict is a
      // NUMBER, not an argument -- how many pixels the draft can absorb before
      // the body scrolls -- and it is measured before the scale is designed
      // rather than estimated around.
      //
      // Reported, deliberately NOT folded into the verdict: it is a measurement,
      // not yet a threshold, and turning it into a pass/fail before knowing its
      // value would be designing around an estimate by another route.
      bodyH:    body ? Math.round(body.clientHeight) : -1,
      contentH: body ? Math.round(body.scrollHeight) : -1,
      slack:    body ? Math.round(body.clientHeight - body.scrollHeight) : -1,
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
    // R5: THE LIST IS NOW FOLDED, and this measurement had to move with it.
    // getBoundingClientRect() on content inside a CLOSED <details> returns all
    // zeros -- and hit() reports two zero-size rectangles as NOT intersecting,
    // so every disjointness check below would have passed VACUOUSLY. Not a
    // failure: a false green, which is worse.
    //
    // Opened rather than un-folded, because the property is about what the
    // reader sees WHEN THEY OPEN IT. A fold does not make a layout defect
    // acceptable; it just postpones it.
    // R6: THE LIST IS SUMMONED NOW, NOT FOLDED. Opening a <details> no longer
    // reveals it -- there is no details around it to open -- so this asks for
    // the rows the way a person does. The property being measured is unchanged:
    // when the rows ARE on screen, their three fields occupy disjoint
    // rectangles. A fold never made a layout defect acceptable, and neither
    // does a summon; it only postpones when you see it.
    //
    // Guarded rather than toggled blindly: __g.comps runs once per viewport, and
    // an unguarded flip would hide the list on every second call.
    if (!CT.compsListShown()) CT.compsListToggle();
    var row = document.querySelector('#compsBox .cmplist .cmprow');
    if (!row) return { found:false, why:'no .cmplist .cmprow rendered (list summoned first)' };
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
  // R5: THE PLOT, MEASURED POPULATED. Presence is not the property -- an SVG
  // whose marks all sit at one x, or whose marks have no size, satisfies every
  // naive check. The want-list shipped exactly that failure one slice ago: a
  // layout gate passed while the element it measured rendered nothing, because a
  // fresh profile had no wants and the flag returned ''.
  //
  // The seed carries listingType, which the older fixtures do not. Without it
  // every mark takes the `unstated` path and the shape encoding goes unmeasured
  // at the ONE place that can actually see shapes.
  // R6: THE TYPE FLOOR, measured on the SHIPPED page rather than read off the
  // stylesheet. Declared sizes are not rendered sizes -- inheritance, shorthand
  // and SVG presentation attributes all intervene -- so the claim "nothing below
  // 12px" is only a claim about what a person sees if it is measured from
  // getComputedStyle at the width they hold.
  //
  // D17 is the failure this guards: a slice's own chrome gets sized last and
  // smallest, because its author reads it at desk distance on a large screen.
  // The two smallest declarations in the app were the plot's own axis ticks and
  // its "YOUR ASK" label, at 9px. Nothing failed; nobody saw.
  __g.typefloor = function(){
    var seen = [], under = [];
    var els = document.querySelectorAll(
      '#compsBox *, #askBox *, #captureResult *, #confirmedBox *, .about, .card h2, .note, .fine');
    Array.prototype.forEach.call(els, function (e) {
      var t = (e.textContent || '').trim();
      if (!t) return;                       // no text, nothing to read
      if (e.children.length) return;        // measure LEAVES, not containers
      var px = parseFloat(window.getComputedStyle(e).fontSize);
      if (!(px > 0)) return;
      if (seen.indexOf(px) < 0) seen.push(px);
      // getAttribute, NOT .className. On an SVG element className is an
      // SVGAnimatedString OBJECT, so the diagnostic read
      // "[object SVGAnimatedString]=9px:$10" -- it caught the right elements and
      // could not name them. For the one class of element this gate exists for
      // (D17: a slice's own chrome, sized last and smallest), the diagnostic was
      // useless exactly where it mattered. Found by planting the defect and
      // READING the output rather than trusting that a failure would explain
      // itself.
      if (px < 12) under.push(((e.getAttribute && e.getAttribute('class')) || e.tagName) +
                              '=' + px + 'px:' + t.slice(0, 24));
    });
    return { found: true, sizes: seen.sort(function(a,b){return a-b;}).join(','),
             under: under.slice(0, 6).join(' | '), underCount: under.length };
  };
  __g.plot = function(){
    CT.byokCancel(); CT.byokBusyClear(); CT.captureDiscard(); CT.clearConfirmed();
    CT.__setComps([
      { itemId:'b1', title:'Hulk 271 GD', endedAt:'2026-08-01T09:00:00Z', soldPrice:9,
        soldCurrency:'USD', listingType:'Auction', bestOffer:false },
      { itemId:'b2', title:'Hulk 271 VG', endedAt:'2026-08-02T09:00:00Z', soldPrice:25,
        soldCurrency:'USD', listingType:'FixedPrice', bestOffer:true },
      { itemId:'b3', title:'Hulk 271 FN', endedAt:'2026-08-03T09:00:00Z', soldPrice:40,
        soldCurrency:'USD', listingType:'Auction', bestOffer:false },
      { itemId:'b4', title:'Hulk 271 CGC 9.8', endedAt:'2026-08-04T09:00:00Z', soldPrice:145,
        soldCurrency:'USD', listingType:'FixedPrice', bestOffer:false }
    ], [], 'Incredible Hulk 271');
    CT.askSetPrice('30');
    var svg = document.querySelector('#compsBox .plotsvg');
    if (!svg) return { found:false, why:'no .plotsvg rendered' };
    var marks = Array.prototype.slice.call(svg.querySelectorAll('g.pm'));
    var rule  = svg.querySelector('.askrule');
    if (!marks.length || !rule) return { found:false, why:'marks=' + marks.length + ' askrule=' + !!rule };
    var R = function(e){ var b=e.getBoundingClientRect();
      return { left:Math.round(b.left), right:Math.round(b.right), w:Math.round(b.width), h:Math.round(b.height),
               cx:(b.left + b.right) / 2 }; };
    var S = R(svg), RU = R(rule);
    var MS = marks.map(R);
    var xs = MS.map(function(m){ return m.cx; });
    var below = [], above = [];
    marks.forEach(function (g, i) {
      var p = Number(g.getAttribute('data-p'));
      if (p < 30) below.push(MS[i].cx); else if (p > 30) above.push(MS[i].cx);
    });
    return {
      found:true,
      plotW:S.w, plotH:S.h,
      markCount: marks.length,
      // Every mark has real extent -- a zero-size mark is invisible and would
      // still satisfy a count.
      allMarksDrawn: MS.every(function(m){ return m.w > 0 && m.h > 0; }),
      // The marks SPREAD. If the scale collapsed, every mark would share one x
      // and the plot would be a single stripe that still counted correctly.
      xSpread: Math.round(Math.max.apply(null, xs) - Math.min.apply(null, xs)),
      // The ask rule between its neighbours, MEASURED ON SCREEN rather than
      // recomputed from compsScale -- the data-layer gate already asserts the
      // arithmetic; this asserts the picture.
      ruleRightOfBelow: below.length ? RU.cx > Math.max.apply(null, below) : true,
      ruleLeftOfAbove:  above.length ? RU.cx < Math.min.apply(null, above) : true,
      shapes: {
        circles: svg.querySelectorAll('g.pm-auction circle').length,
        rects:   svg.querySelectorAll('g.pm-bin rect').length,
        rings:   svg.querySelectorAll('g.pm circle.pmring').length
      },
      pageOverflowX: document.documentElement.scrollWidth > window.innerWidth + 1
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
function Measure-Plot {
  return (Eval '(function(){ return JSON.stringify(__g.plot()); })()' | ConvertFrom-Json)
}
function Measure-TypeFloor {
  return (Eval '(function(){ return JSON.stringify(__g.typefloor()); })()' | ConvertFrom-Json)
}

# ---- C1's SAVE, driven the way a thumb drives it (2026-09-16) ----------------
# A snapshot of everything a person, or the arm, could learn after a tap: what
# the card says, whether it is drawn, and what is ACTUALLY in the key -- read
# from localStorage directly, never through the app's own Store, because the
# app's read path is one of the things under test.
$rsSnap = @'
(function(){
  var r = document.getElementById('replayReport'), a = document.getElementById('replayArm'), k = null, rec = null;
  try { k = localStorage.getItem('collectibles-replay'); } catch (e) {}
  try { rec = k ? JSON.parse(k) : null; } catch (e) {}
  var b = r ? r.getBoundingClientRect() : null;
  return JSON.stringify({
    report: r ? r.textContent.replace(/\s+/g, ' ').trim() : '',
    err: r ? Array.prototype.map.call(r.querySelectorAll('.idna'), function (x) { return x.textContent; }).join(' | ') : '',
    drawn: !!b && b.width > 0 && b.height > 0,
    inView: !!b && b.top >= 0 && b.bottom <= innerHeight,
    armDisabled: a ? a.disabled : null,
    keyLen: k ? k.length : 0,
    keyIsGood: !!rec && typeof window.__rsGood === 'string' && rec.raw === window.__rsGood,
    keyRows: rec ? rec.rows : null,
    tier: CT.Store.tier
  });
})()
'@
function RS-Snap { return (Eval $rsSnap | ConvertFrom-Json) }
# A REAL TOUCH at the element's centre -- after checking the point is ON the
# element. A tap that lands on an overlay is its own silent failure, and a
# gate that dispatched el.click() would walk straight past it.
function RS-Tap([string]$sel) {
  $q = ($sel | ConvertTo-Json)
  $p = Eval ("(function(){ var el = document.querySelector($q); if (!el) return JSON.stringify({ found: false });" +
             " el.scrollIntoView({ block: 'center' }); var b = el.getBoundingClientRect();" +
             " var x = b.left + b.width / 2, y = b.top + b.height / 2, hit = document.elementFromPoint(x, y);" +
             " return JSON.stringify({ found: true, x: x, y: y, text: (el.textContent || '').trim()," +
             " onTarget: !!hit && (hit === el || el.contains(hit)) }); })()") | ConvertFrom-Json
  if ($p.found) {
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart'; touchPoints = @(@{ x = $p.x; y = $p.y }) } | Out-Null
    Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchEnd'; touchPoints = @() } | Out-Null
    Start-Sleep -Milliseconds 400
  }
  return $p
}
# A PASTE, as the browser receives one: focus, select what is there, insert.
function RS-Paste([string]$text) {
  Eval "(function(){ var b = document.getElementById('replayBox'); b.focus(); b.select(); return 1; })()" | Out-Null
  Invoke-CDP 'Input.insertText' @{ text = $text } | Out-Null
}
$script:rsOk = $true
# One line per claim. A failing line carries "FAIL:" so defect-pass.sh's strict
# arm can name it -- the other layout cases print "-> False", which it cannot.
function RS([bool]$ok, [string]$claim) {
  if ($ok) { Write-Host "  replay save       ok  : $claim" }
  else     { Write-Host "  replay save       FAIL: $claim"; $script:rsOk = $false }
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
    # R6's first measurement, reported on its own line so it is read rather than
    # buried in the verdict line's tail. Positive slack = pixels of type growth
    # the draft can absorb before it scrolls.
    Write-Host ("  {0,-17} typeroom: body={1}px content={2}px SLACK={3}px  (not a verdict -- the number the type scale is designed against)" -f `
      $name, $S.bodyH, $S.contentH, $S.slack)

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
    # NON-DEGENERATE RECTANGLES, and this closes a hole that has been here since
    # the comps case was written. hit() reports two ZERO-SIZE rects as not
    # intersecting: P.right(0) <= M.left(0) is true, so "disjoint" is true, and
    # titleBelowPrice becomes 0 >= -1, also true. EVERY comps fact passes
    # vacuously on collapsed rectangles.
    #
    # R5 made that reachable for the first time by folding the list into a
    # <details>, where getBoundingClientRect() returns all zeros. The fold is
    # opened before measuring -- but a gate that would have read a false green
    # either way is not measuring anything, so the sizes are now part of the
    # verdict rather than something to squint at in a log line.
    $cDrawn = $C.price.w -gt 0 -and $C.price.h -gt 0 -and $C.title.w -gt 0 -and $C.title.h -gt 0
    $cOk = $C.found -and $cDrawn -and $C.priceDateDisjoint -and $C.priceTitleDisjoint -and $C.dateTitleDisjoint -and
           $C.titleBelowPrice -and $C.titleBelowDate -and (-not $C.pageOverflowX)
    if ($C.found) {
      Write-Host ("  {0,-17} comps   : drawn={1} ({2}x{3}px) disjoint p/d={4} p/t={5} d/t={6} titleBelow={7} noOverflowX={8} -> {9}" -f `
        $name, $cDrawn, $C.price.w, $C.price.h, $C.priceDateDisjoint, $C.priceTitleDisjoint, $C.dateTitleDisjoint,
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

    # R5: the distribution, measured POPULATED. Named $plOk and deliberately not
    # $pOk -- that is the PENDING verdict above, and shadowing it would drop the
    # pending case out of the fold while everything still read green. That is the
    # coverage-shrinks-silently failure this slice already had to fix in AK6.
    $P = Measure-Plot
    $plOk = $P.found -and $P.allMarksDrawn -and $P.markCount -eq 4 -and $P.xSpread -gt 40 -and
            $P.ruleRightOfBelow -and $P.ruleLeftOfAbove -and (-not $P.pageOverflowX) -and
            $P.shapes.circles -eq 2 -and $P.shapes.rects -eq 2 -and $P.shapes.rings -eq 1
    if ($P.found) {
      Write-Host ("  {0,-17} plot    : marks={1} drawn={2} spread={3}px rule>below={4} rule<above={5} shapes={6}c/{7}r/{8}ring noOverflowX={9} -> {10}" -f `
        $name, $P.markCount, $P.allMarksDrawn, $P.xSpread, $P.ruleRightOfBelow, $P.ruleLeftOfAbove,
        $P.shapes.circles, $P.shapes.rects, $P.shapes.rings, (-not $P.pageOverflowX), $plOk)
    } else {
      Write-Host ("  {0,-17} plot    : NOT MEASURABLE -- {1} -> False" -f $name, $P.why)
    }

    # R6: the type floor, on the SHIPPED page. Named $tfOk and checked against
    # every other verdict name in this loop -- $sOk $fOk $pOk $cOk $aOk $plOk --
    # because shadowing one would drop its case out of the fold while the line
    # above still printed green. That was a live hazard when the plot verdict
    # was added ($pOk is PENDING), and it is cheap to re-check.
    $TF = Measure-TypeFloor
    $tfOk = $TF.found -and $TF.underCount -eq 0
    Write-Host ("  {0,-17} type    : sizes={1} belowFloor={2} -> {3}" -f `
      $name, $TF.sizes, $TF.underCount, $tfOk)
    if ($TF.underCount -gt 0) {
      Write-Host ("  {0,-17}           under 12px: {1}" -f $name, $TF.under)
    }

    if (-not ($sOk -and $fOk -and $pOk -and $cOk -and $aOk -and $plOk -and $tfOk)) { $allOk = $false }
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
  # THE SECOND CALL SITE, and it was found only because the first one started
  # printing its measured rectangle while this one did not. Both need the guard:
  # hit() reports two ZERO-SIZE rects as not intersecting, so a collapsed row
  # passes every disjointness check rather than failing them.
  #
  # Fixing one of two sites and calling the hole closed would have been the
  # coverage-shrinks-silently failure this slice already had to fix twice -- in
  # AK6's sweep, and in report()'s weak arm.
  $clDrawn = $CL.price.w -gt 0 -and $CL.price.h -gt 0 -and $CL.title.w -gt 0 -and $CL.title.h -gt 0
  $clOk = $CL.found -and $clDrawn -and $CL.priceDateDisjoint -and $CL.priceTitleDisjoint -and $CL.dateTitleDisjoint -and
          $CL.titleBelowPrice -and $CL.titleBelowDate -and (-not $CL.pageOverflowX)
  if ($CL.found) {
    Write-Host ("  {0,-17} comps   : drawn={1} ({2}x{3}px) disjoint p/d={4} p/t={5} d/t={6} titleBelow={7} noOverflowX={8} -> {9}" -f `
      'phone 360x520', $clDrawn, $CL.price.w, $CL.price.h, $CL.priceDateDisjoint, $CL.priceTitleDisjoint, $CL.dateTitleDisjoint,
      ($CL.titleBelowPrice -and $CL.titleBelowDate), (-not $CL.pageOverflowX), $clOk)
  } else {
    Write-Host ("  {0,-17} comps   : NOT MEASURABLE -- {1} -> False" -f 'phone 360x520', $CL.why)
  }
  if (-not $clOk) { $allOk = $false }

  if (-not $lOk) { $allOk = $false }

  # ---- C1's SAVE, on the SHIPPED element, with REAL taps (2026-09-16) --------
  # Reported from use: a real Apify response pasted, Save tapped, and NOTHING --
  # no confirmation, no error -- then arming failed. Every RP1 assertion drives
  # CT.replaySave() directly, so nothing had ever pressed the button: D16's
  # second sub-failure, the harness supplying the CALL.
  #
  # Measured before this was written, through the same taps: on a healthy tier
  # the save WORKED on v0.9.0 -- the button is wired and takes the touch. The
  # silence was the MEMORY tier. One failed state save demotes it for the
  # session; readRaw then returns null for every key while writeRaw still
  # writes; the save reported ok, and the card re-rendered "Nothing saved",
  # byte-identical to the card before the tap. RS4 is that case, exactly.
  #
  # ONE REAL PASTE OF THE FULL RESPONSE, and why only one. Input.insertText
  # takes ~15s for the 100KB response (measured 2026-09-16: 15480ms, 15172ms),
  # and pasting it four times put ~60s on every run of this gate and on every
  # defect row that runs it. The full response goes in once, for RS1 -- the
  # reported case. RS3 reuses what is already in the box; the storage cases
  # (RS5, RS4) paste the first three rows of the same response, because their
  # claims are about the tier and the read-back, not about size.
  $RS_FIXTURE = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixtures\comps-asm-151-2026-09-15.json'))
  $RS_SMALL = ConvertTo-Json -InputObject @(($RS_FIXTURE | ConvertFrom-Json)[0..2]) -Depth 5 -Compress
  $SAVE = '#replayBox + button'
  Write-Host "layout: replay save (C1's Settings card, REAL touch on the shipped elements, phone 390x745):"
  Go 390 745 $true
  Eval "(function(){ try { localStorage.removeItem('collectibles-replay'); } catch (e) {} return 1; })()" | Out-Null
  Go 390 745 $true
  $s0 = RS-Snap
  RS ($s0.keyLen -eq 0 -and $s0.report -like '*Nothing saved*' -and $s0.armDisabled -eq $true) `
     "CONTROL: before any tap the key is absent, the card says nothing is saved, arming is disabled -- '$($s0.report)'"
  $t = RS-Tap '#settingsBtn'
  RS ($t.found -and $t.onTarget) 'SETUP: the Settings button takes the tap'
  RS-Paste $RS_FIXTURE
  Eval "(function(){ window.__rsGood = document.getElementById('replayBox').value.trim(); return 1; })()" | Out-Null
  $n = [int](Eval "CT.parseComps(document.getElementById('replayBox').value).rows.length")
  RS ($n -gt 0) "SETUP: the real Apify fixture parses to $n listings -- a success case over zero rows proves nothing"

  # THE PLANTED CONTROL. If the paste alone, or any tap at all, wrote the key or
  # changed the card, RS1 would pass without the button doing anything.
  $t = RS-Tap '[data-setting="replay"] h2'
  $sI = RS-Snap
  RS ($t.found -and $sI.keyLen -eq 0 -and $sI.report -eq $s0.report) `
     'CONTROL: a tap on the card heading, response pasted, saves nothing and changes nothing'

  $t = RS-Tap $SAVE
  $s1 = RS-Snap
  RS ($t.found -and $t.onTarget -and $t.text -like 'Save*') `
     "RS1 GATE: the tap lands ON the save button -- found=$($t.found) onTarget=$($t.onTarget) text='$($t.text)'"
  RS ($s1.keyIsGood -and $s1.keyRows -eq $n) `
     "RS1 GATE: the key holds the pasted response, parsed -- keyLen=$($s1.keyLen) rows=$($s1.keyRows)"
  RS ($s1.report -ne $s0.report -and ([string]$s1.report).Contains("$n listings saved") -and $s1.drawn -and $s1.inView) `
     "RS1 GATE: the card says it was saved, with the parsed count, drawn and in view -- '$($s1.report)'"
  RS (([string]$s1.report).Contains('Saved and read back')) `
     "RS1 GATE: the card acknowledges THIS tap, not only the standing summary a reload would also show -- '$($s1.report)'"
  RS ($s1.armDisabled -eq $false) 'RS1 GATE: arming is enabled once something is saved'

  # A THROW IS A RESULT TOO. A phone has no console, so an exception in an
  # inline handler is visible nowhere unless the card shows it. Planted by
  # swapping the global parseComps for one tap; the box still holds RS1's paste.
  Eval "(function(){ window.__rsPC = parseComps; parseComps = function () { throw new Error('planted parser throw'); }; return 1; })()" | Out-Null
  RS-Tap $SAVE | Out-Null
  $s3 = RS-Snap
  Eval "(function(){ parseComps = window.__rsPC; return 1; })()" | Out-Null
  RS (([string]$s3.err).Contains('planted parser throw') -and $s3.keyIsGood) `
     "RS3 GATE: a throw inside the save is reported on the card, and the saved response is untouched -- card '$($s3.err)'"

  # THE PARSER'S OWN MESSAGE, across both refusals parseComps has (D3: the
  # range, not one specimen). Read from the parser at run time, never pinned
  # here -- a pinned literal is how row 55 died.
  $msgs = @()
  foreach ($g in @(@('not JSON', 'not a response'), @('JSON but not a list', '{"items":[]}'))) {
    RS-Paste $g[1]
    $m = [string](Eval ("CT.parseComps(" + ($g[1] | ConvertTo-Json) + ", 'paste').error"))
    RS-Tap $SAVE | Out-Null
    $s2 = RS-Snap
    RS ($m -ne '' -and ([string]$s2.err).Contains($m)) `
       "RS2 GATE: a paste that is $($g[0]) shows the parser's own message on the card -- expected '$m', card '$($s2.err)'"
    # D27. The same parser answers the live lookup, where "the provider sent"
    # is true. On a paste it blamed a party that did nothing, and pointed away
    # from the recovery that works.
    RS (([string]$s2.err) -ne '' -and -not ([string]$s2.err).ToLower().Contains('provider') -and ([string]$s2.err).ToLower().Contains('paste')) `
       "RS2 GATE: a paste that is $($g[0]) is refused as the PASTE's fault, not the provider's -- card '$($s2.err)'"
    RS ($s2.keyIsGood) "RS2 GATE: the saved response survives a paste that is $($g[0])"
    $msgs += $m
  }
  RS ($msgs.Count -eq 2 -and $msgs[0] -ne $msgs[1]) `
     'RS2 GATE: the two refusals carry DIFFERENT parser messages -- one message for both would mean one branch was never reached'

  # THE REPEAT TAP -- what was actually hit. An amber line went unread, Save was
  # tapped again, the same outcome rendered the same card, and an identical card
  # read as a dead control. Same paste, same outcome, a second later: the card
  # must still CHANGE, and the outcome must not (so the change is the answer,
  # not a different result).
  Start-Sleep -Milliseconds 1100
  $r6a = RS-Snap
  RS-Tap $SAVE | Out-Null
  $r6b = RS-Snap
  RS ($r6a.err -ne '' -and $r6b.err -eq $r6a.err -and $r6b.report -ne $r6a.report) `
     "RS6 GATE: a second tap with the same paste CHANGES the card -- an identical card reads as a dead control -- before '$($r6a.report)' after '$($r6b.report)'"

  # THE READ-BACK, on a HEALTHY tier. A write the arm cannot read is not a save,
  # whatever the write returned. Planted by blinding readRaw to this key alone.
  RS-Paste $RS_SMALL
  $ns = [int](Eval "CT.parseComps(document.getElementById('replayBox').value).rows.length")
  RS ($ns -gt 0) "SETUP: the three-row slice parses to $ns listings -- a refusal of an empty response would prove nothing about storage"
  Eval ("(function(){ localStorage.removeItem('collectibles-replay'); window.__rsRR = CT.Store.readRaw;" +
        " CT.Store.readRaw = function (k) { return k === 'collectibles-replay' ? null : window.__rsRR(k); }; return 1; })()") | Out-Null
  RS-Tap $SAVE | Out-Null
  $s5 = RS-Snap
  Eval "(function(){ CT.Store.readRaw = window.__rsRR; return 1; })()" | Out-Null
  RS ($s5.tier -eq 'local' -and ([string]$s5.err) -ne '' -and -not ([string]$s5.report).Contains('Saved and read back') -and $s5.armDisabled -eq $true) `
     "RS5 GATE: a write that cannot be read back is reported as a failure, never as a save -- tier=$($s5.tier) card '$($s5.report)'"

  # THE REPORTED DEFECT. The tier is demoted through the shipped Store's own
  # test seam; the save is still a real tap on the real button.
  Eval "(function(){ try { localStorage.removeItem('collectibles-replay'); } catch (e) {} return 1; })()" | Out-Null
  Go 390 745 $true
  $tier = Eval "(function(){ CT.Store.forceWriteFailure(true); CT.resave(); CT.Store.forceWriteFailure(false); return CT.Store.tier; })()"
  RS ($tier -eq 'memory') "RS4 SETUP: one failed state save drops the tier to memory -- tier=$tier"
  RS-Tap '#settingsBtn' | Out-Null
  RS-Paste $RS_SMALL
  $b4 = RS-Snap
  $t = RS-Tap $SAVE
  $s4 = RS-Snap
  RS ($t.onTarget -and $s4.report -ne $b4.report -and ([string]$s4.err).ToLower().Contains('memory')) `
     "RS4 GATE: on the memory tier the card CHANGES and names memory as the cause -- before '$($b4.report)' after '$($s4.report)'"
  RS ($s4.keyLen -eq 0) "RS4 GATE: on the memory tier nothing is written, so 'not saved' is true -- keyLen=$($s4.keyLen)"
  RS ($s4.armDisabled -eq $true) 'RS4 GATE: arming stays disabled on the memory tier'
  if (-not $script:rsOk) { $allOk = $false }

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
