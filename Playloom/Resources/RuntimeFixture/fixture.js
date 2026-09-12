(() => {
  const send = value => window.webkit.messageHandlers.playloom.postMessage(value);
  const canvas = document.querySelector('#game');
  const context = canvas.getContext('2d', {willReadFrequently:true});
  let x = 48, frame = 0;
  function draw() {
    context.fillStyle = '#101522'; context.fillRect(0,0,canvas.width,canvas.height);
    context.fillStyle = '#50e3c2'; context.fillRect(x,210,36,36);
    context.fillStyle = '#fff'; context.font = '20px system-ui'; context.fillText('Playloom',108,64);
  }
  function loop() { frame += 1; x = 48 + Math.sin(frame / 30) * 20; draw(); requestAnimationFrame(loop); }
  setInterval(() => send({type:'heartbeat',frame}), 50);
  canvas.addEventListener('pointerdown', () => send({type:'input'}));
  window.playloomProbeInput = () => canvas.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true}));
  window.playloomRestart = () => { frame=0; x=48; draw(); send({type:'restarted'}); };
  window.playloomPixelSample = () => {
    const data=context.getImageData(0,0,canvas.width,canvas.height).data; let changed=0;
    for(let i=0;i<data.length;i+=4) if(data[i]!==16 || data[i+1]!==21 || data[i+2]!==34) changed++;
    return {changedRatio:changed/(data.length/4),width:canvas.width,height:canvas.height};
  };
  window.playloomPixelSampleText = () => {
    const sample=window.playloomPixelSample();
    return `${sample.changedRatio},${sample.width},${sample.height}`;
  };
  draw(); send({type:'ready'}); requestAnimationFrame(loop);
})();
