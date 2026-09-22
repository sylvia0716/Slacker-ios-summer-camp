import http from 'node:http';
import {resolveLanguage} from '../public/language.js';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root = path.resolve(fileURLToPath(new URL('../public/', import.meta.url)));
const types = {'.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8'};
http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://127.0.0.1:3210');
    let body;
    let contentType;
    if (url.pathname === '/email-preview') {
      const language = resolveLanguage(url.searchParams.get('lang'), 'zh-Hant');
      const template = await readFile(new URL(language === 'en' ? '../email/password-reset.en.html' : '../email/password-reset.html', import.meta.url), 'utf8');
      body = '<!doctype html><html lang="' + language + '"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Oops Bomb · 信件預覽</title><body style="margin:0">' + template.replaceAll('%EMAIL%', 'demo@example.com').replaceAll('%LINK%', 'http://127.0.0.1:3210/?preview=ready&lang=' + language) + '</body></html>';
      contentType = types['.html'];
    } else {
      const file = path.resolve(root, '.' + decodeURIComponent(url.pathname === '/' ? '/index.html' : url.pathname));
      if (!file.startsWith(root + path.sep)) throw new Error('Not found');
      body = await readFile(file);
      contentType = types[path.extname(file)] ?? 'application/octet-stream';
    }
    res.writeHead(200, {'Content-Type': contentType, 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer'});
    res.end(body);
  } catch {res.writeHead(404); res.end('Not found');}
}).listen(3210, '127.0.0.1', () => console.log('Auth page preview: http://127.0.0.1:3210/?preview=ready\nEmail preview: http://127.0.0.1:3210/email-preview'));
