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
  function rangeAt(offset, length=1) {
    const e = nodes.find(e=>offset >= e.start && offset < e.start+e.length) || nodes[nodes.length-1];
    if (!e) return null;
    const r=document.createRange(), start=rawOffset(e.node.data, Math.max(0,offset-e.start));
    r.setStart(e.node,start); r.setEnd(e.node, Math.min(e.node.data.length,start+length)); return r;
  }
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
  let hover;
  function lookupAt(x,y,selected=false) {
    const selection=window.getSelection();
    let r=selected && selection?.rangeCount && !selection.isCollapsed ? selection.getRangeAt(0) : document.caretRangeFromPoint(x,y);
    if(!r || r.startContainer.nodeType!==Node.TEXT_NODE || r.startContainer.parentElement.closest(ignored))return;
    const node=r.startContainer, raw=r.startOffset;
    const text=selected && !selection.isCollapsed ? selection.toString().trim() : node.data.slice(raw).replace(/^\s+/,'').slice(0,window.sr.scanLength||24);
    if(!text)return;
    send('lookup',{text,sentence:sentenceAt(node,raw),offset:offsetOf(node,raw),x,y});
  }
  document.addEventListener('mouseup', e=>{if(e.button!==0)return; lastUser=Date.now();setTimeout(()=>lookupAt(e.clientX,e.clientY,true),0)});
  document.addEventListener('mousemove', e=>{hover={x:e.clientX,y:e.clientY}; if(e.shiftKey && !window.getSelection()?.toString()){clearTimeout(window.sr.hoverTimer);window.sr.hoverTimer=setTimeout(()=>lookupAt(e.clientX,e.clientY),180)}});
  document.addEventListener('keydown', e=>{lastUser=Date.now();send('activity');if(e.key==='Shift'&&hover)lookupAt(hover.x,hover.y);if(e.key==='ArrowRight'||e.key==='ArrowLeft'||e.key===' '){if(!window.getSelection()?.toString()){e.preventDefault();window.sr.page(e.key==='ArrowLeft'?-1:1)}}});
  document.addEventListener('wheel',()=>{lastUser=Date.now();send('activity')},{passive:true});
  document.addEventListener('click',e=>{const a=e.target.closest('a');if(a){e.preventDefault();send('link',{href:a.href})}},true);
  window.addEventListener('scroll',()=>{clearTimeout(positionTimer);positionTimer=setTimeout(position,160)},{passive:true});
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
      style.textContent=`html{background:${p.background}!important;color:${p.foreground}!important}body{writing-mode:${p.vertical?'vertical-rl':'horizontal-tb'}!important;font-family:${font},serif!important;font-size:${p.fontSize}px!important;line-height:${p.lineHeight}!important;background:${p.background}!important;color:${p.foreground}!important;margin:0!important;padding:64px!important;${p.vertical?'height:calc(100vh - 128px);min-width:calc(100vw - 128px);':'max-width:860px;margin-inline:auto!important;min-height:calc(100vh - 128px);'}box-sizing:content-box}p,div,span,li{font-size:inherit}img,svg{max-width: min(100%,calc(100vw - 128px));max-height:calc(100vh - 128px);object-fit:contain}body.sr-illustration{writing-mode:horizontal-tb!important;display:flex!important;align-items:center;justify-content:center;width:100%!important;max-width:none!important;min-width:0!important;height:100vh!important;min-height:0!important;margin:0!important;padding:24px!important;box-sizing:border-box!important;overflow:hidden}body.sr-illustration :is(div,p,section,figure,a){display:contents!important}body.sr-illustration :is(img,svg){display:block!important;width:100%!important;height:100%!important;max-width:100%!important;max-height:100%!important;object-fit:contain!important}rt{${p.showRuby?'':'visibility:hidden;'}}::selection{background:#d6b98b66}a{color:inherit}mark.sr-highlight{background:#d5ad5670;color:inherit}${p.customCSS||''}`;
      window.sr.scanLength=p.scanLength;setTimeout(()=>{restoring=false;position()},180);
    },
    restore(offset,fragment){restoring=true;requestAnimationFrame(()=>{if(fragment){document.getElementById(fragment)?.scrollIntoView()}else if(document.body.classList.contains('sr-illustration')) window.scrollTo(0,0);else scrollToOffset(offset);setTimeout(()=>{restoring=false;position()},300)})},
    page(direction){lastUser=Date.now();const vertical=getComputedStyle(document.body).writingMode.startsWith('vertical');window.scrollBy({left:vertical?-direction*(innerWidth-96):0,top:vertical?0:direction*(innerHeight-96),behavior:'smooth'})},
    highlight(offset,length){const r=rangeAt(offset,length);if(r){const selection=window.getSelection();selection.removeAllRanges();selection.addRange(r)}},
    marks(passages){document.querySelectorAll('mark.sr-highlight').forEach(el=>el.replaceWith(...el.childNodes));index();for(const p of [...passages].sort((a,b)=>b.offset-a.offset)){const r=rangeAt(p.offset,p.text.length);if(r){const mark=document.createElement('mark');mark.className='sr-highlight';try{r.surroundContents(mark)}catch{}}}index()}
  };
  function ready(){index();send('ready',{count:total})}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',ready);else ready();
})();
