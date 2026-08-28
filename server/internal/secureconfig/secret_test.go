package secureconfig

import (
	"strings"
	"testing"
)

func TestEncryptDecrypt(t *testing.T) {
	t.Setenv("CONFIG_ENCRYPTION_KEY", strings.Repeat("k", 32))
	encrypted, err := Encrypt("sensitive-value")
	if err != nil {
		t.Fatal(err)
	}
	if encrypted == "sensitive-value" || !strings.HasPrefix(encrypted, encryptedPrefix) {
		t.Fatalf("未生成预期密文: %q", encrypted)
	}
	decrypted, err := Decrypt(encrypted)
	if err != nil || decrypted != "sensitive-value" {
		t.Fatalf("解密结果错误: value=%q err=%v", decrypted, err)
	}
}

func TestDecryptLegacyPlaintext(t *testing.T) {
	decrypted, err := Decrypt("legacy-secret")
	if err != nil || decrypted != "legacy-secret" {
		t.Fatalf("历史明文兼容失败: value=%q err=%v", decrypted, err)
	}
}

func TestEncryptRequiresKey(t *testing.T) {
	t.Setenv("CONFIG_ENCRYPTION_KEY", "")
	if _, err := Encrypt("secret"); err == nil {
		t.Fatal("缺少密钥时应拒绝持久化凭据")
	}
}
