package handler

import "testing"

func TestValidateWebhookURLRejectsPrivateTargets(t *testing.T) {
	for _, target := range []string{
		"http://127.0.0.1:8080/hook",
		"http://localhost:8080/hook",
		"http://10.0.0.8/hook",
		"http://169.254.169.254/latest/meta-data",
		"http://[::1]/hook",
		"file:///tmp/hook",
		"https://user:secret@example.com/hook",
	} {
		t.Run(target, func(t *testing.T) {
			if err := validateWebhookURL(target); err == nil {
				t.Fatalf("应拒绝 Webhook URL: %s", target)
			}
		})
	}
}

func TestValidateWebhookURLAllowsPublicHTTPTargets(t *testing.T) {
	for _, target := range []string{
		"https://example.com/hook",
		"http://8.8.8.8/hook",
	} {
		t.Run(target, func(t *testing.T) {
			if err := validateWebhookURL(target); err != nil {
				t.Fatalf("不应拒绝公开 Webhook URL %s: %v", target, err)
			}
		})
	}
}
