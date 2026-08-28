package integration

import (
	"io"
	"net/http"
	"strings"
	"testing"
)

func TestDecodeFeishuResponseRejectsNon2xx(t *testing.T) {
	resp := &http.Response{
		StatusCode: http.StatusBadGateway,
		Body:       io.NopCloser(strings.NewReader(`{"code":0}`)),
	}
	var target map[string]interface{}
	if err := decodeFeishuResponse(resp, &target); err == nil {
		t.Fatal("非 2xx 飞书响应必须失败")
	}
}

func TestDecodeFeishuResponseRejectsInvalidJSON(t *testing.T) {
	resp := &http.Response{
		StatusCode: http.StatusOK,
		Body:       io.NopCloser(strings.NewReader(`not-json`)),
	}
	var target map[string]interface{}
	if err := decodeFeishuResponse(resp, &target); err == nil {
		t.Fatal("无法解析的飞书响应必须失败")
	}
}

func TestSafeFeishuProviderBlocksCloudExport(t *testing.T) {
	provider := newSafeFeishuProvider(&FeishuProvider{})
	if _, err := provider.SyncTo(nil, nil, &SyncData{}); err == nil {
		t.Fatal("公开预览阶段不得执行会重复创建记录的云端飞书导出")
	}
	if _, err := provider.SyncToCalendar(nil, "calendar", &CalendarSyncData{}); err == nil {
		t.Fatal("公开预览阶段不得执行非幂等的云端飞书日历同步")
	}
}

func TestRegisteredFeishuProviderUsesSafetyBoundary(t *testing.T) {
	provider, err := Get("feishu")
	if err != nil {
		t.Fatalf("获取飞书 Provider 失败: %v", err)
	}
	if _, ok := provider.(*safeFeishuProvider); !ok {
		t.Fatalf("飞书 Provider 未经过公开预览安全边界: %T", provider)
	}
}
