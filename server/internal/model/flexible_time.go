package model

import (
	"database/sql/driver"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"time"
)

// 北京时区（缓存，避免重复加载）
var (
	_beijingTZ   *time.Location
	_beijingOnce sync.Once
)

func BeijingLocation() *time.Location {
	_beijingOnce.Do(func() {
		var err error
		_beijingTZ, err = time.LoadLocation("Asia/Shanghai")
		if err != nil {
			_beijingTZ = time.FixedZone("CST", 8*60*60) // 降级为 UTC+8
		}
	})
	return _beijingTZ
}


// UserLocation 根据用户时区字符串返回 time.Location
// 支持 IANA 时区名（如 "Asia/Shanghai"）和固定偏移（如 "UTC+8"）
func UserLocation(tz string) *time.Location {
	if tz == "" {
		return BeijingLocation()
	}
	loc, err := time.LoadLocation(tz)
	if err != nil {
		return BeijingLocation() // 降级
	}
	return loc
}

// FlexibleTime 自定义时间类型，支持多种 JSON 格式解析：
// - ISO 8601 完整格式: "2026-04-14T00:00:00.000Z"
// - 纯日期格式: "2026-04-14"
// - 空字符串: "" (解析为零值)
// - null: 解析为零值
type FlexibleTime struct {
	time.Time
	Valid bool
}

func (ft *FlexibleTime) UnmarshalJSON(data []byte) error {
	// 处理 null
	if string(data) == "null" {
		ft.Valid = false
		ft.Time = time.Time{}
		return nil
	}

	// 去掉引号
	s := strings.Trim(string(data), `"`)
	if s == "" {
		ft.Valid = false
		ft.Time = time.Time{}
		return nil
	}

	// 尝试 ISO 8601 格式
	if t, err := time.Parse(time.RFC3339, s); err == nil {
		ft.Time = t
		ft.Valid = true
		return nil
	}

	// 尝试带毫秒的 ISO 8601
	if t, err := time.Parse("2006-01-02T15:04:05.000Z", s); err == nil {
		ft.Time = t
		ft.Valid = true
		return nil
	}

	// 尝试纯日期格式（用北京时间解析，存入数据库为 UTC）
	if t, err := time.ParseInLocation("2006-01-02", s, BeijingLocation()); err == nil {
		ft.Time = t.UTC()
		ft.Valid = true
		return nil
	}

	return fmt.Errorf("cannot parse time: %q", s)
}

func (ft FlexibleTime) MarshalJSON() ([]byte, error) {
	if !ft.Valid {
		return []byte("null"), nil
	}
	return json.Marshal(ft.Time.Format(time.RFC3339))
}

func (ft FlexibleTime) Value() (driver.Value, error) {
	if !ft.Valid {
		return nil, nil
	}
	return ft.Time, nil
}

func (ft *FlexibleTime) Scan(value interface{}) error {
	if value == nil {
		ft.Valid = false
		ft.Time = time.Time{}
		return nil
	}
	switch v := value.(type) {
	case time.Time:
		ft.Time = v
		ft.Valid = true
		return nil
	default:
		return fmt.Errorf("cannot scan FlexibleTime from %T", value)
	}
}
