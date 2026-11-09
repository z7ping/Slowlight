package caldav

import (
	"encoding/json"
	"strings"
	"testing"

	"slowlight/internal/secureconfig"
)

func TestResolveCalDAVPasswordReuseIsScopedToSameServerAndUser(t *testing.T) {
	t.Setenv("CONFIG_ENCRYPTION_KEY", strings.Repeat("k", 32))
	encrypted, err := secureconfig.Encrypt("stored-secret")
	if err != nil { t.Fatal(err) }
	old, err := json.Marshal(map[string]string{
		"base_url": "https://tasks.example.org",
		"username": "alice",
		"password": encrypted,
	})
	if err != nil { t.Fatal(err) }

	req := ConfigRequest{BaseURL: "https://tasks.example.org", Username: "alice"}
	if err := resolveCalDAVPassword(&req, string(old)); err != nil {
		t.Fatalf("same endpoint should reuse stored credentials: %v", err)
	}
	if req.Password != "stored-secret" { t.Fatal("stored password was not decrypted for request") }

	for _, tc := range []struct{name, url, username string}{
		{"changed server", "https://other.example.org", "alice"},
		{"changed user", "https://tasks.example.org", "bob"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			changed := ConfigRequest{BaseURL: tc.url, Username: tc.username}
			if err := resolveCalDAVPassword(&changed, string(old)); err == nil {
				t.Fatal("must not reuse credentials when identity changes")
			}
		})
	}

	fresh := ConfigRequest{BaseURL: "https://tasks.example.org", Username: "alice"}
	if err := resolveCalDAVPassword(&fresh, ""); err == nil {
		t.Fatal("first-time config must have a password")
	}
	explicit := ConfigRequest{BaseURL: "https://changed.example.org", Username: "bob", Password: "new-secret"}
	if err := resolveCalDAVPassword(&explicit, string(old)); err != nil {
		t.Fatalf("explicitly provided credential must be allowed: %v", err)
	}
	if explicit.Password != "new-secret" { t.Fatal("explicit password modified") }
}

func TestResolveCalDAVPasswordRejectsCorruptOrUndecryptableStoredSecret(t *testing.T) {
	t.Setenv("CONFIG_ENCRYPTION_KEY", strings.Repeat("k", 32))
	for _, stored := range []string{
		"not-json",
		`{"base_url":"https://tasks.example.org","username":"alice","password":""}`,
		`{"base_url":"https://tasks.example.org","username":"alice","password":"enc:v1:broken"}`,
	} {
		req := ConfigRequest{BaseURL: "https://tasks.example.org", Username: "alice"}
		if err := resolveCalDAVPassword(&req, stored); err == nil {
			t.Fatalf("expected error for invalid stored config %q", stored)
		}
	}
}
