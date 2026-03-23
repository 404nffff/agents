package core

type SuccessPayload struct {
	Driver   string                 `json:"driver"`
	Profile  string                 `json:"profile,omitempty"`
	Query    string                 `json:"query,omitempty"`
	RowCount int                    `json:"row_count"`
	Columns  []string               `json:"columns,omitempty"`
	Rows     []map[string]any       `json:"rows"`
	Meta     map[string]interface{} `json:"meta,omitempty"`
}

type ErrorPayload struct {
	Error ErrorDetail `json:"error"`
}

type ErrorDetail struct {
	Code    string `json:"code"`
	Message string `json:"message"`
	Driver  string `json:"driver,omitempty"`
}

type SQLFilePayload struct {
	Status   string `json:"status"`
	Action   string `json:"action"`
	FilePath string `json:"file_path"`
	Message  string `json:"message"`
	Query    string `json:"query"`
}

type SQLRules struct {
	AllowedStart      []string
	ForbiddenKeywords []string
	ForbiddenPhrases  []string
}

type SQLValidationResult struct {
	NormalizedSQL      string
	ShouldGenerateFile bool
	FileKind           string
	Action             string
}

type SQLConnConfig struct {
	Host           string
	Port           int
	User           string
	Password       string
	Database       string
	Socket         string
	TimeoutSeconds int
	SSLMode        string
}

type MongoConnConfig struct {
	URI                string
	Database           string
	TimeoutSeconds     int
	AllowedOperations  []string
	ForbiddenAggStages []string
}

type RedisConnConfig struct {
	Addr            string
	User            string
	Password        string
	DB              int
	TimeoutSeconds  int
	AllowedCommands []string
}
