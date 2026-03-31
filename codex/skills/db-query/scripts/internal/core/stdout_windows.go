//go:build windows

package core

import (
	"errors"
	"os"
	"syscall"
	"unsafe"
)

var (
	kernel32DLL         = syscall.NewLazyDLL("kernel32.dll")
	procGetConsoleMode  = kernel32DLL.NewProc("GetConsoleMode")
	procWriteConsoleW   = kernel32DLL.NewProc("WriteConsoleW")
	writeConsoleChunkSz = 4096
)

func writeStdout(data []byte) error {
	if len(data) == 0 {
		return nil
	}

	handle := syscall.Handle(os.Stdout.Fd())
	// 非控制台句柄（如重定向到文件/管道）保持 UTF-8 原样输出。
	if !isConsoleHandle(handle) {
		_, err := os.Stdout.Write(data)
		return err
	}

	// 控制台句柄使用 WriteConsoleW，避免受代码页影响导致中文乱码。
	return writeConsoleUTF16(handle, string(data))
}

func isConsoleHandle(handle syscall.Handle) bool {
	var mode uint32
	ret, _, _ := procGetConsoleMode.Call(uintptr(handle), uintptr(unsafe.Pointer(&mode)))
	return ret != 0
}

func writeConsoleUTF16(handle syscall.Handle, text string) error {
	if text == "" {
		return nil
	}

	runes := []rune(text)
	for start := 0; start < len(runes); start += writeConsoleChunkSz {
		end := start + writeConsoleChunkSz
		if end > len(runes) {
			end = len(runes)
		}

		segment := string(runes[start:end])
		utf16, err := syscall.UTF16FromString(segment)
		if err != nil {
			return err
		}
		if len(utf16) == 0 {
			continue
		}

		var written uint32
		ret, _, callErr := procWriteConsoleW.Call(
			uintptr(handle),
			uintptr(unsafe.Pointer(&utf16[0])),
			uintptr(len(utf16)-1),
			uintptr(unsafe.Pointer(&written)),
			0,
		)
		if ret == 0 {
			if callErr != syscall.Errno(0) {
				return callErr
			}
			return errors.New("WriteConsoleW failed")
		}
	}

	return nil
}
