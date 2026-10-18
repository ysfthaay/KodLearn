const express = require('express');
const cors = require('cors');
const http = require('http');
const WebSocket = require('ws');
const { spawn, exec } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
// Pin .env to backend/.env regardless of process.cwd() so the API key loads
// even if the server is started from a parent directory.
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

// Tiny startup signal so it's obvious in the terminal which AI is wired up
// and whether the key actually got read. Doesn't print the key.
const _hasGemini = !!(
  process.env.Gemini_API_Key ||
  process.env.GEMINI_API_KEY
);
console.log(`🤖 AI provider: Gemini  |  key loaded: ${_hasGemini ? 'yes' : 'NO (check .env)'}`);

const codeRoutes = require('./routes/code');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

app.get('/', (req, res) => {
  res.json({ message: 'KodLearn API çalışıyor 🚀' });
});

app.use('/api/code', codeRoutes);

// HTTP server oluştur
const server = http.createServer(app);

// WebSocket server
const wss = new WebSocket.Server({ server });

wss.on('connection', (ws) => {
  let childProcess = null;
  let srcFile = null;
  let outFile = null;

  ws.on('message', async (message) => {
    const data = JSON.parse(message);

    if (data.type === 'run') {
      // Önceki process varsa kapat
      if (childProcess) {
        childProcess.kill();
        childProcess = null;
      }

      const tmpDir = os.tmpdir();
      const fileName = `kodlearn_${Date.now()}`;
      srcFile = path.join(tmpDir, `${fileName}.c`);
      outFile = path.join(tmpDir, fileName);

      // --- KODLEARN HİLESİ BAŞLANGICI ---
      // Kullanıcının koduna gizlice buffer sıfırlama kodunu enjekte ediyoruz
      // Böylece printf("Lütfen sayı giriniz: ") anında terminale düşecek.
      //
      // NOTE: the shim is appended to the SAME line as `int main() {` (no
      // surrounding newlines) so the compiler's line numbers stay in lock-
      // step with what the user sees in the editor. Previously this added
      // two lines, shifting every error report by +2.
      const modifiedCode = data.code.replace(
        /(int\s+main\s*\([^)]*\)\s*\{)/,
        '$1 setvbuf(stdout, NULL, _IONBF, 0);'
      );
      // --- KODLEARN HİLESİ BİTİŞİ ---

      // Modifiye edilmiş kodu dosyaya yaz
      fs.writeFileSync(srcFile, modifiedCode);

      // Önce derle
      exec(`gcc ${srcFile} -o ${outFile} 2>&1`, (compileErr, compileOut) => {
        if (compileErr) {
          ws.send(JSON.stringify({ type: 'error', data: compileOut }));
          ws.send(JSON.stringify({ type: 'done' }));
          try { fs.unlinkSync(srcFile); } catch (_) {}
          return;
        }

        // Çalıştır (Spawn ile)
        childProcess = spawn(outFile, [], {
          stdio: ['pipe', 'pipe', 'pipe'],
        });

        ws.send(JSON.stringify({ type: 'started' }));

        childProcess.stdout.on('data', (chunk) => {
          ws.send(JSON.stringify({ type: 'output', data: chunk.toString() }));
        });

        childProcess.stderr.on('data', (chunk) => {
          ws.send(JSON.stringify({ type: 'error', data: chunk.toString() }));
        });

        childProcess.on('close', (code) => {
          ws.send(JSON.stringify({ type: 'done', exitCode: code }));
          try { fs.unlinkSync(srcFile); } catch (_) {}
          try { fs.unlinkSync(outFile); } catch (_) {}
          childProcess = null;
        });

        // Timeout 10 saniye
        setTimeout(() => {
          if (childProcess) {
            childProcess.kill();
            ws.send(JSON.stringify({ type: 'error', data: 'Zaman aşımı (10s)' }));
            ws.send(JSON.stringify({ type: 'done' }));
          }
        }, 10000);
      });

    } else if (data.type === 'input') {
      // Kullanıcı girişini process'e gönder
      if (childProcess && childProcess.stdin.writable) {
        // Flutter tarafından `data.data` zaten '\n' eklenerek gönderiliyorsa (önceki kodunda öyleydi)
        // Burada tekrar '\n' eklememize gerek yok. Ya da işi sağlama alalım:
        const inputStr = data.data.endsWith('\n') ? data.data : data.data + '\n';
        childProcess.stdin.write(inputStr);
      }
    } else if (data.type === 'kill') {
      if (childProcess) {
        childProcess.kill();
        childProcess = null;
      }
    }
  });

  ws.on('close', () => {
    if (childProcess) {
      childProcess.kill();
      childProcess = null;
    }
    try { if (srcFile) fs.unlinkSync(srcFile); } catch (_) {}
    try { if (outFile) fs.unlinkSync(outFile); } catch (_) {}
  });
});

server.listen(PORT, () => {
  console.log(`Server ${PORT} portunda çalışıyor...`);
});