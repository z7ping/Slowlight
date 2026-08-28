package secureconfig

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"os"
	"strings"
)

const encryptedPrefix = "enc:v1:"

// Encrypt 加密需要持久化的集成凭据。密钥仅从服务端环境读取。
func Encrypt(plaintext string) (string, error) {
	key, err := encryptionKey()
	if err != nil {
		return "", err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", fmt.Errorf("创建凭据加密器失败: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("创建凭据加密模式失败: %w", err)
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return "", fmt.Errorf("生成凭据随机数失败: %w", err)
	}
	ciphertext := gcm.Seal(nonce, nonce, []byte(plaintext), nil)
	return encryptedPrefix + base64.RawStdEncoding.EncodeToString(ciphertext), nil
}

// Decrypt 解密已加密凭据；历史明文配置保持可读，便于渐进迁移。
func Decrypt(value string) (string, error) {
	if !strings.HasPrefix(value, encryptedPrefix) {
		return value, nil
	}
	key, err := encryptionKey()
	if err != nil {
		return "", err
	}
	data, err := base64.RawStdEncoding.DecodeString(strings.TrimPrefix(value, encryptedPrefix))
	if err != nil {
		return "", errors.New("凭据密文格式无效")
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", fmt.Errorf("创建凭据解密器失败: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("创建凭据解密模式失败: %w", err)
	}
	if len(data) < gcm.NonceSize() {
		return "", errors.New("凭据密文长度无效")
	}
	plaintext, err := gcm.Open(nil, data[:gcm.NonceSize()], data[gcm.NonceSize():], nil)
	if err != nil {
		return "", errors.New("凭据解密失败，请检查 CONFIG_ENCRYPTION_KEY")
	}
	return string(plaintext), nil
}

func encryptionKey() ([]byte, error) {
	secret := os.Getenv("CONFIG_ENCRYPTION_KEY")
	if len(secret) < 32 {
		return nil, errors.New("CONFIG_ENCRYPTION_KEY 未配置或长度不足 32 个字符")
	}
	sum := sha256.Sum256([]byte(secret))
	return sum[:], nil
}
