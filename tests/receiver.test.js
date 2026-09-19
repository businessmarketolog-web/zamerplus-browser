'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');const path=require('node:path');const os=require('node:os');const {spawn}=require('node:child_process');
(async()=>{
  const home=fs.mkdtempSync(path.join(os.tmpdir(),'zp-test-'));
  const child=spawn(process.execPath,[path.resolve(__dirname,'../desktop-receiver/receiver.js')],{env:{...process.env,HOME:home},stdio:'ignore'});
  try{
    const conf=path.join(home,'Documents','ZamerPlus','receiver-config.json');
    for(let i=0;i<60&&!fs.existsSync(conf);i++)await new Promise(r=>setTimeout(r,100));
    assert(fs.existsSync(conf),'receiver must create pairing config');
    const token=JSON.parse(fs.readFileSync(conf)).token;
    let req=()=>fetch('http://127.0.0.1:8787/status');
    for(let i=0;i<60;i++)try{let r=await req();if(r.ok)break;}catch{await new Promise(r=>setTimeout(r,100))}
    let bad=await fetch('http://127.0.0.1:8787/upload',{method:'POST',body:'{}'});
    assert.equal(bad.status,401);
    const payload={format:'zamerplus-sketchup',version:2,scan:{walls:[{id:'w1',widthMm:4000}]},roomName:'Тест'};
    let ok=await fetch('http://127.0.0.1:8787/upload',{method:'POST',headers:{'X-Zamer-Token':token,'Content-Type':'application/json'},body:JSON.stringify(payload)});
    assert.equal(ok.status,202);
    assert.equal((await ok.json()).status,'queued');
    const files=fs.readdirSync(path.join(home,'Documents','ZamerPlus','Inbox'));
    assert.equal(files.length,1);assert.equal(JSON.parse(fs.readFileSync(path.join(home,'Documents','ZamerPlus','Inbox',files[0]))).roomName,'Тест');
    console.log('PASS: token authorization, LAN status, upload queue, persisted JSON');
  }finally{child.kill();}
})().catch(e=>{console.error(e);process.exitCode=1});
