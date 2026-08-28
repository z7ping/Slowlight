package handler

import (
	"errors"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"

	"slowlight/internal/model"
)

type AuthHandler struct {
	DB *gorm.DB
}

func NewAuthHandler(db *gorm.DB) *AuthHandler {
	return &AuthHandler{DB: db}
}

type RegisterRequest struct {
	Username string `json:"username" binding:"required,min=3,max=50"`
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=6"`
	Nickname string `json:"nickname"`
}

type LoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

type AuthResponse struct {
	Token string     `json:"token"`
	User  model.User `json:"user"`
}

func (h *AuthHandler) Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var existing model.User
	if h.DB.Where("username = ?", req.Username).First(&existing).RowsAffected > 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "用户名已存在"})
		return
	}
	if h.DB.Where("email = ?", req.Email).First(&existing).RowsAffected > 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "邮箱已注册"})
		return
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "密码加密失败"})
		return
	}

	nickname := req.Nickname
	if nickname == "" {
		nickname = req.Username
	}
	user := model.User{
		Username: req.Username,
		Email:    req.Email,
		Password: string(hashedPassword),
		Nickname: nickname,
	}
	if err := h.DB.Create(&user).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建用户失败"})
		return
	}

	defaultLists := []model.List{
		{UserID: user.ID, Name: "工作", Icon: "💼", Color: "#1890ff", SortOrder: 1},
		{UserID: user.ID, Name: "生活", Icon: "🏠", Color: "#52c41a", SortOrder: 2},
		{UserID: user.ID, Name: "学习", Icon: "📚", Color: "#722ed1", SortOrder: 3},
	}
	h.DB.Create(&defaultLists)

	// 默认 SystemTag 保留为分类标签，同时显式映射到固定 Dimension。
	defaultTags := []model.SystemTag{
		{UserID: user.ID, Name: "身体", Icon: "💪", Color: "#52c41a", DimensionKey: model.DimensionBody, SortOrder: 1, IsDefault: true},
		{UserID: user.ID, Name: "认知", Icon: "🧠", Color: "#1890ff", DimensionKey: model.DimensionCognition, SortOrder: 2, IsDefault: true},
		{UserID: user.ID, Name: "产出", Icon: "🎯", Color: "#722ed1", DimensionKey: model.DimensionOutput, SortOrder: 3, IsDefault: true},
		{UserID: user.ID, Name: "关系", Icon: "❤️", Color: "#eb2f96", DimensionKey: model.DimensionRelationship, SortOrder: 4, IsDefault: true},
	}
	h.DB.Create(&defaultTags)

	token, err := generateToken(user.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "生成 token 失败"})
		return
	}
	c.JSON(http.StatusCreated, AuthResponse{Token: token, User: user})
}

func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	var user model.User
	if err := h.DB.Where("username = ?", req.Username).First(&user).Error; err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "用户名或密码错误"})
		return
	}
	if err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(req.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "用户名或密码错误"})
		return
	}
	token, err := generateToken(user.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "生成 token 失败"})
		return
	}
	c.JSON(http.StatusOK, AuthResponse{Token: token, User: user})
}

func (h *AuthHandler) GetProfile(c *gin.Context) {
	userID := c.GetUint("userID")
	var user model.User
	if err := h.DB.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "用户不存在"})
		return
	}
	c.JSON(http.StatusOK, user)
}

func jwtSigningSecret() ([]byte, error) {
	secret := os.Getenv("JWT_SECRET")
	if secret == "" {
		return nil, errors.New("JWT_SECRET environment variable is required")
	}
	return []byte(secret), nil
}

func generateToken(userID uint) (string, error) {
	secret, err := jwtSigningSecret()
	if err != nil {
		return "", err
	}
	claims := jwt.MapClaims{
		"user_id": userID,
		"exp":     time.Now().Add(7 * 24 * time.Hour).Unix(),
		"iat":     time.Now().Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(secret)
}

func AuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "未提供认证信息"})
			c.Abort()
			return
		}
		tokenString := authHeader
		if len(authHeader) > 7 && authHeader[:7] == "Bearer " {
			tokenString = authHeader[7:]
		}
		secret, err := jwtSigningSecret()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "服务端认证未配置"})
			c.Abort()
			return
		}
		token, err := jwt.Parse(
			tokenString,
			func(token *jwt.Token) (interface{}, error) {
				return secret, nil
			},
			jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		)
		if err != nil || !token.Valid {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "无效的 token"})
			c.Abort()
			return
		}
		claims, ok := token.Claims.(jwt.MapClaims)
		if !ok {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "无效的 token claims"})
			c.Abort()
			return
		}
		rawUserID, ok := claims["user_id"].(float64)
		if !ok {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "无效的 token claims"})
			c.Abort()
			return
		}
		c.Set("userID", uint(rawUserID))
		c.Next()
	}
}
