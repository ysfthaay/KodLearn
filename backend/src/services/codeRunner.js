const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const runCode = async (code, stdin = '') => {
  return new Promise((resolve) => {
    
    // --- KODLEARN HİLESİ: Çıktı tamponlamayı (Output Buffering) kapat ---
    // Kullanıcının yazdığı 'int main() {' kısmını bulup, hemen altına buffer kapatma kodunu ekler.
    const modifiedCode = code.replace(
      /(int\s+main\s*\([^)]*\)\s*\{)/,
      '$1\n    setvbuf(stdout, NULL, _IONBF, 0);\n'
    );

    const tmpDir = os.tmpdir();
    const fileName = `kodlearn_${Date.now()}`;
    const srcFile = path.join(tmpDir, `${fileName}.c`);
    const outFile = path.join(tmpDir, fileName);
    const stdinFile = path.join(tmpDir, `${fileName}.txt`);

    // Orjinal 'code' yerine, arasına sızdığımız 'modifiedCode'u dosyaya yazıyoruz
    fs.writeFileSync(srcFile, modifiedCode);
    fs.writeFileSync(stdinFile, stdin);

    exec(`gcc ${srcFile} -o ${outFile} 2>&1`, (compileErr, compileOut) => {
      if (compileErr) {
        try { fs.unlinkSync(srcFile); } catch (_) {}
        try { fs.unlinkSync(stdinFile); } catch (_) {}
        return resolve({
          status: 'COMPILE_ERROR',
          output: null,
          error: compileOut,
        });
      }

      exec(`${outFile} < ${stdinFile}`, { timeout: 10000 }, (runErr, stdout, stderr) => {
        try { fs.unlinkSync(srcFile); } catch (_) {}
        try { fs.unlinkSync(outFile); } catch (_) {}
        try { fs.unlinkSync(stdinFile); } catch (_) {}

        if (runErr && runErr.killed) {
          return resolve({ status: 'RUNTIME_ERROR', output: null, error: 'Zaman aşımı (10s)' });
        }

        if (runErr && !stdout) {
          return resolve({ status: 'RUNTIME_ERROR', output: null, error: stderr || runErr.message });
        }

        resolve({ status: 'SUCCESS', output: stdout, error: stderr || null });
      });
    });
  });
};

module.exports = { runCode };