package core

import (
	"bytes"
	"encoding/json"
)

func PrintJSON(v any) error {
	payload, err := encodeJSON(v)
	if err != nil {
		return err
	}

	return writeStdout(payload)
}

func encodeJSON(v any) ([]byte, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "  ")
	if err := enc.Encode(v); err != nil {
		return nil, err
	}

	return buf.Bytes(), nil
}
