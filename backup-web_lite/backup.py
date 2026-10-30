#!/usr/bin/env python3
import os, tarfile, cgi, json, html, shutil, urllib.parse, traceback, threading, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from datetime import datetime

PORT = 5000
ROOT = "/host"
DEFAULT_BACKUP_DIR = "/host/opt/backups"

tasks = {}
tasks_lock = threading.Lock()

HTML = """<!DOCTYPE html><html><head><meta charset="utf-8"><title>Backup</title>
<style>
body{font-family:sans-serif;max-width:900px;margin:40px auto;padding:20px}
table{width:100%;border-collapse:collapse;margin:20px 0}
td,th{padding:8px;border:1px solid #ddd;text-align:left}
button{padding:6px 12px;cursor:pointer;margin:2px}
.section{margin:30px 0;padding:15px;border:1px solid #ccc}
input[type=text]{width:420px;padding:6px}
.modal{display:none;position:fixed;z-index:1;left:0;top:0;width:100%;height:100%;background:rgba(0,0,0,.5)}
.modal-content{background:#fff;margin:8% auto;padding:20px;width:620px;max-height:65vh;overflow-y:auto}
.folder-item{padding:8px;cursor:pointer;border-bottom:1px solid #eee}
.folder-item:hover{background:#f0f0f0}
#msg{padding:10px;background:#ffe9e9;border:1px solid #f5c2c2;white-space:pre-wrap;display:{MSGSHOW}}
#progress-box{display:none;padding:15px;background:#e8f4ff;border:1px solid #b3d4fc;margin:15px 0;font-family:monospace}
#progress-box .bar{height:20px;background:#ddd;border-radius:3px;overflow:hidden;margin:8px 0}
#progress-box .bar-fill{height:100%;background:#4a90e2;transition:width .3s}
#log-box{background:#1e1e1e;color:#d4d4d4;padding:10px;max-height:200px;overflow-y:auto;font-size:12px;margin-top:10px}
</style></head><body>
<h1>🗄️ Backup</h1>
<div id="msg">{MSG}</div>

<div id="progress-box">
  <div><b>Статус:</b> <span id="p-status">запуск...</span></div>
  <div><b>Источник:</b> <span id="p-source"></span></div>
  <div><b>Назначение:</b> <span id="p-dest"></span></div>
  <div><b>Файлов:</b> <span id="p-files">0</span></div>
  <div><b>Размер архива:</b> <span id="p-size">0 MB</span></div>
  <div><b>Время:</b> <span id="p-time">0 сек</span></div>
  <div class="bar"><div class="bar-fill" id="p-bar" style="width:0%"></div></div>
  <div id="log-box"></div>
</div>

<div class="section">
<h2>Создать бэкап</h2>
<form id="backup-form" onsubmit="return startBackup(event)">
<p>Откуда: <input type="text" id="source" name="source" value="{SRC}" readonly>
<button type="button" onclick="openModal('source')">Обзор...</button></p>
<p>Куда: <input type="text" id="dest" name="dest" value="{DST}" readonly onchange="loadBackups(this.value)">
<button type="button" onclick="openModal('dest')">Обзор...</button></p>
<button type="submit" id="submit-btn">Упаковать</button>
</form>
</div>

<div class="section">
<h2>Бэкапы <small>(<span id="list-dir-name">{LISTDIR}</span>)</small></h2>
<table>
<tr><th>Имя</th><th>Размер</th><th>Дата</th><th>Действия</th></tr>
<tbody id="backups-tbody"><tr><td colspan="4">Загрузка...</td></tr></tbody>
</table>
</div>

<div class="section">
<h2>Загрузить</h2>
<form method="post" action="/upload" enctype="multipart/form-data">
<input type="file" name="file" accept=".tar.gz" required>
<button type="submit">Загрузить</button>
</form>
</div>

<div id="modal" class="modal"><div class="modal-content">
<h3>Выберите папку</h3><p>Путь: <span id="current-path"></span></p>
<div id="folder-list"></div>
<button onclick="selectFolder()">Выбрать эту папку</button>
<button onclick="closeModal()">Отмена</button>
</div></div>

<script>
let currentTarget='', currentPath=ROOTJS;
let currentDest = '{DST}';

async function startBackup(e){
 e.preventDefault();
 const src=document.getElementById('source').value;
 const dst=document.getElementById('dest').value;
 if(!src||!dst){alert('Выберите папки');return false;}

 document.getElementById('submit-btn').disabled=true;
 document.getElementById('progress-box').style.display='block';
 document.getElementById('p-source').textContent=src;
 document.getElementById('p-dest').textContent=dst;
 document.getElementById('p-status').textContent='запуск...';
 document.getElementById('log-box').innerHTML='';

 const t0=Date.now();
 try{
  const r=await fetch('/api/backup',{method:'POST',headers:{'Content-Type':'application/json'},
   body:JSON.stringify({source:src,dest:dst})});
  const d=await r.json();
  if(!d.ok){alert('Ошибка: '+d.error);document.getElementById('submit-btn').disabled=false;return false;}
  pollStatus(d.task_id,t0);
 }catch(err){
  alert('Ошибка сети: '+err);
  document.getElementById('submit-btn').disabled=false;
 }
 return false;
}

async function pollStatus(taskId,t0){
 const r=await fetch('/api/status/'+taskId);
 const d=await r.json();
 const elapsed=((Date.now()-t0)/1000).toFixed(1);
 document.getElementById('p-time').textContent=elapsed+' сек';
 document.getElementById('p-status').textContent=d.status;
 document.getElementById('p-files').textContent=d.files_done+(d.files_total?' / '+d.files_total:'');
 document.getElementById('p-size').textContent=(d.size/1048576).toFixed(2)+' MB';
 if(d.files_total>0){
  const pct=Math.min(100,(d.files_done/d.files_total*100)).toFixed(1);
  document.getElementById('p-bar').style.width=pct+'%';
 }
 const log=document.getElementById('log-box');
 log.innerHTML=d.log.map(l=>'<div>'+l+'</div>').join('');
 log.scrollTop=log.scrollHeight;

 if(d.status==='done'){
  document.getElementById('p-bar').style.width='100%';
  document.getElementById('p-status').textContent='✅ Готово!';
  setTimeout(()=>{ location.reload(); }, 1500);
 }else if(d.status==='error'){
  document.getElementById('p-status').textContent='❌ Ошибка: '+d.error;
  document.getElementById('submit-btn').disabled=false;
 }else{
  setTimeout(()=>pollStatus(taskId,t0),1000);
 }
}

async function loadBackups(dir) {
 currentDest = dir;
 document.getElementById('list-dir-name').textContent = dir;
 const tbody = document.getElementById('backups-tbody');
 tbody.innerHTML = '<tr><td colspan="4">Загрузка...</td></tr>';
 try {
  const r = await fetch('/api/list?path=' + encodeURIComponent(dir));
  const d = await r.json();
  tbody.innerHTML = '';
  if (!d.files || !d.files.length) {
   tbody.innerHTML = '<tr><td colspan="4">Пусто</td></tr>';
   return;
  }
  d.files.forEach(f => {
   const tr = document.createElement('tr');
   tr.innerHTML = `
    <td>${f.name}</td>
    <td>${f.size}</td>
    <td>${f.date}</td>
    <td>
     <a href="/download/${encodeURIComponent(f.name)}?dir=${encodeURIComponent(f.dir)}"><button>Скачать</button></a>
     <form method="post" action="/delete/${encodeURIComponent(f.name)}?dir=${encodeURIComponent(f.dir)}" style="display:inline">
      <button>Удалить</button>
     </form>
    </td>`;
   tbody.appendChild(tr);
  });
 } catch(e) {
  tbody.innerHTML = '<tr><td colspan="4">Ошибка чтения папки</td></tr>';
 }
}

function openModal(t){currentTarget=t;currentPath=ROOTJS;
 document.getElementById('modal').style.display='block';loadFolders();}
function closeModal(){document.getElementById('modal').style.display='none';}
async function loadFolders(){
 const r=await fetch('/api/folders?path='+encodeURIComponent(currentPath));
 const d=await r.json();
 document.getElementById('current-path').textContent=currentPath;
 const list=document.getElementById('folder-list');list.innerHTML='';
 if(currentPath!==ROOTJS){
  const up=document.createElement('div');up.className='folder-item';up.textContent='📁 .. (назад)';
  up.onclick=()=>{let p=currentPath.split('/').filter(Boolean);p.pop();
   currentPath='/'+p.join('/');if(!currentPath.startsWith(ROOTJS))currentPath=ROOTJS;loadFolders();};
  list.appendChild(up);}
 if(!d.folders.length){const e=document.createElement('div');e.className='folder-item';
  e.textContent='(в этой папке нет подпапок, но её можно выбрать)';list.appendChild(e);}
 d.folders.forEach(f=>{const v=document.createElement('div');v.className='folder-item';
  v.textContent='📁 '+f;v.onclick=()=>{currentPath=currentPath.replace(/\/$/,'')+'/'+f;loadFolders();};
  list.appendChild(v);});
}
function selectFolder(){
 document.getElementById(currentTarget).value=currentPath;
 closeModal();
 if(currentTarget === 'dest') { loadBackups(currentPath); }
}

// Загружаем список при старте
window.onload = () => loadBackups(currentDest);
</script></body></html>"""

def run_backup_task(task_id, src, dst):
    with tasks_lock:
        tasks[task_id]['status'] = 'running'
        tasks[task_id]['log'].append(f'[{now()}] Начинаю упаковку {src}')
    try:
        tasks[task_id]['log'].append(f'[{now()}] Считаю файлы...')
        all_files = []
        for root, dirs, files in os.walk(src):
            for f in files:
                full = os.path.join(root, f)
                try:
                    if not os.path.islink(full): all_files.append(full)
                except: pass
        with tasks_lock:
            tasks[task_id]['files_total'] = len(all_files)
            tasks[task_id]['log'].append(f'[{now()}] Найдено файлов: {len(all_files)}')

        base = os.path.basename(src.rstrip('/')) or 'root'
        name = f"{base}_{datetime.now().strftime('%Y-%m-%d_%H-%M-%S')}.tar.gz"
        archive = os.path.join(dst, name)
        dst_real = os.path.realpath(dst)

        with tasks_lock: tasks[task_id]['log'].append(f'[{now()}] Создаю {name}')

        files_done = 0
        with tarfile.open(archive, 'w:gz') as tar:
            for fpath in all_files:
                try:
                    f_real = os.path.realpath(fpath)
                    if f_real == dst_real or f_real.startswith(dst_real + os.sep): continue
                    arcname = os.path.join(base, os.path.relpath(fpath, src))
                    tar.add(fpath, arcname=arcname, recursive=False)
                    files_done += 1
                    with tasks_lock:
                        tasks[task_id]['files_done'] = files_done
                        tasks[task_id]['size'] = os.path.getsize(archive)
                        if files_done % 50 == 0:
                            tasks[task_id]['log'].append(f'[{now()}] {files_done}/{tasks[task_id]["files_total"]} файлов, {tasks[task_id]["size"]/1048576:.1f} MB')
                except Exception as e:
                    with tasks_lock: tasks[task_id]['log'].append(f'[{now()}] ⚠ Пропущен: {fpath}: {e}')

        final_size = os.path.getsize(archive)
        with tasks_lock:
            tasks[task_id]['status'] = 'done'
            tasks[task_id]['size'] = final_size
            tasks[task_id]['files_done'] = files_done
            tasks[task_id]['log'].append(f'[{now()}] ✅ Готово! {name} ({final_size/1048576:.1f} MB, {files_done} файлов)')
    except Exception as e:
        with tasks_lock:
            tasks[task_id]['status'] = 'error'
            tasks[task_id]['error'] = str(e)
            tasks[task_id]['log'].append(f'[{now()}] ❌ Ошибка: {e}')

def now(): return datetime.now().strftime('%H:%M:%S')

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def reply(self, code, body=b"", ctype="text/html; charset=utf-8", extra=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items(): self.send_header(k, v)
        self.end_headers()
        if body: self.wfile.write(body)

    def page(self, msg="", src="", dst=DEFAULT_BACKUP_DIR):
        out = (HTML.replace("{MSG}", html.escape(msg))
                   .replace("{MSGSHOW}", "block" if msg else "none")
                   .replace("{SRC}", html.escape(src))
                   .replace("{DST}", html.escape(dst))
                   .replace("{LISTDIR}", html.escape(dst))
                   .replace("ROOTJS", json.dumps(ROOT)))
        self.reply(200, out.encode())

    def do_GET(self):
        u = urllib.parse.urlsplit(self.path)
        path = urllib.parse.unquote(u.path)
        q = urllib.parse.parse_qs(u.query)
        try:
            if path == "/": return self.page()

            if path == "/api/folders":
                p = q.get("path", [ROOT])[0]
                if not p.startswith(ROOT): p = ROOT
                folders = []
                try: folders = sorted(e for e in os.listdir(p) if os.path.isdir(os.path.join(p, e)))
                except OSError: pass
                return self.reply(200, json.dumps({"folders": folders}).encode(), "application/json")

            if path == "/api/list":
                p = q.get("path", [DEFAULT_BACKUP_DIR])[0]
                if not p.startswith(ROOT): p = ROOT
                files = []
                try:
                    for f in sorted(os.listdir(p), reverse=True):
                        if f.endswith(".tar.gz"):
                            s = os.stat(os.path.join(p, f))
                            files.append({
                                "name": f, "size": f"{s.st_size/1048576:.1f} MB",
                                "date": datetime.fromtimestamp(s.st_mtime).strftime("%Y-%m-%d %H:%M"), "dir": p
                            })
                except Exception: pass
                return self.reply(200, json.dumps({"files": files, "dir": p}).encode(), "application/json")

            if path.startswith("/api/status/"):
                task_id = path[len("/api/status/"):]
                with tasks_lock: t = tasks.get(task_id)
                if not t: return self.reply(404, b'{"error":"not found"}', "application/json")
                return self.reply(200, json.dumps({
                    "status": t["status"], "files_done": t["files_done"], "files_total": t["files_total"],
                    "size": t["size"], "log": t["log"][-20:], "error": t.get("error", "")
                }).encode(), "application/json")

            if path.startswith("/download/"):
                name = os.path.basename(path[len("/download/"):])
                dir_path = q.get("dir", [DEFAULT_BACKUP_DIR])[0]
                p = os.path.join(dir_path, name)
                if not os.path.isfile(p): return self.reply(404, b"not found", "text/plain")
                self.send_response(200)
                self.send_header("Content-Type", "application/gzip")
                self.send_header("Content-Length", str(os.path.getsize(p)))
                self.send_header("Content-Disposition", 'attachment; filename="%s"' % name)
                self.end_headers()
                with open(p, "rb") as f: shutil.copyfileobj(f, self.wfile, 1024 * 256)
                return

            self.reply(404, b"not found", "text/plain")
        except (BrokenPipeError, ConnectionResetError): pass
        except Exception: self.reply(500, ("<pre>" + html.escape(traceback.format_exc()) + "</pre>").encode())

    def do_POST(self):
        path = urllib.parse.unquote(urllib.parse.urlsplit(self.path).path)
        u = urllib.parse.urlsplit(self.path)
        q = urllib.parse.parse_qs(u.query)
        try:
            if path == "/api/backup":
                n = int(self.headers.get("Content-Length", 0))
                body = json.loads(self.rfile.read(n).decode())
                src, dst = body.get("source", ""), body.get("dest", "")
                if not src.startswith(ROOT) or not os.path.isdir(src):
                    return self.reply(400, json.dumps({"ok": False, "error": "Неверная папка-источник"}).encode(), "application/json")
                if not dst.startswith(ROOT):
                    return self.reply(400, json.dumps({"ok": False, "error": "Папка назначения должна быть внутри " + ROOT}).encode(), "application/json")
                os.makedirs(dst, exist_ok=True)
                task_id = str(int(time.time() * 1000))
                with tasks_lock:
                    tasks[task_id] = {"status": "starting", "files_done": 0, "files_total": 0, "size": 0, "log": [], "error": ""}
                threading.Thread(target=run_backup_task, args=(task_id, src, dst), daemon=True).start()
                return self.reply(200, json.dumps({"ok": True, "task_id": task_id}).encode(), "application/json")

            if path.startswith("/delete/"):
                name = os.path.basename(path[len("/delete/"):])
                dir_path = q.get("dir", [DEFAULT_BACKUP_DIR])[0]
                p = os.path.join(dir_path, name)
                if os.path.isfile(p) and name.endswith(".tar.gz"): os.remove(p)
                self.reply(303, b"", extra={"Location": "/"})
                return

            if path == "/upload":
                form = cgi.FieldStorage(fp=self.rfile, headers=self.headers, environ={"REQUEST_METHOD": "POST", "CONTENT_TYPE": self.headers.get("Content-Type", "")})
                item = form["file"]
                name = os.path.basename(item.filename)
                if name.endswith(".tar.gz"):
                    with open(os.path.join(DEFAULT_BACKUP_DIR, name), "wb") as f: shutil.copyfileobj(item.file, f, 1024 * 256)
                self.reply(303, b"", extra={"Location": "/"})
                return

            self.reply(404, b"not found", "text/plain")
        except (BrokenPipeError, ConnectionResetError): pass
        except Exception: self.reply(500, ("<pre>" + html.escape(traceback.format_exc()) + "</pre>").encode())

if __name__ == "__main__":
    os.makedirs(DEFAULT_BACKUP_DIR, exist_ok=True)
    print("http://0.0.0.0:%d" % PORT, flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
