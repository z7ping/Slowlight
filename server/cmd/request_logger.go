package main

import (
	"fmt"
	"strings"

	"github.com/gin-gonic/gin"
)

// OAuth 回调的查询参数含一次性授权码和 state，不能进入访问日志。
func requestLogFormatter(p gin.LogFormatterParams) string {
	path := p.Path
	if strings.HasPrefix(path, "/api/auth/github/callback?") {
		path = "/api/auth/github/callback"
	}
	return fmt.Sprintf("[GIN] %s | %3d | %13v | %15s | %-7s %q\n",
		p.TimeStamp.Format("2006/01/02 - 15:04:05"), p.StatusCode, p.Latency, p.ClientIP, p.Method, path)
}
