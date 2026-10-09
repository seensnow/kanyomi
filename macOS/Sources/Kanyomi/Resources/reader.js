(() => {
  if (window.sr) return;
  const send = (type, data = {}) => window.webkit.messageHandlers.reader.postMessage({type, ...data});
  const ignored = 'rt,rp,script,style,head,noscript,[aria-hidden="true"]';
  const clean = text => text.replace(/\s/g, '');
  let nodes = [], total = 0, restoring = false, lastUser = 0, positionTimer;
  function index() {
    nodes = []; total = 0;
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {acceptNode: n => n.parentElement?.closest(ignored) || !clean(n.data) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT});
    while (walker.nextNode()) { const n = walker.currentNode; nodes.push({node:n, start:total, length:clean(n.data).length}); total += clean(n.data).length; }
  }
  function rawOffset(text, target) { let count = 0; for (let i=0; i<text.length; i++) { if (!/\s/.test(text[i])) { if (count === target) return i; count++; } } return text.length; }
  function offsetOf(node, raw) { const entry = nodes.find(e=>e.node===node); return entry ? entry.start + clean(node.data.slice(0,raw)).length : 0; }
  function rangesAt(offset, length=1) {
    const end=offset+length, ranges=[];
    for(const e of nodes) {
      if(e.start>=end)break;
      if(e.start+e.length<=offset)continue;
      const r=document.createRange();
      r.setStart(e.node,rawOffset(e.node.data,Math.max(0,offset-e.start)));
      r.setEnd(e.node,rawOffset(e.node.data,Math.min(e.length,end-e.start)-1)+1);
      ranges.push(r);
    }
    return ranges;
  }
  function rangeAt(offset,length=1) {
    const ranges=rangesAt(offset,length);if(!ranges.length)return null;
    const r=ranges[0].cloneRange(),last=ranges[ranges.length-1];r.setEnd(last.endContainer,last.endOffset);return r;
  }
  let lookupMark=null, lastLookup=-1;
  function paintLookup() {
    document.querySelectorAll('.sr-lookup-overlay').forEach(el=>el.remove());
    const ranges=lookupMark?rangesAt(lookupMark.offset,lookupMark.length):[];
    if(window.CSS?.highlights && window.Highlight) {
      CSS.highlights.set('sr-lookup',new Highlight(...ranges));return;
    }
    for(const r of ranges)for(const rect of r.getClientRects()) {
      const el=document.createElement('div');el.className='sr-lookup-overlay';el.setAttribute('aria-hidden','true');
      el.style.cssText=`position:fixed;pointer-events:none;z-index:2147483647;background:#c77c5c55;left:${rect.left}px;top:${rect.top}px;width:${rect.width}px;height:${rect.height}px`;
      document.body.append(el);
    }
  }
  function lookupHighlight(offset,length) {lookupMark=length>0?{offset,length}:null;paintLookup()}
  function scrollToOffset(offset) {
    const r=rangeAt(offset); if (!r) return;
    const rect=r.getBoundingClientRect(); const vertical=getComputedStyle(document.body).writingMode.startsWith('vertical');
    if (vertical) window.scrollBy({left:rect.right-innerWidth+64, behavior:'instant'});
    else window.scrollBy({top:rect.top-64, behavior:'instant'});
  }
  function visibleOffset() {
    const vertical=getComputedStyle(document.body).writingMode.startsWith('vertical');
    // Probe the first visible line; fall back to text range rectangles for illustrated pages.
    const xs=vertical ? [innerWidth-68,innerWidth-100,innerWidth-140,innerWidth/2] : [64,96,140,innerWidth/2];
    for (const x of xs) for (const y of [68,100,140,200,innerHeight/2]) {
      const r=document.caretRangeFromPoint(x,y); if (r && nodes.some(e=>e.node===r.startContainer)) return offsetOf(r.startContainer,r.startOffset);
    }
    for (const e of nodes) { const r=document.createRange(); r.selectNodeContents(e.node); const box=r.getBoundingClientRect(); if (box.bottom>0 && box.top<innerHeight && box.right>0 && box.left<innerWidth) return e.start; }
    return total;
  }
  function position() { if(restoring) return; send('position',{offset:visibleOffset(),count:total,reading:Date.now()-lastUser<1500}); }
  function sentenceAt(node, raw) {
    const block=node.parentElement.closest('p,li,div,section') || node.parentElement;
    const text=[...block.childNodes].length ? (()=>{ const w=document.createTreeWalker(block,NodeFilter.SHOW_TEXT,{acceptNode:n=>n.parentElement?.closest(ignored)?NodeFilter.FILTER_REJECT:NodeFilter.FILTER_ACCEPT});let all='',point=0;while(w.nextNode()){if(w.currentNode===node)point=all.length+raw;all+=w.currentNode.data}return {all,point};})() : {all:node.data,point:raw};
    let start=text.point, end=text.point;
    while(start>0 && !/[。！？!?\n]/.test(text.all[start-1]))start--;
    while(end<text.all.length && !/[。！？!?\n]/.test(text.all[end]))end++;
    if(end<text.all.length)end++;
    return text.all.slice(start,end).trim();
  }
  let hover, hoverFrame;
  const segmenter=new Intl.Segmenter('ja',{granularity:'grapheme'}), glyphCache=new WeakMap();
  function adjacentGlyphs(node,raw) {
    let cached=glyphCache.get(node);
    if(!cached || cached.text!==node.data){cached={text:node.data,parts:[...segmenter.segment(node.data)]};glyphCache.set(node,cached)}
    const parts=cached.parts;let low=0,high=parts.length;
    while(low<high){const mid=(low+high)>>1;if(parts[mid].index<raw)low=mid+1;else high=mid}
    return parts.slice(Math.max(0,low-1),Math.min(parts.length,low+1));
  }
  function glyphAt(x,y) {
    const caret=document.caretRangeFromPoint(x,y);
    if(!caret || caret.startContainer.nodeType!==Node.TEXT_NODE)return null;
    const entryIndex=nodes.findIndex(e=>e.node===caret.startContainer);
    if(entryIndex<0)return null;
    // Carets represent insertion positions, so test both adjacent glyphs, including
    // a neighboring text node at a ruby/span boundary. Never accept a nearest glyph.
    for(const e of nodes.slice(Math.max(0,entryIndex-1),entryIndex+2)) {
      for(const part of adjacentGlyphs(e.node,e.node===caret.startContainer?caret.startOffset:e.start<nodes[entryIndex].start?e.node.data.length:0)) {
        if(/\s/.test(part.segment))continue;
        const r=document.createRange();r.setStart(e.node,part.index);r.setEnd(e.node,part.index+part.segment.length);
        if([...r.getClientRects()].some(b=>x>=b.left && x<b.right && y>=b.top && y<b.bottom))return {node:e.node,raw:part.index,length:part.segment.length};
      }
    }
    return null;
  }
  function lookupAt(x,y,selected=false) {
    const selection=window.getSelection(),hasSelection=selected && selection?.rangeCount && !selection.isCollapsed;
    const selectedRange=hasSelection?selection.getRangeAt(0):null;
    const hit=hasSelection?{node:selectedRange.startContainer,raw:selectedRange.startOffset,length:clean(selection.toString()).length}:glyphAt(x,y);
    if(!hit || hit.node.nodeType!==Node.TEXT_NODE || hit.node.parentElement.closest(ignored))return;
    const {node,raw}=hit,offset=offsetOf(node,raw);
    if(!selected && offset===lastLookup)return;
    const block=node.parentElement.closest('p,li,div,section') || node.parentElement;
    let text=hasSelection?clean(selection.toString()):'';
    if(!hasSelection) {
      const startIndex=nodes.findIndex(e=>e.node===node);
      for(const e of nodes.slice(startIndex)) {
        if((e.node.parentElement.closest('p,li,div,section')||e.node.parentElement)!==block)break;
        text+=clean(e.node.data.slice(e.node===node?raw:0));
        if(text.length>=(window.sr.scanLength||24)*2)break;
      }
      text=[...text].slice(0,window.sr.scanLength||24).join('');
    }
    if(!text)return;
    lastLookup=offset;lookupHighlight(offset,hit.length);
    send('lookup',{text,sentence:sentenceAt(node,raw),offset,x,y});
  }
  document.addEventListener('mouseup', e=>{if(e.button!==0 || e.target.closest('a'))return;lastUser=Date.now();lookupAt(e.clientX,e.clientY,true)});
  document.addEventListener('mousemove', e=>{hover={x:e.clientX,y:e.clientY};if(e.shiftKey && !window.getSelection()?.toString() && !hoverFrame){const scan=()=>{hoverFrame=null;lookupAt(hover.x,hover.y)};hoverFrame=document.visibilityState==='hidden'?setTimeout(scan,0):requestAnimationFrame(scan)}});
  document.addEventListener('keydown', e=>{lastUser=Date.now();send('activity');if(e.key==='Shift'&&hover)lookupAt(hover.x,hover.y);if(e.key==='ArrowRight'||e.key==='ArrowLeft'||e.key===' '){if(!window.getSelection()?.toString()){e.preventDefault();window.sr.page(e.key==='ArrowLeft'?-1:1)}}});
  document.addEventListener('wheel',()=>{lastUser=Date.now();send('activity')},{passive:true});
  document.addEventListener('click',e=>{const a=e.target.closest('a');if(a){e.preventDefault();send('link',{href:a.href})}},true);
  window.addEventListener('resize',paintLookup);
  window.addEventListener('scroll',()=>{paintLookup();clearTimeout(positionTimer);positionTimer=setTimeout(position,160)},{passive:true});
  window.sr={
    scanLength:24,
    configure(p){
      restoring=true;
      let style=document.getElementById('sr-style');if(!style){style=document.createElement('style');style.id='sr-style';document.head.append(style)}
      const font=JSON.stringify(p.font);
      // Image-only XHTML often uses a 100% SVG inside fixed-size publisher wrappers.
      // Give it a viewport-sized horizontal canvas independent of text preferences.
      const content=document.body.cloneNode(true);
      content.querySelectorAll(`${ignored},svg`).forEach(el=>el.remove());
      const illustration=!clean(content.textContent) && document.body.querySelectorAll('img,svg').length===1;
      document.body.classList.toggle('sr-illustration',illustration);
      style.textContent=`html{background:${p.background}!important;color:${p.foreground}!important}body{writing-mode:${p.vertical?'vertical-rl':'horizontal-tb'}!important;font-family:${font},serif!important;font-size:${p.fontSize}px!important;line-height:${p.lineHeight}!important;background:${p.background}!important;color:${p.foreground}!important;margin:0!important;padding:64px!important;${p.vertical?'height:calc(100vh - 128px);min-width:calc(100vw - 128px);':'max-width:860px;margin-inline:auto!important;min-height:calc(100vh - 128px);'}box-sizing:content-box}p,div,span,li{font-size:inherit}img,svg{max-width: min(100%,calc(100vw - 128px));max-height:calc(100vh - 128px);object-fit:contain}body.sr-illustration{writing-mode:horizontal-tb!important;display:flex!important;align-items:center;justify-content:center;width:100%!important;max-width:none!important;min-width:0!important;height:100vh!important;min-height:0!important;margin:0!important;padding:24px!important;box-sizing:border-box!important;overflow:hidden}body.sr-illustration :is(div,p,section,figure,a){display:contents!important}body.sr-illustration :is(img,svg){display:block!important;width:100%!important;height:100%!important;max-width:100%!important;max-height:100%!important;object-fit:contain!important}rt{${p.showRuby?'':'visibility:hidden;'}}::selection{background:#c77c5c66}a{color:inherit}::highlight(sr-lookup){background:#c77c5c88;color:inherit}mark.sr-highlight{background:#c77c5c70;color:inherit}${p.customCSS||''}`;
      window.sr.scanLength=p.scanLength;setTimeout(()=>{restoring=false;position()},180);
    },
    restore(offset,fragment){restoring=true;requestAnimationFrame(()=>{if(fragment){document.getElementById(fragment)?.scrollIntoView()}else if(document.body.classList.contains('sr-illustration')) window.scrollTo(0,0);else scrollToOffset(offset);setTimeout(()=>{restoring=false;position()},300)})},
    page(direction){lastUser=Date.now();const vertical=getComputedStyle(document.body).writingMode.startsWith('vertical');window.scrollBy({left:vertical?-direction*(innerWidth-96):0,top:vertical?0:direction*(innerHeight-96),behavior:'smooth'})},
    lookupHighlight,
    highlight(offset,length){const r=rangeAt(offset,length);if(r){const selection=window.getSelection();selection.removeAllRanges();selection.addRange(r)}},
    marks(passages){document.querySelectorAll('mark.sr-highlight').forEach(el=>el.replaceWith(...el.childNodes));index();for(const p of [...passages].sort((a,b)=>b.offset-a.offset)){const r=rangeAt(p.offset,p.text.length);if(r){const mark=document.createElement('mark');mark.className='sr-highlight';try{r.surroundContents(mark)}catch{}}}index();paintLookup()}
  };
  function ready(){index();send('ready',{count:total})}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',ready);else ready();
})();
