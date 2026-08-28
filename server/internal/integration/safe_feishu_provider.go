package integration

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

// safeFeishuProvider 是公开预览阶段的云端飞书安全边界。
//
// 旧服务端导出实现使用 batch_create，每次同步都会追加记录；在建立稳定的
// remote record mapping / upsert 语义之前，宁可明确拒绝云端导出，也不能让用户
// 得到“同步成功”却产生重复数据。Local Data 模式已有独立的幂等 upsert 实现，
// 不受此限制。
type safeFeishuProvider struct {
	delegate Provider
	client   *http.Client
}

func newSafeFeishuProvider(delegate Provider) Provider {
	return &safeFeishuProvider{
		delegate: delegate,
		client:   &http.Client{Timeout: 15 * time.Second},
	}
}

func (p *safeFeishuProvider) Name() string         { return p.delegate.Name() }
func (p *safeFeishuProvider) DisplayName() string { return p.delegate.DisplayName() }

func (p *safeFeishuProvider) ValidateCredentials(credentials map[string]interface{}) error {
	appID, _ := credentials["app_id"].(string)
	appSecret, _ := credentials["app_secret"].(string)
	if strings.TrimSpace(appID) == "" || strings.TrimSpace(appSecret) == "" {
		return fmt.Errorf("App ID 和 App Secret 不能为空")
	}

	body, err := json.Marshal(map[string]string{
		"app_id":     appID,
		"app_secret": appSecret,
	})
	if err != nil {
		return fmt.Errorf("构造飞书认证请求失败: %w", err)
	}
	req, err := http.NewRequest(
		http.MethodPost,
		"https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal",
		bytes.NewReader(body),
	)
	if err != nil {
		return fmt.Errorf("创建飞书认证请求失败: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := p.client.Do(req)
	if err != nil {
		return fmt.Errorf("飞书认证请求失败: %w", err)
	}
	defer resp.Body.Close()

	var result struct {
		Code              int    `json:"code"`
		Msg               string `json:"msg"`
		TenantAccessToken string `json:"tenant_access_token"`
	}
	if err := decodeFeishuResponse(resp, &result); err != nil {
		return fmt.Errorf("飞书认证响应无效: %w", err)
	}
	if result.Code != 0 {
		return fmt.Errorf("飞书认证失败: %s (code: %d)", result.Msg, result.Code)
	}
	if strings.TrimSpace(result.TenantAccessToken) == "" {
		return fmt.Errorf("飞书认证响应缺少访问令牌")
	}
	return nil
}

func (p *safeFeishuProvider) CreateTemplate(credentials map[string]interface{}) (map[string]interface{}, error) {
	result, err := p.delegate.CreateTemplate(credentials)
	if err != nil {
		return nil, err
	}

	appToken, _ := result["app_token"].(string)
	tables, _ := result["tables"].(map[string]string)
	if strings.TrimSpace(appToken) == "" || len(tables) == 0 || strings.TrimSpace(tables["任务表"]) == "" {
		return nil, fmt.Errorf("飞书模板创建响应不完整，未保存不确定结果")
	}

	// 不返回伪造的 your-domain.feishu.cn 链接；使用可打开的通用 Base 链接。
	result["table_url"] = fmt.Sprintf(
		"https://feishu.cn/base/%s?table=%s",
		appToken,
		tables["任务表"],
	)
	return result, nil
}

func (p *safeFeishuProvider) ConnectExisting(credentials map[string]interface{}, resourceURL string) (map[string]interface{}, error) {
	result, err := p.delegate.ConnectExisting(credentials, resourceURL)
	if err != nil {
		return nil, err
	}
	tables, _ := result["tables"].(map[string]string)
	if len(tables) == 0 || strings.TrimSpace(tables["任务表"]) == "" {
		return nil, fmt.Errorf("未识别到可同步的任务表，拒绝保存不完整绑定")
	}
	return result, nil
}

func (p *safeFeishuProvider) SyncTo(credentials map[string]interface{}, tableIDs map[string]string, data *SyncData) (*SyncResult, error) {
	return nil, fmt.Errorf("云端模式飞书导出暂未开放：旧实现会重复创建记录；请使用 Local Data 模式的本机飞书同步")
}

func (p *safeFeishuProvider) SyncFrom(credentials map[string]interface{}, tableIDs map[string]string) (*ImportResult, error) {
	return nil, fmt.Errorf("飞书导入尚未开放")
}

func (p *safeFeishuProvider) ListCalendars(credentials map[string]interface{}) ([]CalendarInfo, error) {
	// 列表本身是只读操作，可继续使用；delegate 返回异常时会显式失败。
	return p.delegate.ListCalendars(credentials)
}

func (p *safeFeishuProvider) SyncToCalendar(credentials map[string]interface{}, calendarID string, data *CalendarSyncData) (*SyncResult, error) {
	return nil, fmt.Errorf("云端模式飞书日历同步暂未开放：当前实现无法保证重复执行不产生重复事件")
}

func decodeFeishuResponse(resp *http.Response, target interface{}) error {
	if resp == nil {
		return fmt.Errorf("空 HTTP 响应")
	}
	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusMultipleChoices {
		return fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	if err := json.NewDecoder(resp.Body).Decode(target); err != nil {
		return fmt.Errorf("JSON 解析失败: %w", err)
	}
	return nil
}
