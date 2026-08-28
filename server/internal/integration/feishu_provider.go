package integration

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"regexp"
	"strings"
	"time"
)

// FeishuProvider 飞书平台集成
type FeishuProvider struct{}

func init() {
	Register(&FeishuProvider{})
}

func (p *FeishuProvider) Name() string         { return "feishu" }
func (p *FeishuProvider) DisplayName() string   { return "飞书" }

// ===== 凭据验证 =====

func (p *FeishuProvider) ValidateCredentials(credentials map[string]interface{}) error {
	appID, _ := credentials["app_id"].(string)
	appSecret, _ := credentials["app_secret"].(string)
	if appID == "" || appSecret == "" {
		return fmt.Errorf("App ID 和 App Secret 不能为空")
	}
	_, err := getTenantToken(appID, appSecret)
	return err
}

// ===== 模板创建 =====

type bitableField struct {
	FieldName string      `json:"field_name"`
	Type      int         `json:"type"`
	Property  interface{} `json:"property,omitempty"`
}

func (p *FeishuProvider) CreateTemplate(credentials map[string]interface{}) (map[string]interface{}, error) {
	appID, _ := credentials["app_id"].(string)
	appSecret, _ := credentials["app_secret"].(string)
	token, err := getTenantToken(appID, appSecret)
	if err != nil {
		return nil, fmt.Errorf("获取飞书 token 失败: %v", err)
	}

	// 创建多维表格
	appToken, err := createBitable(token, "所行映我数据")
	if err != nil {
		return nil, fmt.Errorf("创建多维表格失败: %v", err)
	}

	// 定义各表字段
	tableDefs := getTableDefinitions()

	// 逐个创建表
	tableIDs := map[string]string{}
	for tableName, fields := range tableDefs {
		tableID, err := createTable(token, appToken, tableName, "全部"+strings.TrimRight(tableName, "表"), fields)
		if err != nil {
			return nil, fmt.Errorf("创建 %s 失败: %v", tableName, err)
		}
		tableIDs[tableName] = tableID
	}

	// 解析真实 URL
	bitableURL := resolveBitableURL(token, appToken, tableIDs["任务表"])

	return map[string]interface{}{
		"table_url":  bitableURL,
		"tables":     tableIDs,
		"app_token":  appToken,
	}, nil
}

// ===== 绑定已有表格 =====

func (p *FeishuProvider) ConnectExisting(credentials map[string]interface{}, resourceURL string) (map[string]interface{}, error) {
	appID, _ := credentials["app_id"].(string)
	appSecret, _ := credentials["app_secret"].(string)
	token, err := getTenantToken(appID, appSecret)
	if err != nil {
		return nil, fmt.Errorf("获取飞书 token 失败: %v", err)
	}

	appToken, _, err := parseTableURL(token, resourceURL)
	if err != nil {
		return nil, fmt.Errorf("解析表格链接失败: %v", err)
	}

	tables, err := listBitableTables(token, appToken)
	if err != nil {
		return nil, fmt.Errorf("获取数据表列表失败: %v", err)
	}

	// 自动识别表类型（通过字段名匹配）
	tableIDMap := map[string]string{}
	for _, table := range tables {
		fieldNames := map[string]bool{}
		for _, f := range table.Fields {
			fieldNames[f.FieldName] = true
		}
		tableType := identifyTableType(fieldNames)
		if tableType != "" {
			tableIDMap[tableType] = table.TableID
		}
	}

	return map[string]interface{}{
		"tables":    tableIDMap,
		"app_token": appToken,
	}, nil
}

// ===== 同步到外部平台 =====

func (p *FeishuProvider) SyncTo(credentials map[string]interface{}, tableIDs map[string]string, data *SyncData) (*SyncResult, error) {
	appID, _ := credentials["app_id"].(string)
	appSecret, _ := credentials["app_secret"].(string)
	token, err := getTenantToken(appID, appSecret)
	if err != nil {
		return nil, err
	}

	tableURL, _ := credentials["table_url"].(string)
	appToken, _, err := parseTableURL(token, tableURL)
	if err != nil {
		return nil, err
	}

	result := &SyncResult{Results: map[string]int{}}

	// 1. 同步任务
	if tableID := tableIDs["任务表"]; tableID != "" {
		records := make([]map[string]interface{}, 0, len(data.Tasks))
		for _, task := range data.Tasks {
			fields := map[string]interface{}{
				"标题":     task.Title,
				"描述":     task.Description,
				"清单":     task.ListName,
				"完成":     task.IsCompleted,
				"优先级":   priorityText(task.Priority),
				"创建时间": task.CreatedAt,
			}
			if task.DueDate != nil {
				fields["截止日期"] = *task.DueDate
			}
			if task.CompletedAt != nil {
				fields["完成时间"] = *task.CompletedAt
			}
			records = append(records, map[string]interface{}{"fields": fields})
		}
		if err := batchCreateRecords(token, appToken, tableID, records); err != nil {
			result.Errors = append(result.Errors, "任务表: "+err.Error())
		} else {
			result.Results["任务表"] = len(records)
		}
	}

	// 2. 同步番茄钟
	if tableID := tableIDs["番茄钟表"]; tableID != "" {
		records := make([]map[string]interface{}, 0, len(data.Sessions))
		for _, s := range data.Sessions {
			fields := map[string]interface{}{
				"类型":     sessionTypeName(s.Type),
				"开始时间": s.StartedAt,
				"时长(秒)": s.DurationSec,
				"设备":     s.Device,
			}
			if s.EndedAt != nil {
				fields["结束时间"] = *s.EndedAt
			}
			if s.TaskID != nil {
				fields["关联任务ID"] = *s.TaskID
			}
			records = append(records, map[string]interface{}{"fields": fields})
		}
		if err := batchCreateRecords(token, appToken, tableID, records); err != nil {
			result.Errors = append(result.Errors, "番茄钟表: "+err.Error())
		} else {
			result.Results["番茄钟表"] = len(records)
		}
	}

	// 3. 同步休息提醒
	if tableID := tableIDs["休息提醒表"]; tableID != "" {
		records := make([]map[string]interface{}, 0, len(data.Reminders))
		for _, s := range data.Reminders {
			fields := map[string]interface{}{
				"开始时间":     s.StartedAt,
				"工作时长(秒)": s.WorkSeconds,
				"休息时长(秒)": s.RestSeconds,
				"跳过休息":     s.SkippedRest,
				"设备":         s.Device,
			}
			if s.WorkEndedAt != nil {
				fields["工作结束"] = *s.WorkEndedAt
			}
			if s.RestEndedAt != nil {
				fields["休息结束"] = *s.RestEndedAt
			}
			records = append(records, map[string]interface{}{"fields": fields})
		}
		if err := batchCreateRecords(token, appToken, tableID, records); err != nil {
			result.Errors = append(result.Errors, "休息提醒表: "+err.Error())
		} else {
			result.Results["休息提醒表"] = len(records)
		}
	}

	// 4. 同步标签
	if tableID := tableIDs["标签表"]; tableID != "" {
		records := make([]map[string]interface{}, 0, len(data.Tags))
		for _, t := range data.Tags {
			fields := map[string]interface{}{
				"名称":      t.Name,
				"颜色":      t.Color,
				"关联任务数": t.TaskCount,
			}
			records = append(records, map[string]interface{}{"fields": fields})
		}
		if err := batchCreateRecords(token, appToken, tableID, records); err != nil {
			result.Errors = append(result.Errors, "标签表: "+err.Error())
		} else {
			result.Results["标签表"] = len(records)
		}
	}

	return result, nil
}

// ===== 从外部平台导入 =====

func (p *FeishuProvider) SyncFrom(credentials map[string]interface{}, tableIDs map[string]string) (*ImportResult, error) {
	appID, _ := credentials["app_id"].(string)
	appSecret, _ := credentials["app_secret"].(string)
	token, err := getTenantToken(appID, appSecret)
	if err != nil {
		return nil, err
	}

	tableURL, _ := credentials["table_url"].(string)
	appToken, _, err := parseTableURL(token, tableURL)
	if err != nil {
		return nil, err
	}

	tableID := tableIDs["任务表"]
	if tableID == "" {
		return nil, fmt.Errorf("未找到任务表")
	}

	records, err := listRecords(token, appToken, tableID)
	if err != nil {
		return nil, err
	}

	// 返回原始记录供 handler 处理
	log.Printf("[FeishuProvider.SyncFrom] got %d records", len(records))

	return &ImportResult{
		Imported: len(records),
		Message:  fmt.Sprintf("从飞书获取 %d 条记录", len(records)),
	}, nil
}

// ===== 日历同步 =====

func (p *FeishuProvider) ListCalendars(credentials map[string]interface{}) ([]CalendarInfo, error) {
	appID, _ := credentials["app_id"].(string)
	appSecret, _ := credentials["app_secret"].(string)
	token, err := getTenantToken(appID, appSecret)
	if err != nil {
		return nil, err
	}

	url := "https://open.feishu.cn/open-apis/calendar/v4/calendars?page_size=50"
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result struct {
		Code int `json:"code"`
		Msg  string `json:"msg"`
		Data struct {
			CalendarList []struct {
				CalendarID  string `json:"calendar_id"`
				Summary     string `json:"summary"`
				Description string `json:"description"`
				Role        string `json:"role"`
				Type        string `json:"type"`
			} `json:"calendar_list"`
		} `json:"data"`
	}
	json.NewDecoder(resp.Body).Decode(&result)

	if result.Code != 0 {
		return nil, fmt.Errorf("获取日历列表失败: %s (code: %d)", result.Msg, result.Code)
	}

	calendars := make([]CalendarInfo, 0, len(result.Data.CalendarList))
	for _, cal := range result.Data.CalendarList {
		calendars = append(calendars, CalendarInfo{
			ID:          cal.CalendarID,
			Name:        cal.Summary,
			Description: cal.Description,
			IsPrimary:   cal.Type == "primary",
			Role:        cal.Role,
		})
	}
	return calendars, nil
}

func (p *FeishuProvider) SyncToCalendar(credentials map[string]interface{}, calendarID string, data *CalendarSyncData) (*SyncResult, error) {
	appID, _ := credentials["app_id"].(string)
	appSecret, _ := credentials["app_secret"].(string)
	token, err := getTenantToken(appID, appSecret)
	if err != nil {
		return nil, err
	}

	result := &SyncResult{Results: map[string]int{}}
	created := 0

	for _, event := range data.Events {
		payload := map[string]interface{}{
			"summary":     event.Summary,
			"description": event.Description,
		}

		if event.IsAllDay {
			// 全天事件：使用 date 格式
			startDate := fmt.Sprintf("%d-%02d-%02d",
				time.Unix(event.StartTime, 0).Year(),
				time.Unix(event.StartTime, 0).Month(),
				time.Unix(event.StartTime, 0).Day())
			endDate := fmt.Sprintf("%d-%02d-%02d",
				time.Unix(event.EndTime, 0).Year(),
				time.Unix(event.EndTime, 0).Month(),
				time.Unix(event.EndTime, 0).Day())
			payload["start_time"] = map[string]string{"date": startDate}
			payload["end_time"] = map[string]string{"date": endDate}
		} else {
			// 有时区的事件
			payload["start_time"] = map[string]string{
				"timestamp": fmt.Sprintf("%d", event.StartTime),
				"timezone":  "Asia/Shanghai",
			}
			payload["end_time"] = map[string]string{
				"timestamp": fmt.Sprintf("%d", event.EndTime),
				"timezone":  "Asia/Shanghai",
			}
		}

		// 重复规则
		if event.RRule != "" {
			payload["recurrence"] = event.RRule
		}

		payloadJSON, _ := json.Marshal(payload)

		apiURL := fmt.Sprintf("https://open.feishu.cn/open-apis/calendar/v4/calendars/%s/events", calendarID)
		req, _ := http.NewRequest("POST", apiURL, bytes.NewBuffer(payloadJSON))
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("Content-Type", "application/json")

		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			result.Errors = append(result.Errors, fmt.Sprintf("%s: %v", event.Summary, err))
			continue
		}

		var respData struct {
			Code int    `json:"code"`
			Msg  string `json:"msg"`
		}
		json.NewDecoder(resp.Body).Decode(&respData)
		resp.Body.Close()

		if respData.Code != 0 {
			result.Errors = append(result.Errors, fmt.Sprintf("%s: %s (code: %d)", event.Summary, respData.Msg, respData.Code))
			continue
		}
		created++
	}

	result.Results["日历事件"] = created
	return result, nil
}

// ===== 飞书 API 方法 =====

type feishuToken struct {
	Code              int    `json:"code"`
	TenantAccessToken string `json:"tenant_access_token"`
	Msg               string `json:"msg"`
}

func getTenantToken(appID, appSecret string) (string, error) {
	url := "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal"
	body := map[string]string{"app_id": appID, "app_secret": appSecret}
	bodyJSON, _ := json.Marshal(body)

	resp, err := http.Post(url, "application/json", bytes.NewBuffer(bodyJSON))
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var tokenResp feishuToken
	json.NewDecoder(resp.Body).Decode(&tokenResp)
	if tokenResp.Code != 0 {
		return "", fmt.Errorf("飞书认证失败: %s", tokenResp.Msg)
	}
	return tokenResp.TenantAccessToken, nil
}

func parseTableURL(token, tableURL string) (appToken, tableID string, err error) {
	re := regexp.MustCompile(`feishu\.(cn|com)/(?:base|wiki)/([a-zA-Z0-9]+)`)
	matches := re.FindStringSubmatch(tableURL)
	if len(matches) < 3 {
		return "", "", fmt.Errorf("无法从 URL 解析 app_token: %s", tableURL)
	}
	appToken = matches[2]

	tableRe := regexp.MustCompile(`[?&]table=([a-zA-Z0-9]+)`)
	tableMatches := tableRe.FindStringSubmatch(tableURL)
	if len(tableMatches) >= 2 {
		tableID = tableMatches[1]
	}

	if tableID == "" {
		tableID, err = getFirstTableID(token, appToken)
		if err != nil {
			return appToken, "", err
		}
	}
	return appToken, tableID, nil
}

func getFirstTableID(token, appToken string) (string, error) {
	url := fmt.Sprintf("https://open.feishu.cn/open-apis/bitable/v1/apps/%s/tables?page_size=1", appToken)
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var result struct {
		Code int `json:"code"`
		Data struct {
			Items []struct {
				TableID string `json:"table_id"`
			} `json:"items"`
		} `json:"data"`
	}
	json.NewDecoder(resp.Body).Decode(&result)

	if result.Code != 0 {
		return "", fmt.Errorf("获取数据表失败，code: %d", result.Code)
	}
	if len(result.Data.Items) == 0 {
		return "", fmt.Errorf("多维表格中没有数据表")
	}
	return result.Data.Items[0].TableID, nil
}

func createBitable(token, name string) (string, error) {
	url := "https://open.feishu.cn/open-apis/bitable/v1/apps"
	body := map[string]interface{}{"name": name}
	bodyJSON, _ := json.Marshal(body)

	req, _ := http.NewRequest("POST", url, bytes.NewBuffer(bodyJSON))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var result struct {
		Code int `json:"code"`
		Msg  string `json:"msg"`
		Data struct {
			App struct {
				AppToken string `json:"app_token"`
			} `json:"app"`
		} `json:"data"`
	}
	json.NewDecoder(resp.Body).Decode(&result)

	if result.Code != 0 {
		log.Printf("[createBitable] code=%d msg=%s", result.Code, result.Msg)
		return "", fmt.Errorf("创建多维表格失败 (code: %d): %s", result.Code, result.Msg)
	}
	return result.Data.App.AppToken, nil
}

func createTable(token, appToken, name, defaultViewName string, fields []bitableField) (string, error) {
	url := fmt.Sprintf("https://open.feishu.cn/open-apis/bitable/v1/apps/%s/tables", appToken)

	fieldDefs := make([]map[string]interface{}, 0, len(fields))
	for _, f := range fields {
		def := map[string]interface{}{
			"field_name": f.FieldName,
			"type":       f.Type,
		}
		if f.Property != nil {
			def["property"] = f.Property
		}
		fieldDefs = append(fieldDefs, def)
	}

	body := map[string]interface{}{
		"table": map[string]interface{}{
			"name":                name,
			"default_view_name":   defaultViewName,
			"fields":              fieldDefs,
		},
	}
	bodyJSON, _ := json.Marshal(body)

	req, _ := http.NewRequest("POST", url, bytes.NewBuffer(bodyJSON))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var result struct {
		Code int `json:"code"`
		Msg  string `json:"msg"`
		Data struct {
			TableID string `json:"table_id"`
		} `json:"data"`
	}
	json.NewDecoder(resp.Body).Decode(&result)

	if result.Code != 0 {
		log.Printf("[createTable] name=%s code=%d msg=%s", name, result.Code, result.Msg)
		return "", fmt.Errorf("创建表 %s 失败 (code: %d): %s", name, result.Code, result.Msg)
	}
	return result.Data.TableID, nil
}

func createRecord(token, appToken, tableID string, fields map[string]interface{}) error {
	url := fmt.Sprintf("https://open.feishu.cn/open-apis/bitable/v1/apps/%s/tables/%s/records", appToken, tableID)
	body := map[string]interface{}{"fields": fields}
	bodyJSON, _ := json.Marshal(body)

	req, _ := http.NewRequest("POST", url, bytes.NewBuffer(bodyJSON))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	var result struct {
		Code int    `json:"code"`
		Msg  string `json:"msg"`
	}
	json.NewDecoder(resp.Body).Decode(&result)

	if result.Code != 0 {
		return fmt.Errorf("创建记录失败: %s (code: %d)", result.Msg, result.Code)
	}
	return nil
}

func batchCreateRecords(token, appToken, tableID string, records []map[string]interface{}) error {
	if len(records) == 0 {
		return nil
	}
	for i := 0; i < len(records); i += 500 {
		end := i + 500
		if end > len(records) {
			end = len(records)
		}
		batch := records[i:end]

		url := fmt.Sprintf("https://open.feishu.cn/open-apis/bitable/v1/apps/%s/tables/%s/records/batch_create", appToken, tableID)
		body := map[string]interface{}{"records": batch}
		bodyJSON, _ := json.Marshal(body)

		req, _ := http.NewRequest("POST", url, bytes.NewBuffer(bodyJSON))
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("Content-Type", "application/json")

		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			return err
		}
		resp.Body.Close()

		var result struct {
			Code int    `json:"code"`
			Msg  string `json:"msg"`
		}
		json.NewDecoder(resp.Body).Decode(&result)
		if result.Code != 0 {
			return fmt.Errorf("批量创建记录失败: %s (code: %d)", result.Msg, result.Code)
		}
	}
	return nil
}

func listRecords(token, appToken, tableID string) ([]map[string]interface{}, error) {
	url := fmt.Sprintf("https://open.feishu.cn/open-apis/bitable/v1/apps/%s/tables/%s/records?page_size=500", appToken, tableID)
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result struct {
		Code int `json:"code"`
		Data struct {
			Items []map[string]interface{} `json:"items"`
		} `json:"data"`
	}
	json.NewDecoder(resp.Body).Decode(&result)

	if result.Code != 0 {
		return nil, fmt.Errorf("获取记录失败，code: %d", result.Code)
	}
	return result.Data.Items, nil
}

type bitableTableInfo struct {
	TableID string `json:"table_id"`
	Name    string `json:"name"`
	Fields  []struct {
		FieldName string `json:"field_name"`
		Type      int    `json:"type"`
	} `json:"fields"`
}

func listBitableTables(token, appToken string) ([]bitableTableInfo, error) {
	url := fmt.Sprintf("https://open.feishu.cn/open-apis/bitable/v1/apps/%s/tables?page_size=100", appToken)
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result struct {
		Code int `json:"code"`
		Data struct {
			Items []bitableTableInfo `json:"items"`
		} `json:"data"`
	}
	json.NewDecoder(resp.Body).Decode(&result)

	if result.Code != 0 {
		return nil, fmt.Errorf("获取表列表失败，code: %d", result.Code)
	}

	// 为每个表获取字段列表
	for i := range result.Data.Items {
		fields, err := getTableFields(token, appToken, result.Data.Items[i].TableID)
		if err == nil {
			result.Data.Items[i].Fields = fields
		}
	}

	return result.Data.Items, nil
}

func getTableFields(token, appToken, tableID string) ([]struct {
	FieldName string `json:"field_name"`
	Type      int    `json:"type"`
}, error) {
	url := fmt.Sprintf("https://open.feishu.cn/open-apis/bitable/v1/apps/%s/tables/%s/fields?page_size=100", appToken, tableID)
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result struct {
		Code int `json:"code"`
		Data struct {
			Items []struct {
				FieldName string `json:"field_name"`
				Type      int    `json:"type"`
			} `json:"items"`
		} `json:"data"`
	}
	json.NewDecoder(resp.Body).Decode(&result)

	if result.Code != 0 {
		return nil, fmt.Errorf("获取字段列表失败，code: %d", result.Code)
	}
	return result.Data.Items, nil
}

func resolveBitableURL(token, appToken, tableID string) string {
	return fmt.Sprintf("https://your-domain.feishu.cn/base/%s?table=%s", appToken, tableID)
}

// ===== 工具函数 =====

func priorityText(priority string) string {
	switch priority {
	case "urgent_important":
		return "重要紧急"
	case "important":
		return "重要"
	case "urgent":
		return "紧急"
	default:
		return "无"
	}
}

func sessionTypeName(t string) string {
	switch t {
	case "break":
		return "短休息"
	case "long_break":
		return "长休息"
	default:
		return "工作"
	}
}

// identifyTableType 通过字段名识别表类型
func identifyTableType(fieldNames map[string]bool) string {
	switch {
	case fieldNames["标题"] && fieldNames["清单"]:
		return "任务表"
	case fieldNames["名称"] && fieldNames["颜色"] && fieldNames["图标"] && !fieldNames["频率"]:
		return "清单表"
	case fieldNames["名称"] && fieldNames["频率"]:
		return "习惯表"
	case fieldNames["类型"] && fieldNames["开始时间"] && fieldNames["时长(秒)"]:
		return "番茄钟表"
	case fieldNames["工作结束"] || (fieldNames["工作时长(秒)"] && fieldNames["休息时长(秒)"]):
		return "休息提醒表"
	case fieldNames["关联任务数"]:
		return "标签表"
	default:
		return ""
	}
}

// getTableDefinitions 返回所有表的字段定义
func getTableDefinitions() map[string][]bitableField {
	return map[string][]bitableField{
		"任务表": {
			{FieldName: "标题", Type: 1},
			{FieldName: "描述", Type: 1},
			{FieldName: "清单", Type: 3, Property: map[string]interface{}{"options": []map[string]interface{}{
				{"name": "工作"}, {"name": "生活"}, {"name": "学习"},
			}}},
			{FieldName: "优先级", Type: 3, Property: map[string]interface{}{"options": []map[string]interface{}{
				{"name": "重要紧急"}, {"name": "重要"}, {"name": "紧急"}, {"name": "无"},
			}}},
			{FieldName: "状态", Type: 3, Property: map[string]interface{}{"options": []map[string]interface{}{
				{"name": "进行中"}, {"name": "已完成"},
			}}},
			{FieldName: "截止日期", Type: 5},
			{FieldName: "完成时间", Type: 5},
			{FieldName: "创建时间", Type: 1001},
			{FieldName: "标签", Type: 4},
		},
		"清单表": {
			{FieldName: "名称", Type: 1},
			{FieldName: "颜色", Type: 1},
			{FieldName: "图标", Type: 1},
			{FieldName: "排序", Type: 2},
		},
		"习惯表": {
			{FieldName: "名称", Type: 1},
			{FieldName: "图标", Type: 1},
			{FieldName: "颜色", Type: 1},
			{FieldName: "频率", Type: 3, Property: map[string]interface{}{"options": []map[string]interface{}{
				{"name": "每天"}, {"name": "每周"}, {"name": "每月"},
			}}},
			{FieldName: "连续天数", Type: 2},
			{FieldName: "目标天数", Type: 2},
		},
		"番茄钟表": {
			{FieldName: "类型", Type: 3, Property: map[string]interface{}{"options": []map[string]interface{}{
				{"name": "工作"}, {"name": "短休息"}, {"name": "长休息"},
			}}},
			{FieldName: "开始时间", Type: 5},
			{FieldName: "结束时间", Type: 5},
			{FieldName: "时长(秒)", Type: 2},
			{FieldName: "设备", Type: 1},
			{FieldName: "关联任务ID", Type: 2},
		},
		"休息提醒表": {
			{FieldName: "开始时间", Type: 5},
			{FieldName: "工作结束", Type: 5},
			{FieldName: "休息结束", Type: 5},
			{FieldName: "工作时长(秒)", Type: 2},
			{FieldName: "休息时长(秒)", Type: 2},
			{FieldName: "跳过休息", Type: 7},
			{FieldName: "设备", Type: 1},
		},
		"标签表": {
			{FieldName: "名称", Type: 1},
			{FieldName: "颜色", Type: 1},
			{FieldName: "关联任务数", Type: 2},
		},
	}
}
