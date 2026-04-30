package core

import "fmt"

const (
	CodeInvalidArgument = "INVALID_ARGUMENT"
	CodeInvalidQuery    = "INVALID_QUERY"
	CodeInvalidConfig   = "INVALID_CONFIG"
	CodeConnectionError = "CONNECTION_ERROR"
	CodeExecutionError  = "EXECUTION_ERROR"
	CodeInternalError   = "INTERNAL_ERROR"
)

type AppError struct {
	Code    string
	Message string
	Err     error
}

func (e *AppError) Error() string {
	if e == nil {
		return ""
	}
	if e.Err == nil {
		return fmt.Sprintf("%s: %s", e.Code, e.Message)
	}
	return fmt.Sprintf("%s: %s: %v", e.Code, e.Message, e.Err)
}

func (e *AppError) Unwrap() error {
	if e == nil {
		return nil
	}
	return e.Err
}

func NewAppError(code, message string) *AppError {
	return &AppError{Code: code, Message: message}
}

func WrapAppError(code, message string, err error) *AppError {
	return &AppError{Code: code, Message: message, Err: err}
}
