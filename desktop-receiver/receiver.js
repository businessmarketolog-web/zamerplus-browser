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
function privatePeer(ip){
  ip=ip.replace(/^::ffff:/,'');const x=ip.split('.').map(Number);
  if(x.length!==4||x.some(v=>!Number.isInteger(v)||v<0||v>255))return false;
  return x[0]===10||(x[0]===192&&x[1]===168)||(x[0]===172&&x[1]>=16&&x[1]<=31)||ip==='127.0.0.1';
}
const server=http.createServer((req,res)=>{
  if(!privatePeer(req.socket.remoteAddress||''))return send(res,403,{error:'private LAN only'});
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
});
server.listen(PORT,'0.0.0.0',()=>{
  console.log('\n=== Замер+ · приёмник Windows ===');
  console.log('Код сопряжения: '+config.token);
  for(const i of Object.values(os.networkInterfaces()))for(const x of i||[])if(x.family==='IPv4'&&!x.internal&&privatePeer(x.address))console.log('IP компьютера: '+x.address);
  console.log('Порт: '+PORT+' · папка сканов: '+INBOX);
  console.log('Разрешите доступ Node.js только для ЧАСТНЫХ сетей Windows. Закройте окно, чтобы остановить приёмник.\n');
});
