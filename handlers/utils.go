package handlers

import (
	"regexp"
	"strings"
)

// isValidDID validates DID format (matching RubixGo validation)
func isValidDID(did string) bool {
	// Check if DID starts with "bafybmi" and has exactly 59 characters
	if !strings.HasPrefix(did, "bafybmi") || len(did) != 59 {
		return false
	}

	// Check if DID is alphanumeric
	isAlphanumeric := regexp.MustCompile(`^[a-zA-Z0-9]*$`).MatchString(did)
	return isAlphanumeric
}
