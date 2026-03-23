package core

import (
	"fmt"
	"os"
	"path/filepath"
	"time"
)

func GenerateSQLFile(sqlText, fileKind string) (string, error) {
	wd, err := os.Getwd()
	if err != nil {
		return "", WrapAppError(CodeInternalError, "failed to get current working directory", err)
	}
	return GenerateSQLFileAt(sqlText, fileKind, time.Now(), wd)
}

func GenerateSQLFileAt(sqlText, fileKind string, now time.Time, dir string) (string, error) {
	if fileKind == "" {
		return "", NewAppError(CodeInvalidArgument, "file kind cannot be empty")
	}
	fileName := fmt.Sprintf("%s_%s.sql", fileKind, now.Format("20060102_150405"))
	targetPath := filepath.Join(dir, fileName)

	if err := os.WriteFile(targetPath, []byte(sqlText+"\n"), 0o644); err != nil {
		return "", WrapAppError(CodeExecutionError, "failed to write SQL file", err)
	}
	return targetPath, nil
}
