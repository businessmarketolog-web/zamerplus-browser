'use strict';
// Zamer+ local receiver: keep this service inside a trusted private LAN.
const http=require('node:http');
const crypto=require('node:crypto');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const ROOT=path.join(os.homedir(),'Documents','ZamerPlus');
const INBOX=path.join(ROOT,'Inbox');
const CONF=path.join(ROOT,'receiver-config.json');
const PORT=8787;
fs.mkdirSync(INBOX,{recursive:true});
let config;
if(fs.existsSync(CONF))config=JSON.parse(fs.readFileSync(CONF,'utf8'));
else{
  config={token:crypto.randomBytes(24).toString('hex'),createdAt:new Date().toISOString()};
  fs.writeFileSync(CONF,JSON.stringify(config,null,2),{flag:'wx',mode:0o600});
}
if(!/^[0-9a-f]{48}$/.test(config.token))throw Error('Invalid receiver token');
function authorized(req){
  const sent=String(req.headers['x-zamer-token']||'');
  if(!/^[0-9a-f]{48}$/.test(sent))return false;
  return crypto.timingSafeEqual(Buffer.from(sent),Buffer.from(config.token));
}
function send(res,code,body){
  res.writeHead(code,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
  res.end(JSON.stringify(body));
}
function checkPayload(p){
  if(!p||typeof p!=='object'||!['zamerplus-sketchup','zamerplus-project'].includes(p.format))return false;
  if(p.format==='zamerplus-sketchup')return Array.isArray(p.scan?.walls)&&p.scan.walls.length>0&&p.scan.walls.length<=1000;
  return Array.isArray(p.rooms)&&p.rooms.length>0&&p.rooms.length<=100&&p.rooms.every(r=>Array.isArray(r.scan?.walls)&&r.scan.walls.length>0&&r.scan.walls.length<=1000);
}
function octets(ip){
  ip=String(ip||'').replace(/^::ffff:/,'');
  const p=ip.split('.');
  if(p.length!==4||p.some(x=>x.length<1||x.length>3||!/^[0-9]+$/.test(x)))return null;
  const x=p.map(Number);
  return x.some(v=>!Number.isInteger(v)||v<0||v>255)?null:x;
}
function tailscaleIP(ip){
  const x=octets(ip);
  return Boolean(x&&x[0]===100&&x[1]>=64&&x[1]<=127);
}
function privatePeer(ip){
  const x=octets(ip);
  return Boolean(x&&(x[0]===10||(x[0]===192&&x[1]===168)||(x[0]===172&&x[1]>=16&&x[1]<=31)||(x[0]===127&&x[1]===0&&x[2]===0&&x[3]===1)));
}
const homeBind=process.env.ZAMER_BIND_IP||config.lanIp||'0.0.0.0';
if(homeBind!=='0.0.0.0'&&!privatePeer(homeBind))throw Error('Invalid LAN bind address');
function requestAllowed(req){
  const local=String(req.socket.localAddress||'').replace(/^::ffff:/,'');
  const remote=String(req.socket.remoteAddress||'').replace(/^::ffff:/,'');
  if(homeBind==='0.0.0.0')return privatePeer(remote)||(local===tailAddress&&tailscaleIP(remote));
  if(local===homeBind)return privatePeer(remote);
  if(tailscaleIP(local)&&remote===local)return true; // local connectivity self-test only
  return tailscaleIP(local)&&tailscaleIP(remote)&&local===tailAddress;
}
let tailAddress=null,tailServer=null;
function discoverTailAddress(){
  for(const [name,infos] of Object.entries(os.networkInterfaces())){
    if(!/tailscale/i.test(name))continue;
    for(const v of infos||[])if(v.family==='IPv4'&&tailscaleIP(v.address))return v.address;
  }
  return null;
}

const requestHandler=(req,res)=>{
  if(!requestAllowed(req))return send(res,403,{error:'trusted LAN or Tailscale only'});
  if(req.method==='GET'&&req.url==='/status')return send(res,200,{ok:true,service:'ZamerPlusReceiver',queue:fs.readdirSync(INBOX).filter(s=>s.endsWith('.zamer.json')).length});
  if(req.method!=='POST'||req.url!=='/upload')return send(res,404,{error:'not found'});
  if(!authorized(req))return send(res,401,{error:'pairing code invalid'});
  const max=512*1024;let size=0,chunks=[];
  req.on('data',c=>{size+=c.length;if(size>max){send(res,413,{error:'scan too large'});req.destroy();return;}chunks.push(c)});
  req.on('end',()=>{
    if(size>max)return;
    try{
      const p=JSON.parse(Buffer.concat(chunks).toString('utf8'));
      if(!checkPayload(p))return send(res,422,{error:'invalid Zamer+ scan'});
      const id=Date.now()+'_'+crypto.randomBytes(8).toString('hex');
      const tmp=path.join(INBOX,id+'.tmp'),final=path.join(INBOX,id+'.zamer.json');
      fs.writeFileSync(tmp,JSON.stringify(p),{flag:'wx'});fs.renameSync(tmp,final);
      send(res,202,{ok:true,accepted:true,id,status:'queued'});
      process.stdout.write('Получен скан: '+id+' ('+(p.format==='zamerplus-project'?'проект':'комната')+')\n');
    }catch(e){send(res,400,{error:'invalid JSON'})}
  });
};
const server=http.createServer(requestHandler);
server.listen(PORT,homeBind,()=>{
  console.log('\n=== Замер+ · приёмник Windows ===');
  console.log('Код сопряжения: '+config.token);
  for(const i of Object.values(os.networkInterfaces()))for(const x of i||[])if(x.family==='IPv4'&&!x.internal&&privatePeer(x.address))console.log('IP компьютера: '+x.address);
  console.log('Порт: '+PORT+' · папка сканов: '+INBOX);
  console.log('Приёмник работает на домашнем IP; удалённая передача через приватную сеть Tailscale.');
});
function syncTailListener(){
  const ip=discoverTailAddress();
  if(ip===tailAddress)return;
  if(tailServer){const old=tailServer;tailServer=null;tailAddress=null;old.close();}
  if(!ip||ip===homeBind)return;
  if(homeBind==='0.0.0.0'){tailAddress=ip;console.log('Tailscale IP enabled: '+ip);return;}
  const next=http.createServer(requestHandler);
  next.on('error',e=>{console.error('Не удалось привязать Tailscale: '+e.message);if(tailServer===next){tailServer=null;tailAddress=null;}});
  next.listen(PORT,ip,()=>console.log('Удалённый IP Tailscale для Замер+: '+ip));
  tailServer=next;tailAddress=ip;
}
syncTailListener();
setInterval(syncTailListener,10000).unref();

