//go:build !windows

package core

import "os"

func writeStdout(data []byte) error {
	_, err := os.Stdout.Write(data)
	return err
}
