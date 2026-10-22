package handler

import (
	"errors"
	"net/http"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"slowlight/internal/model"
)

// 仅在 GitHub 首次自动注册时创建的 github_<subject>（可带冲突后缀）
// 没有可供用户使用的密码。旧记录没有 PasswordLoginEnabled 时按绑定身份识别。
func passwordLoginEnabledChecked(db *gorm.DB, user model.User) (bool, error) {
	if user.PasswordLoginEnabled != nil {
		return *user.PasswordLoginEnabled, nil
	}
	var identity model.OAuthIdentity
	err := db.Where("provider = ? AND user_id = ?", "github", user.ID).First(&identity).Error
	if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		return false, err
	}
	if err == nil {
		generated := "github_" + identity.ProviderUserID
		if user.Username == generated || strings.HasPrefix(user.Username, generated+"_") {
			return false, nil
		}
	}
	// 旧普通账号即使绑定了 GitHub 仍保留原来的密码登录能力。
	return true, nil
}

func passwordLoginEnabled(db *gorm.DB, user model.User) bool {
	enabled, err := passwordLoginEnabledChecked(db, user)
	return err == nil && enabled
}

func (h *AuthHandler) PasswordStatus(c *gin.Context) {
	userID := c.GetUint("userID")
	var user model.User
	if err := h.DB.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "账号不存在"})
		return
	}
	enabled, err := passwordLoginEnabledChecked(h.DB, user)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "账号密码状态暂时无法确认"})
		return
	}
	c.Header("Cache-Control", "no-store")
	c.JSON(http.StatusOK, gin.H{
		"password_login_enabled": enabled,
		"login_username": func() string {
			if enabled { return user.Username }
			return ""
		}(),
	})
}

type updateProfileRequest struct {
	Nickname *string `json:"nickname" binding:"required"`
}

func (h *AuthHandler) UpdateProfile(c *gin.Context) {
	var req updateProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil || req.Nickname == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请填写昵称"})
		return
	}
	nickname := strings.TrimSpace(*req.Nickname)
	if utf8.RuneCountInString(nickname) < 1 || utf8.RuneCountInString(nickname) > 50 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "昵称应为 1–50 个字符"})
		return
	}
	userID := c.GetUint("userID")
	if err := h.DB.Model(&model.User{}).Where("id = ?", userID).Update("nickname", nickname).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "保存昵称失败"})
		return
	}
	var user model.User
	if err := h.DB.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "读取更新后资料失败"})
		return
	}
	c.Header("Cache-Control", "no-store")
	c.JSON(http.StatusOK, user)
}

var loginUsernamePattern = regexp.MustCompile(`^[a-zA-Z][a-zA-Z0-9_]{2,29}$`)

type setupPasswordRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

func validateAccountPassword(password string) bool {
	return len(password) >= 10 && len(password) <= 72
}

// GitHub 授权成功签发的 JWT 五分钟内允许设置独立登录凭据。
// 常规密码 JWT、旧 JWT、过期 JWT 都不能用于认领账号。
func recentlyVerifiedGitHub(c *gin.Context) bool {
	method, _ := c.Get("authMethod")
	issued, _ := c.Get("authIssuedAt")
	iat, ok := issued.(int64)
	age := time.Since(time.Unix(iat, 0))
	return method == "github" && ok && age >= 0 && age <= 5*time.Minute
}

func (h *AuthHandler) SetupPassword(c *gin.Context) {
	var req setupPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请填写登录账号及密码"})
		return
	}
	username := strings.TrimSpace(req.Username)
	if !loginUsernamePattern.MatchString(username) || strings.HasPrefix(strings.ToLower(username), "github_") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "账号须为 3–30 位字母、数字或下划线，以字母开头，不能使用系统保留前缀"})
		return
	}
	if !validateAccountPassword(req.Password) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "密码应为 10–72 字节"})
		return
	}
	if !recentlyVerifiedGitHub(c) {
		c.JSON(http.StatusForbidden, gin.H{"error": "请先重新完成 GitHub 身份验证"})
		return
	}
	hashed, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "密码处理失败"})
		return
	}
	userID := c.GetUint("userID")
	err = h.DB.Transaction(func(tx *gorm.DB) error {
		var user model.User
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&user, userID).Error; err != nil { return err }
		if passwordLoginEnabled(tx, user) { return errPasswordAlreadySet }
		var bound int64
		if err := tx.Model(&model.OAuthIdentity{}).
			Where("user_id = ? AND provider = ?", userID, "github").Count(&bound).Error; err != nil { return err }
		if bound != 1 { return errGitHubNotBound }
		var existing int64
		if err := tx.Model(&model.User{}).Where("username = ? AND id <> ?", username, userID).
			Count(&existing).Error; err != nil { return err }
		if existing != 0 { return errUsernameTaken }
		// 用列白名单写入，绝不改变 User.ID 或 OAuthIdentity.UserID。
		return tx.Model(&user).Updates(map[string]interface{}{
			"username": username, "password": string(hashed), "password_login_enabled": true,
		}).Error
	})
	if err != nil {
		switch {
		case errors.Is(err, errPasswordAlreadySet):
			c.JSON(http.StatusConflict, gin.H{"error": "账号密码已设置，不能重复认领账号"})
		case errors.Is(err, errGitHubNotBound):
			c.JSON(http.StatusForbidden, gin.H{"error": "当前账号没有有效 GitHub 绑定"})
		case errors.Is(err, errUsernameTaken), strings.Contains(strings.ToLower(err.Error()), "duplicate key"):
			c.JSON(http.StatusConflict, gin.H{"error": "登录账号已被使用"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "设置账号密码失败"})
		}
		return
	}
	c.Header("Cache-Control", "no-store")
	c.JSON(http.StatusOK, gin.H{"password_login_enabled": true, "login_username": username})
}

var (
	errPasswordAlreadySet = errors.New("password already set")
	errGitHubNotBound = errors.New("github not bound")
	errUsernameTaken = errors.New("username taken")
)

type changePasswordRequest struct {
	CurrentPassword string `json:"current_password" binding:"required"`
	NewPassword string `json:"new_password" binding:"required"`
}

func (h *AuthHandler) ChangePassword(c *gin.Context) {
	var req changePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil || !validateAccountPassword(req.NewPassword) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请填写原密码及 10–72 字节的新密码"})
		return
	}
	hashed, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "密码处理失败"})
		return
	}
	userID := c.GetUint("userID")
	err = h.DB.Transaction(func(tx *gorm.DB) error {
		var user model.User
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&user, userID).Error; err != nil { return err }
		if !passwordLoginEnabled(tx, user) ||
			bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(req.CurrentPassword)) != nil {
			return errInvalidCurrentPassword
		}
		return tx.Model(&user).Update("password", string(hashed)).Error
	})
	if err != nil {
		if errors.Is(err, errInvalidCurrentPassword) {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "原密码不正确"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "修改密码失败"})
		}
		return
	}
	c.Header("Cache-Control", "no-store")
	c.JSON(http.StatusOK, gin.H{"updated": true})
}

var errInvalidCurrentPassword = errors.New("invalid current password")
